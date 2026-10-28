#!/usr/bin/env bash
# Controleert de eindopdracht van module 09.
# Gebruik: ./check.sh

fouten=0
ok()   { printf "  \033[32m✔\033[0m %s\n" "$1"; }
fout() { printf "  \033[31m✘\033[0m %s\n" "$1"; [ -n "$2" ] && printf "      → %s\n" "$2"; fouten=$((fouten + 1)); }

repo="$(cd "$(dirname "$0")/../.." && pwd)"
context=${CONTEXT:-kind-snip}
k() { kubectl --context "$context" "$@"; }
bestand="$repo/k8s/api/deployment.yaml"

echo
echo "Module 09 — Deployments"
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
if [ -f "$bestand" ]; then ok "k8s/api/deployment.yaml bestaat"; else fout "k8s/api/deployment.yaml niet gevonden" "Stap 3."; fi
if [ -f "$repo/k8s/snip-api-pod.yaml" ] || k get pod snip-api >/dev/null 2>&1; then
  fout "de losse pod uit module 08 bestaat nog" "kubectl delete -f k8s/snip-api-pod.yaml && rm k8s/snip-api-pod.yaml"
else
  ok "losse pod uit module 08 is opgeruimd"
fi

# --- deployment -----------------------------------------------------------
echo
echo "deployment snip-api"
if ! k get deploy snip-api >/dev/null 2>&1; then
  fout "deployment snip-api niet gevonden" "kubectl apply -f k8s/api/deployment.yaml"
  echo; exit 1
fi
gewenst=$(k get deploy snip-api -o jsonpath='{.spec.replicas}')
klaar=$(k get deploy snip-api -o jsonpath='{.status.readyReplicas}')
if [ "$gewenst" = "3" ] && [ "${klaar:-0}" = "3" ]; then ok "3 replicas, alle 3 ready"; else fout "replicas: $gewenst gevraagd, ${klaar:-0} ready" "kubectl rollout status deploy/snip-api"; fi
image=$(k get deploy snip-api -o jsonpath='{.spec.template.spec.containers[0].image}')
case "$image" in
  *:sha-*) ok "vaste versie: ${image##*:}" ;;
  *)       fout "image is $image" "Gebruik een vaste sha-tag, geen latest." ;;
esac
surge=$(k get deploy snip-api -o jsonpath='{.spec.strategy.rollingUpdate.maxSurge}')
onbeschikbaar=$(k get deploy snip-api -o jsonpath='{.spec.strategy.rollingUpdate.maxUnavailable}')
if [ "$surge" = "1" ] && [ "$onbeschikbaar" = "0" ]; then ok "maxSurge 1, maxUnavailable 0"; else fout "maxSurge $surge, maxUnavailable $onbeschikbaar" "Zie de strategy in stap 3."; fi
versies=$(k rollout history deploy/snip-api 2>/dev/null | awk 'NR>2 && NF')
aantal=$(printf '%s\n' "$versies" | grep -c .)
if [ "$aantal" -ge 2 ]; then ok "geschiedenis: $aantal versies"; else fout "geschiedenis heeft $aantal versie(s)" "Doe de update uit stap 8."; fi
if printf '%s\n' "$versies" | awk '{print $2}' | grep -qv '<none>'; then ok "change-cause staat in de geschiedenis"; else fout "geen change-cause in de geschiedenis" "kubernetes.io/change-cause in metadata.annotations"; fi
if [ -f "$bestand" ]; then
  if k diff -f "$bestand" >/dev/null 2>&1; then ok "cluster en bestand zijn het eens"; else fout "cluster wijkt af van het bestand" "kubectl diff -f k8s/api/deployment.yaml"; fi
fi

echo
if [ "$fouten" -eq 0 ]; then
  printf "\033[32mGeslaagd! Door naar module 10.\033[0m\n\n"
else
  printf "\033[31m%d punt(en) nog niet in orde.\033[0m\n\n" "$fouten"
  exit 1
fi
