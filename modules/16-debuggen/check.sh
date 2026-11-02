#!/usr/bin/env bash
# Controleert de eindopdracht van module 16.
# Gebruik: ./check.sh

fouten=0
ok()   { printf "  \033[32m✔\033[0m %s\n" "$1"; }
fout() { printf "  \033[31m✘\033[0m %s\n" "$1"; [ -n "$2" ] && printf "      → %s\n" "$2"; fouten=$((fouten + 1)); }

repo="$(cd "$(dirname "$0")/../.." && pwd)"
context=${CONTEXT:-kind-snip}
k() { kubectl --context "$context" -n snip-test "$@"; }

echo
echo "Module 16 — Debuggen"
echo

if [ -z "$CONTEXT" ] && [ "$(kubectl config current-context 2>/dev/null)" != "kind-snip" ]; then
  fout "actieve context is '$(kubectl config current-context 2>/dev/null)'" "kubectl config use-context kind-snip"
fi
if ! k get pods >/dev/null 2>&1; then
  fout "cluster $context niet bereikbaar" "podman start snip-control-plane"
  echo; exit 1
fi

# --- alles draait -----------------------------------------------------------
echo "snip-test draait"
for d in snip-api snip-web; do
  k rollout status deploy/$d --timeout=5s >/dev/null 2>&1 \
    && ok "$d is helemaal uitgerold" || fout "$d is niet helemaal uitgerold" "kubectl get pods,rs -n snip-test en kubectl events -n snip-test"
done
# pods die niet aan het stoppen zijn, maar ook niet klaar
niet_klaar=$(k get pods -o go-template='{{range .items}}{{if not .metadata.deletionTimestamp}}{{$n := .metadata.name}}{{range .status.conditions}}{{if and (eq .type "Ready") (ne .status "True")}}{{$n}} {{end}}{{end}}{{end}}{{end}}' 2>/dev/null)
[ -z "$niet_klaar" ] && ok "alle pods zijn Running en klaar" || fout "niet klaar: $niet_klaar" "kubectl describe pod -n snip-test NAAM"

los=$(k get pods -o go-template='{{range .items}}{{if not .metadata.ownerReferences}}{{.metadata.name}} {{end}}{{end}}' 2>/dev/null)
[ -z "$los" ] && ok "geen losse pods (zonder eigenaar)" \
  || fout "losse pod: $los" "Een kopie van kubectl debug of een kubectl run? Die ruimt niemand op."

# --- gelijk aan Git ---------------------------------------------------------
echo
echo "gelijk aan Git"
kubectl --context "$context" diff -k "$repo/k8s/overlays/test" >/dev/null 2>&1 \
  && ok "de app is gelijk aan k8s/overlays/test" || fout "de app wijkt af van Git" "kubectl diff -k k8s/overlays/test"
kubectl --context "$context" diff -f "$repo/k8s/platform/namespaces/snip-test.yaml" >/dev/null 2>&1 \
  && ok "de namespace is gelijk aan k8s/platform/namespaces/snip-test.yaml" || fout "de namespace (quota, rechten) wijkt af van Git" "kubectl diff -f k8s/platform/namespaces/snip-test.yaml"
in_git=$(kubectl kustomize "$repo/k8s/overlays/test" 2>/dev/null | awk '/^kind: NetworkPolicy/{np=1} np && /^  name:/{print $2; np=0}' | sort)
in_cluster=$(k get networkpolicy -o name 2>/dev/null | cut -d/ -f2 | sort)
extra=$(comm -13 <(echo "$in_git") <(echo "$in_cluster"))
[ -z "$extra" ] && ok "geen NetworkPolicies die niet in Git staan" \
  || fout "NetworkPolicy die niet in Git staat: $(echo $extra)" "apply -k haalt niets weg. Bekijk hem, en gooi hem weg."

# --- werkt het? -------------------------------------------------------------
echo
echo "werkt het?"
envoy=$(kubectl --context "$context" get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-namespace=snip-test -o name 2>/dev/null | head -1)
if [ -z "$envoy" ]; then
  fout "geen Envoy voor snip-test"
else
  poort=18$((RANDOM % 900 + 100))
  kubectl --context "$context" port-forward -n envoy-gateway-system "$envoy" "$poort:80" >/dev/null 2>&1 &
  tunnel=$!; sleep 3
  site=$(curl -s --max-time 5 -o /dev/null -w "%{http_code}" "localhost:$poort/")
  links=$(curl -s --max-time 5 "localhost:$poort/api/links")
  kort=$(curl -s --max-time 5 -o /dev/null -w "%{http_code}" "localhost:$poort/gh")
  { kill "$tunnel"; wait "$tunnel"; } 2>/dev/null
  [ "$site" = "200" ] && ok "de website werkt" || fout "de website geeft $site"
  echo "$links" | grep -q '"code":"gh"' && ok "/api/links werkt" || fout "/api/links werkt niet"
  [ "$kort" = "302" ] && ok "korte links werken" || fout "/gh geeft $kort in plaats van 302"
fi

# --- k9s (optioneel) --------------------------------------------------------
echo
command -v k9s >/dev/null && ok "k9s is geïnstalleerd" || echo "  – k9s niet gevonden (optioneel: brew install k9s)"

echo
if [ "$fouten" -eq 0 ]; then
  printf "\033[32mGeslaagd! Door naar module 17.\033[0m\n\n"
else
  printf "\033[31m%d punt(en) nog niet in orde.\033[0m\n\n" "$fouten"
  exit 1
fi
