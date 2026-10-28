#!/usr/bin/env bash
# Controleert de eindopdracht van module 13.
# Gebruik: ./check.sh

fouten=0
ok()   { printf "  \033[32m✔\033[0m %s\n" "$1"; }
fout() { printf "  \033[31m✘\033[0m %s\n" "$1"; [ -n "$2" ] && printf "      → %s\n" "$2"; fouten=$((fouten + 1)); }

repo="$(cd "$(dirname "$0")/../.." && pwd)"
context=${CONTEXT:-kind-snip}
k() { kubectl --context "$context" "$@"; }

echo
echo "Module 13 — Probes, resources en autoscaling"
echo

if [ -z "$CONTEXT" ] && [ "$(kubectl config current-context 2>/dev/null)" != "kind-snip" ]; then
  fout "actieve context is '$(kubectl config current-context 2>/dev/null)'" "kubectl config use-context kind-snip"
fi
if ! k get nodes >/dev/null 2>&1; then
  fout "cluster $context niet bereikbaar" "podman start snip-control-plane"
  echo; exit 1
fi

# --- nieuwe versie --------------------------------------------------------
echo "nieuwe versie van de API"
image=$(k get deploy snip-api -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
case "$image" in
  *sha-4000a15|"") fout "snip-api draait nog de oude versie (${image:-geen})" "Stap 1." ;;
  *) ok "snip-api draait $image" ;;
esac

# --- probes ---------------------------------------------------------------
echo
echo "probes"
c='{.spec.template.spec.containers[0]'
[ "$(k get deploy snip-api -o jsonpath="$c.readinessProbe.httpGet.path}" 2>/dev/null)" = "/health/db" ] \
  && ok "snip-api: readiness op /health/db" || fout "snip-api: readinessProbe op /health/db ontbreekt" "Stap 2."
[ "$(k get deploy snip-api -o jsonpath="$c.livenessProbe.httpGet.path}" 2>/dev/null)" = "/health" ] \
  && ok "snip-api: liveness op /health" || fout "snip-api: livenessProbe op /health ontbreekt" "Stap 2."
k get sts snip-db -o jsonpath="$c.readinessProbe.exec.command}" 2>/dev/null | grep -q pg_isready \
  && ok "snip-db: readiness met pg_isready" || fout "snip-db: readinessProbe met pg_isready ontbreekt" "Stap 3."
[ -n "$(k get deploy snip-web -o jsonpath="$c.readinessProbe}" 2>/dev/null)" ] \
  && ok "snip-web: readiness" || fout "snip-web: readinessProbe ontbreekt" "Stap 3."

# --- resources ------------------------------------------------------------
echo
echo "resources"
for obj in deploy/snip-api deploy/snip-web sts/snip-db; do
  r=$(k get "$obj" -o jsonpath="$c.resources.requests.cpu} $c.resources.requests.memory} $c.resources.limits.memory}" 2>/dev/null)
  set -- $r
  [ $# -eq 3 ] && ok "$obj: requests $1/$2, limit $3" || fout "$obj: requests (cpu en memory) en een memory-limit ontbreken" "Stap 6."
done
k top pods >/dev/null 2>&1 && ok "metrics-server werkt (kubectl top)" || fout "kubectl top werkt niet" "Stap 5."

# --- autoscaling ----------------------------------------------------------
echo
echo "autoscaling"
[ -f "$repo/k8s/api/hpa.yaml" ] || fout "k8s/api/hpa.yaml niet gevonden"
if grep -q "^  replicas:" "$repo/k8s/api/deployment.yaml" 2>/dev/null; then
  fout "k8s/api/deployment.yaml heeft nog replicas:" "Haal die regel weg: de HPA bepaalt het aantal (stap 7)."
fi
if [ "$(k get hpa snip-api -o jsonpath='{.spec.scaleTargetRef.name}' 2>/dev/null)" = "snip-api" ]; then
  ok "HPA snip-api: $(k get hpa snip-api -o jsonpath='{.spec.minReplicas}–{.spec.maxReplicas} pods')"
else
  fout "HPA snip-api ontbreekt" "Stap 7."
fi
k get events --field-selector involvedObject.kind=HorizontalPodAutoscaler,involvedObject.name=snip-api,reason=SuccessfulRescale \
  -o jsonpath='{.items[*].message}' 2>/dev/null | grep -q "above target" \
  && ok "de HPA heeft opgeschaald onder belasting" \
  || fout "geen opschaling gezien in het afgelopen uur" "Stap 8 (Kubernetes bewaart events een uur)."

# --- alles gezond ---------------------------------------------------------
echo
echo "alles gezond"
klaar=$(k get deploy snip-api -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
[ "${klaar:-0}" -ge 2 ] && ok "snip-api: $klaar pods ready" || fout "snip-api: ${klaar:-0} pods ready, verwacht minstens 2"
[ "$(k get sts snip-db -o jsonpath='{.status.readyReplicas}' 2>/dev/null)" = "1" ] \
  && ok "snip-db ready" || fout "snip-db is niet ready" "kubectl describe pod snip-db-0"
klaar=$(k get deploy snip-web -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
[ "${klaar:-0}" -ge 2 ] && ok "snip-web: $klaar pods ready" || fout "snip-web: ${klaar:-0} pods ready, verwacht 2"
k get pod belasting >/dev/null 2>&1 && fout "de pod belasting draait nog" "kubectl delete pod belasting"

echo
if [ "$fouten" -eq 0 ]; then
  printf "\033[32mGeslaagd! Door naar module 14.\033[0m\n\n"
else
  printf "\033[31m%d punt(en) nog niet in orde.\033[0m\n\n" "$fouten"
  exit 1
fi
