#!/usr/bin/env bash
# Controleert de eindopdracht van module 15.
# Gebruik: ./check.sh

fouten=0
ok()   { printf "  \033[32m✔\033[0m %s\n" "$1"; }
fout() { printf "  \033[31m✘\033[0m %s\n" "$1"; [ -n "$2" ] && printf "      → %s\n" "$2"; fouten=$((fouten + 1)); }

repo="$(cd "$(dirname "$0")/../.." && pwd)"
context=${CONTEXT:-kind-snip}
k() { kubectl --context "$context" "$@"; }

echo
echo "Module 15 — Teams en grenzen"
echo

if [ -z "$CONTEXT" ] && [ "$(kubectl config current-context 2>/dev/null)" != "kind-snip" ]; then
  fout "actieve context is '$(kubectl config current-context 2>/dev/null)'" "kubectl config use-context kind-snip"
fi
if ! k get nodes >/dev/null 2>&1; then
  fout "cluster $context niet bereikbaar" "podman start snip-control-plane"
  echo; exit 1
fi

# --- bestanden ------------------------------------------------------------
echo "bestanden"
for f in k8s/base/networkpolicy.yaml k8s/platform/namespaces/snip-test.yaml k8s/platform/namespaces/default.yaml; do
  [ -f "$repo/$f" ] || fout "$f niet gevonden"
done
if kubectl kustomize "$repo/k8s/base" 2>/dev/null | grep -q "kind: NetworkPolicy"; then
  ok "de base bevat NetworkPolicies"
else
  fout "k8s/base/kustomization.yaml noemt networkpolicy.yaml niet" "Stap 8."
fi

# --- rechten --------------------------------------------------------------
echo
echo "rechten (RBAC)"
dev() { k auth can-i "$@" --as=jan --as-group=snip-devs 2>/dev/null; }
[ "$(dev delete pods -n snip-test)" = "yes" ] \
  && ok "snip-devs mag in snip-test alles met de app" || fout "snip-devs mag in snip-test geen pods weggooien" "RoleBinding met edit (stap 3)"
[ "$(dev get pods -n default)" = "yes" ] && [ "$(dev delete pods -n default)" = "no" ] \
  && ok "snip-devs mag in prod (default) alleen kijken" || fout "snip-devs heeft in default niet precies view" "Stap 3."
[ "$(dev get secrets -n default)" = "no" ] \
  && ok "snip-devs kan de wachtwoorden in prod niet lezen" || fout "snip-devs kan Secrets in default lezen"
sa=system:serviceaccount:snip-test:deployer
ci() { k auth can-i "$@" --as=$sa 2>/dev/null; }
[ "$(ci patch deployments -n snip-test)" = "yes" ] \
  && ok "deployer mag Deployments bijwerken" || fout "deployer mag geen Deployments bijwerken in snip-test" "Stap 4."
[ "$(ci delete deployments -n snip-test)" = "no" ] && [ "$(ci get secrets -n snip-test)" = "no" ] \
  && [ "$(ci patch deployments -n default)" = "no" ] \
  && ok "deployer mag verder niets" || fout "deployer mag te veel (weggooien, Secrets of een andere namespace)" "Stap 4."

# --- grenzen --------------------------------------------------------------
echo
echo "grenzen (quota)"
k get resourcequota -n snip-test -o name 2>/dev/null | grep -q . \
  && ok "ResourceQuota in snip-test" || fout "geen ResourceQuota in snip-test" "Stap 5."
k get limitrange -n snip-test -o name 2>/dev/null | grep -q . \
  && ok "LimitRange in snip-test" || fout "geen LimitRange in snip-test" "Stap 5."

# --- netwerk --------------------------------------------------------------
echo
echo "netwerk (NetworkPolicies)"
for ns in default snip-test; do
  n=$(k get networkpolicy -n "$ns" -o name 2>/dev/null | wc -l | tr -d ' ')
  [ "$n" -ge 4 ] && ok "$ns: $n NetworkPolicies" || fout "$ns: $n NetworkPolicies, verwacht 4" "Stap 8."
done
for o in prod test; do
  k diff -k "$repo/k8s/overlays/$o" >/dev/null 2>&1 \
    && ok "het cluster is gelijk aan k8s/overlays/$o" || fout "het cluster wijkt af van k8s/overlays/$o" "kubectl diff -k k8s/overlays/$o"
done
uit=$(k run check-indringer --image=postgres:18-alpine --restart=Never --rm -i --quiet -- \
  pg_isready -h snip-db.snip-test -t 3 2>/dev/null)
case "$uit" in
  *accepting*) fout "vanuit prod kun je nog bij de database van test" "Stap 8." ;;
  *) ok "vanuit prod kun je niet bij de database van test" ;;
esac
for ns in default snip-test; do
  envoy=$(k get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-namespace=$ns -o name 2>/dev/null | head -1)
  [ -z "$envoy" ] && { fout "geen Envoy voor $ns"; continue; }
  poort=18$((RANDOM % 900 + 100))
  k port-forward -n envoy-gateway-system "$envoy" "$poort:80" >/dev/null 2>&1 &
  tunnel=$!; sleep 3
  links=$(curl -s --max-time 3 "localhost:$poort/api/links")
  kort=$(curl -s --max-time 3 -o /dev/null -w "%{http_code}" "localhost:$poort/gh")
  { kill "$tunnel"; wait "$tunnel"; } 2>/dev/null
  echo "$links" | grep -q '"code":"gh"' && [ "$kort" = "302" ] \
    && ok "$ns: website, /api en korte links werken nog" \
    || fout "$ns: snip werkt niet meer via de voordeur" "Kijk welke policy het verkeer tegenhoudt (stap 8)."
done

# --- cilium (optioneel) ---------------------------------------------------
echo
echo "Cilium (deel D, optioneel)"
if kubectl --context kind-cilium get nodes >/dev/null 2>&1; then
  c() { kubectl --context kind-cilium "$@"; }
  [ "$(c get ds -n kube-system cilium -o jsonpath='{.status.numberReady}' 2>/dev/null)" -ge 1 ] 2>/dev/null \
    && ok "Cilium draait" || fout "Cilium draait niet in kind-cilium" "Stap 10."
  c get ciliumnetworkpolicy -n snip -o name 2>/dev/null | grep -q . \
    && ok "CiliumNetworkPolicy in namespace snip" || fout "geen CiliumNetworkPolicy in snip" "Stap 12."
else
  echo "  – overgeslagen (geen cluster kind-cilium)"
fi

echo
if [ "$fouten" -eq 0 ]; then
  printf "\033[32mGeslaagd! Door naar module 16.\033[0m\n\n"
else
  printf "\033[31m%d punt(en) nog niet in orde.\033[0m\n\n" "$fouten"
  exit 1
fi
