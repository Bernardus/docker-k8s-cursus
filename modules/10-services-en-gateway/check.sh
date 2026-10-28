#!/usr/bin/env bash
# Controleert de eindopdracht van module 10.
# Gebruik: ./check.sh

fouten=0
ok()   { printf "  \033[32m✔\033[0m %s\n" "$1"; }
fout() { printf "  \033[31m✘\033[0m %s\n" "$1"; [ -n "$2" ] && printf "      → %s\n" "$2"; fouten=$((fouten + 1)); }
info() { printf "  \033[34mℹ\033[0m %s\n" "$1"; }

repo="$(cd "$(dirname "$0")/../.." && pwd)"
context=${CONTEXT:-kind-snip}
k() { kubectl --context "$context" "$@"; }

echo
echo "Module 10 — Services en de Gateway"
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
for f in api/service.yaml gateway.yaml api/route.yaml; do
  if [ -f "$repo/k8s/$f" ]; then ok "k8s/$f"; else fout "k8s/$f niet gevonden"; fi
done

# --- service --------------------------------------------------------------
echo
echo "service snip-api"
if k get svc snip-api >/dev/null 2>&1; then
  type=$(k get svc snip-api -o jsonpath='{.spec.type}')
  poorten=$(k get svc snip-api -o jsonpath='{.spec.ports[0].port}→{.spec.ports[0].targetPort}')
  [ "$type" = "ClusterIP" ] && ok "type ClusterIP" || fout "type is $type, verwacht ClusterIP"
  [ "$poorten" = "80→3000" ] && ok "poort 80 → 3000" || fout "poorten $poorten, verwacht 80→3000"
  endpoints=$(k get endpointslices -l kubernetes.io/service-name=snip-api -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]} {end}' | wc -w | tr -d ' ')
  if [ "$endpoints" -ge 3 ]; then ok "$endpoints endpoints (pods)"; else fout "$endpoints endpoints, verwacht 3" "Past de selector op het etiket van je pods?"; fi
else
  fout "service snip-api niet gevonden" "kubectl apply -f k8s/api/service.yaml"
fi

# --- gateway --------------------------------------------------------------
echo
echo "gateway"
versie=$(k get deploy envoy-gateway -n envoy-gateway-system -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
case "$versie" in
  *v1.9.2) ok "Envoy Gateway v1.9.2" ;;
  "")      fout "Envoy Gateway niet gevonden" "Stap 6." ;;
  *)       info "Envoy Gateway draait, image: $versie" ;;
esac
if [ "$(k get gateway snip -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null)" = "True" ]; then
  ok "gateway snip: Programmed"
else
  fout "gateway snip niet Programmed" "kubectl describe gateway snip"
fi
route=$(k get httproute snip-api -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status} {end}' 2>/dev/null)
case "$route" in
  *Accepted=True*ResolvedRefs=True*|*ResolvedRefs=True*Accepted=True*) ok "route snip-api: Accepted, ResolvedRefs" ;;
  "") fout "httproute snip-api niet gevonden" "kubectl apply -f k8s/api/route.yaml" ;;
  *)  fout "route snip-api: $route" "kubectl describe httproute snip-api" ;;
esac

# --- verkeer door de voordeur --------------------------------------------
echo
echo "verkeer"
envoy=$(k get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=snip -o name 2>/dev/null | head -1)
if [ -n "$envoy" ]; then
  poort=18$((RANDOM % 900 + 100))
  k port-forward -n envoy-gateway-system "$envoy" "$poort:80" >/dev/null 2>&1 &
  tunnel=$!
  sleep 3
  pods=$(for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do curl -s --max-time 3 "localhost:$poort/api/info"; echo; done | grep -o '"container":"[^"]*"' | sort -u | wc -l | tr -d ' ')
  { kill "$tunnel"; wait "$tunnel"; } 2>/dev/null
  if [ "$pods" -ge 2 ]; then
    ok "via de Gateway antwoordden $pods verschillende pods"
  elif [ "$pods" -eq 1 ]; then
    fout "via de Gateway antwoordde steeds dezelfde pod" "Heeft de Service 3 endpoints?"
  else
    fout "geen antwoord via de Gateway" "kubectl get gateway,httproute"
  fi
else
  fout "geen Envoy-service voor gateway snip gevonden"
fi

# --- opgeruimd? -----------------------------------------------------------
rest=""
k get svc snip-api-kapot >/dev/null 2>&1 && rest="$rest svc/snip-api-kapot"
k get httproute snip-api-kapot >/dev/null 2>&1 && rest="$rest httproute/snip-api-kapot"
k get ingress snip-api >/dev/null 2>&1 && rest="$rest ingress/snip-api"
k get pod tmp >/dev/null 2>&1 && rest="$rest pod/tmp"
if [ -n "$rest" ]; then
  echo
  fout "oefenobjecten nog niet opgeruimd:$rest" "kubectl delete$rest"
fi

echo
if [ "$fouten" -eq 0 ]; then
  printf "\033[32mGeslaagd! Door naar module 11.\033[0m\n\n"
else
  printf "\033[31m%d punt(en) nog niet in orde.\033[0m\n\n" "$fouten"
  exit 1
fi
