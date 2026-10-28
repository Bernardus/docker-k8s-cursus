#!/usr/bin/env bash
# Controleert de eindopdracht van module 11.
# Gebruik: ./check.sh

fouten=0
ok()   { printf "  \033[32m✔\033[0m %s\n" "$1"; }
fout() { printf "  \033[31m✘\033[0m %s\n" "$1"; [ -n "$2" ] && printf "      → %s\n" "$2"; fouten=$((fouten + 1)); }

repo="$(cd "$(dirname "$0")/../.." && pwd)"
context=${CONTEXT:-kind-snip}
k() { kubectl --context "$context" "$@"; }

echo
echo "Module 11 — ConfigMaps en Secrets"
echo

if [ -z "$CONTEXT" ] && [ "$(kubectl config current-context 2>/dev/null)" != "kind-snip" ]; then
  fout "actieve context is '$(kubectl config current-context 2>/dev/null)'" "kubectl config use-context kind-snip"
fi
if ! k get nodes >/dev/null 2>&1; then
  fout "cluster $context niet bereikbaar" "podman start snip-control-plane"
  echo; exit 1
fi

# --- website --------------------------------------------------------------
echo "website"
for f in web/configmap-site.yaml web/configmap-nginx.yaml web/deployment.yaml web/service.yaml web/route.yaml; do
  [ -f "$repo/k8s/$f" ] || fout "k8s/$f niet gevonden"
done
k get configmap snip-web-site -o jsonpath='{.data.index\.html}' 2>/dev/null | grep -q "<title>snip</title>" \
  && ok "ConfigMap snip-web-site bevat index.html" || fout "ConfigMap snip-web-site met index.html ontbreekt" "Stap 1."
k get configmap snip-web-nginx -o jsonpath='{.data.default\.conf}' 2>/dev/null | grep -q "proxy_pass" \
  && ok "ConfigMap snip-web-nginx bevat default.conf" || fout "ConfigMap snip-web-nginx met default.conf ontbreekt" "Stap 1."
klaar=$(k get deploy snip-web -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
[ "${klaar:-0}" -ge 2 ] && ok "snip-web: $klaar pods ready" || fout "snip-web: ${klaar:-0} pods ready, verwacht 2" "kubectl rollout status deploy/snip-web"
cms=$(k get deploy snip-web -o jsonpath='{range .spec.template.spec.volumes[*]}{.configMap.name} {end}' 2>/dev/null)
case "$cms" in *snip-web-site*snip-web-nginx*|*snip-web-nginx*snip-web-site*) ok "pagina en nginx.conf komen uit ConfigMaps" ;; *) fout "snip-web gebruikt de ConfigMaps niet als volume" ;; esac

# --- routes ---------------------------------------------------------------
echo
echo "routes"
[ "$(k get httproute snip-api -o jsonpath='{.spec.rules[0].matches[0].path.value}' 2>/dev/null)" = "/api" ] \
  && ok "snip-api: /api" || fout "route snip-api gaat niet over /api" "Stap 3."
[ "$(k get httproute snip-web -o jsonpath='{.spec.rules[0].matches[0].path.value}' 2>/dev/null)" = "/" ] \
  && ok "snip-web: /" || fout "route snip-web voor / ontbreekt" "Stap 3."
envoy=$(k get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=snip -o name 2>/dev/null | head -1)
if [ -n "$envoy" ]; then
  poort=18$((RANDOM % 900 + 100))
  k port-forward -n envoy-gateway-system "$envoy" "$poort:80" >/dev/null 2>&1 &
  tunnel=$!; sleep 3
  curl -s --max-time 3 "localhost:$poort/" | grep -q "<title>snip</title>" && ok "/ geeft de website" || fout "/ geeft de website niet"
  curl -s --max-time 3 "localhost:$poort/api/info" | grep -q '"app":"snip-api"' && ok "/api/info geeft de API" || fout "/api/info geeft de API niet"
  { kill "$tunnel"; wait "$tunnel"; } 2>/dev/null
fi

# --- secret ---------------------------------------------------------------
echo
echo "secret"
[ -n "$(k get secret snip-db -o jsonpath='{.data.password}' 2>/dev/null)" ] \
  && ok "Secret snip-db met sleutel password" || fout "Secret snip-db met sleutel password ontbreekt" "Stap 6."
bron=$(k get deploy snip-api -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="DB_PASSWORD")].valueFrom.secretKeyRef.name}' 2>/dev/null)
url=$(k get deploy snip-api -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="DATABASE_URL")].value}' 2>/dev/null)
if [ "$bron" = "snip-db" ] && echo "$url" | grep -q '$(DB_PASSWORD)'; then
  ok "API bouwt DATABASE_URL op met het wachtwoord uit snip-db"
else
  fout "API haalt het wachtwoord niet uit de Secret" "Stap 7."
fi
if grep -rlq "^kind: Secret" "$repo/k8s" 2>/dev/null; then
  fout "er staat een Secret als bestand in k8s/" "Verwijder dat bestand: Secrets horen niet in Git."
else
  ok "geen Secret-bestand in k8s/"
fi
k get deploy snip-api-kapot >/dev/null 2>&1 && fout "oefen-deployment snip-api-kapot staat er nog" "kubectl delete deploy snip-api-kapot"

echo
if [ "$fouten" -eq 0 ]; then
  printf "\033[32mGeslaagd! Door naar module 12.\033[0m\n\n"
else
  printf "\033[31m%d punt(en) nog niet in orde.\033[0m\n\n" "$fouten"
  exit 1
fi
