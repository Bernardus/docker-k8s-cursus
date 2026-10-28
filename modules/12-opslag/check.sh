#!/usr/bin/env bash
# Controleert de eindopdracht van module 12.
# Gebruik: ./check.sh

fouten=0
ok()   { printf "  \033[32m✔\033[0m %s\n" "$1"; }
fout() { printf "  \033[31m✘\033[0m %s\n" "$1"; [ -n "$2" ] && printf "      → %s\n" "$2"; fouten=$((fouten + 1)); }

repo="$(cd "$(dirname "$0")/../.." && pwd)"
context=${CONTEXT:-kind-snip}
k() { kubectl --context "$context" "$@"; }
psql() { k exec snip-db-0 -- psql -U postgres -d snip -tAc "$1" 2>/dev/null; }

echo
echo "Module 12 — Opslag"
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
for f in db/statefulset.yaml db/service.yaml db/configmap-init.yaml; do
  [ -f "$repo/k8s/$f" ] && ok "k8s/$f" || fout "k8s/$f niet gevonden"
done

# --- database -------------------------------------------------------------
echo
echo "database"
[ "$(k get statefulset snip-db -o jsonpath='{.status.readyReplicas}' 2>/dev/null)" = "1" ] \
  && ok "StatefulSet snip-db: 1 pod ready" || fout "StatefulSet snip-db is niet ready" "kubectl rollout status statefulset/snip-db"
[ "$(k get pvc data-snip-db-0 -o jsonpath='{.status.phase}' 2>/dev/null)" = "Bound" ] \
  && ok "PVC data-snip-db-0 is Bound" || fout "PVC data-snip-db-0 is niet Bound" "kubectl get pvc"
[ "$(k get svc snip-db -o jsonpath='{.spec.clusterIP}' 2>/dev/null)" = "None" ] \
  && ok "Service snip-db is headless" || fout "headless Service snip-db ontbreekt" "Stap 4."
[ "$(k get statefulset snip-db -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="POSTGRES_PASSWORD")].valueFrom.secretKeyRef.name}' 2>/dev/null)" = "snip-db" ] \
  && ok "wachtwoord komt uit de Secret snip-db" || fout "POSTGRES_PASSWORD komt niet uit de Secret snip-db"

# --- de API kan erbij -----------------------------------------------------
echo
echo "API"
k exec deploy/snip-api -- node -e "fetch('http://localhost:3000/health/db').then(r => r.text()).then(console.log)" 2>/dev/null | grep -q '"ok"' \
  && ok "/health/db: ok" || fout "de API kan niet bij de database" "kubectl logs snip-db-0"

# --- data die blijft --------------------------------------------------------
echo
echo "data"
eigen=$(psql "SELECT count(*) FROM links WHERE code NOT IN ('gh','k8s','podman')")
if [ "${eigen:-0}" -ge 1 ]; then ok "$eigen eigen link(s) in de database"; else fout "nog geen eigen link gemaakt" "Stap 7."; fi
gestart=$(k get pod snip-db-0 -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null)
ouder=$(psql "SELECT count(*) FROM links WHERE code NOT IN ('gh','k8s','podman') AND created_at < '$gestart'::timestamptz")
if [ "${ouder:-0}" -ge 1 ]; then
  ok "je link is ouder dan de huidige pod: overleefde een nieuwe pod"
else
  fout "nog geen bewijs dat je data een nieuwe pod overleeft" "kubectl delete pod snip-db-0 (stap 8)"
fi

rest=""
k get statefulset snip-db-oud >/dev/null 2>&1 && rest="$rest statefulset/snip-db-oud"
k get pvc data-snip-db-oud-0 >/dev/null 2>&1 && rest="$rest pvc/data-snip-db-oud-0"
[ -n "$rest" ] && { echo; fout "oefenobjecten nog niet opgeruimd:$rest" "kubectl delete$rest"; }

echo
if [ "$fouten" -eq 0 ]; then
  printf "\033[32mGeslaagd! Door naar module 13.\033[0m\n\n"
else
  printf "\033[31m%d punt(en) nog niet in orde.\033[0m\n\n" "$fouten"
  exit 1
fi
