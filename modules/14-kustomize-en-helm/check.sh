#!/usr/bin/env bash
# Controleert de eindopdracht van module 14.
# Gebruik: ./check.sh

fouten=0
ok()   { printf "  \033[32m✔\033[0m %s\n" "$1"; }
fout() { printf "  \033[31m✘\033[0m %s\n" "$1"; [ -n "$2" ] && printf "      → %s\n" "$2"; fouten=$((fouten + 1)); }

repo="$(cd "$(dirname "$0")/../.." && pwd)"
context=${CONTEXT:-kind-snip}
k() { kubectl --context "$context" "$@"; }

echo
echo "Module 14 — Kustomize en Helm"
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
for f in app/kustomization.yaml k8s/base/kustomization.yaml k8s/base/gateway.yaml k8s/base/api/hpa.yaml \
         k8s/overlays/test/kustomization.yaml k8s/overlays/prod/kustomization.yaml k8s/platform/gatewayclass.yaml k8s/platform/headlamp-values.yaml; do
  [ -f "$repo/$f" ] || fout "$f niet gevonden"
done
for f in k8s/api k8s/web k8s/db k8s/gateway.yaml k8s/base/web/configmap-site.yaml k8s/base/web/configmap-nginx.yaml k8s/base/db/configmap-init.yaml; do
  [ -e "$repo/$f" ] && fout "$f staat er nog" "Stap 1 en 2."
done
grep -q "kind: Gateway$" "$repo/k8s/platform/gatewayclass.yaml" 2>/dev/null && fout "de Gateway snip hoort in k8s/base/gateway.yaml, niet in platform/" "Stap 1."
for d in base overlays/test overlays/prod; do
  if kubectl kustomize "$repo/k8s/$d" >/dev/null 2>&1; then
    ok "kubectl kustomize k8s/$d werkt"
  else
    fout "kubectl kustomize k8s/$d geeft een fout" "Draai het zelf voor de melding."
  fi
done

# --- prod ----------------------------------------------------------------
echo
echo "omgeving prod (namespace default)"
site=$(k get deploy snip-web -o jsonpath='{.spec.template.spec.volumes[*].configMap.name}' 2>/dev/null)
init=$(k get sts snip-db -o jsonpath='{.spec.template.spec.volumes[*].configMap.name}' 2>/dev/null)
if echo "$site $init" | grep -qE "snip-web-site-[a-z0-9]{10}" && echo "$init" | grep -qE "snip-db-init-[a-z0-9]{10}"; then
  ok "ConfigMaps komen uit de generator (met hash)"
else
  fout "de pods gebruiken nog de oude ConfigMaps" "kubectl apply -k k8s/base (stap 3)"
fi
k get configmap snip-web-site snip-web-nginx snip-db-init >/dev/null 2>&1 \
  && fout "de oude ConfigMaps (zonder hash) staan er nog" "Stap 3."
if k diff -k "$repo/k8s/overlays/prod" >/dev/null 2>&1; then
  ok "het cluster is precies gelijk aan k8s/overlays/prod"
else
  fout "het cluster wijkt af van k8s/overlays/prod" "kubectl diff -k k8s/overlays/prod (stap 8)"
fi
[ "$(k get deploy snip-web -o jsonpath='{.metadata.labels.env}' 2>/dev/null)" = "prod" ] \
  && ok "label env=prod" || fout "label env=prod ontbreekt" "kubectl apply -k k8s/overlays/prod (stap 8)"
klaar=$(k get deploy snip-web -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
[ "${klaar:-0}" -ge 2 ] && ok "snip-web: $klaar pods ready" || fout "snip-web: ${klaar:-0} pods ready, verwacht 2"

# --- test -----------------------------------------------------------------
echo
echo "omgeving test (namespace snip-test)"
t() { k -n snip-test "$@"; }
[ "$(t get sts snip-db -o jsonpath='{.status.readyReplicas}' 2>/dev/null)" = "1" ] \
  && ok "snip-db ready" || fout "snip-db in snip-test is niet ready" "kubectl -n snip-test get pods (stap 5 en 6)"
klaar=$(t get deploy snip-api -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
[ "${klaar:-0}" -ge 1 ] && ok "snip-api: $klaar pod(s) ready" || fout "snip-api in snip-test is niet ready" "kubectl -n snip-test get pods"
case "$(t get deploy snip-api -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)" in
  *:latest) ok "snip-api draait :latest" ;;
  *) fout "snip-api in snip-test draait niet :latest" "images: in k8s/overlays/test/kustomization.yaml (stap 5)" ;;
esac
[ "$(t get hpa snip-api -o jsonpath='{.spec.minReplicas}-{.spec.maxReplicas}' 2>/dev/null)" = "1-2" ] \
  && ok "HPA: 1–2 pods" || fout "HPA in snip-test heeft niet 1–2 pods" "patches: in k8s/overlays/test/kustomization.yaml (stap 5)"
[ "$(t get deploy snip-web -o jsonpath='{.metadata.labels.env}' 2>/dev/null)" = "test" ] \
  && ok "label env=test" || fout "label env=test ontbreekt" "labels: in k8s/overlays/test/kustomization.yaml"
envoy=$(k get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-namespace=snip-test -o name 2>/dev/null | head -1)
if [ -n "$envoy" ]; then
  poort=18$((RANDOM % 900 + 100))
  k port-forward -n envoy-gateway-system "$envoy" "$poort:80" >/dev/null 2>&1 &
  tunnel=$!; sleep 3
  curl -s --max-time 3 "localhost:$poort/api/links" | grep -q '"code":"gh"' \
    && ok "eigen Gateway: /api/links geeft links" || fout "de Gateway van snip-test geeft geen links" "Stap 7."
  { kill "$tunnel"; wait "$tunnel"; } 2>/dev/null
else
  fout "geen Gateway in snip-test" "Stap 6."
fi

# --- helm -----------------------------------------------------------------
echo
echo "helm"
command -v helm >/dev/null && ok "helm $(helm version --short 2>/dev/null)" || fout "helm niet gevonden" "brew install helm (stap 9)"
[ -n "$(k get secret -n headlamp -l owner=helm,name=headlamp,status=deployed -o name 2>/dev/null)" ] \
  && ok "release headlamp is geïnstalleerd" || fout "release headlamp ontbreekt in namespace headlamp" "Stap 10."
[ "$(k get clusterrolebinding headlamp-admin -o jsonpath='{.roleRef.name}' 2>/dev/null)" = "view" ] \
  && ok "Headlamp mag alleen kijken (view)" || fout "Headlamp heeft niet de rol view" "headlamp-values.yaml (stap 10)"
klaar=$(k get deploy -n headlamp headlamp -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
[ "${klaar:-0}" -eq 2 ] && ok "Headlamp: 2 pods ready" || fout "Headlamp: ${klaar:-0} pods ready, verwacht 2" "replicaCount in headlamp-values.yaml (stap 11)"

echo
if [ "$fouten" -eq 0 ]; then
  printf "\033[32mGeslaagd! Door naar module 15.\033[0m\n\n"
else
  printf "\033[31m%d punt(en) nog niet in orde.\033[0m\n\n" "$fouten"
  exit 1
fi
