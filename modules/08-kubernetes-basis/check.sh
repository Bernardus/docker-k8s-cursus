#!/usr/bin/env bash
# Controleert de eindopdracht van module 08.
# Gebruik: ./check.sh

fouten=0
ok()   { printf "  \033[32m✔\033[0m %s\n" "$1"; }
fout() { printf "  \033[31m✘\033[0m %s\n" "$1"; [ -n "$2" ] && printf "      → %s\n" "$2"; fouten=$((fouten + 1)); }
info() { printf "  \033[34mℹ\033[0m %s\n" "$1"; }

repo="$(cd "$(dirname "$0")/../.." && pwd)"
cluster=${CLUSTER:-snip}

echo
echo "Module 08 — Waarom Kubernetes, en je eerste cluster"
echo

# --- tools ----------------------------------------------------------------
echo "tools"
if command -v kind >/dev/null 2>&1; then ok "kind $(kind version | awk '{print $2}')"; else fout "kind niet gevonden" "brew install kind"; fi
if [ "$KIND_EXPERIMENTAL_PROVIDER" = "podman" ]; then
  ok "kind gebruikt Podman"
else
  fout "KIND_EXPERIMENTAL_PROVIDER staat niet op podman" "echo 'export KIND_EXPERIMENTAL_PROVIDER=podman' >> ~/.zshrc && exec zsh -l"
fi
client=$(kubectl version -o json 2>/dev/null | jq -r '.clientVersion.minor' | tr -dc 0-9)
server=$(kubectl version -o json 2>/dev/null | jq -r '.serverVersion.minor // empty' | tr -dc 0-9)
if [ -n "$client" ] && [ -n "$server" ]; then
  verschil=$(( client > server ? client - server : server - client ))
  if [ "$verschil" -le 1 ]; then ok "kubectl 1.$client past bij het cluster (1.$server)"; else fout "kubectl 1.$client en cluster 1.$server verschillen te veel" "brew upgrade kubernetes-cli"; fi
fi

# --- cluster --------------------------------------------------------------
echo
echo "cluster"
if kind get clusters 2>/dev/null | grep -qx "$cluster"; then
  ok "kind-cluster '$cluster' bestaat"
else
  fout "kind-cluster '$cluster' niet gevonden" "kind create cluster --name $cluster"
  echo; exit 1
fi
if [ "$(kubectl config current-context 2>/dev/null)" = "kind-$cluster" ]; then
  ok "actieve context: kind-$cluster"
else
  fout "actieve context is '$(kubectl config current-context 2>/dev/null)'" "kubectl config use-context kind-$cluster"
  echo; exit 1
fi
if kubectl get nodes --no-headers 2>/dev/null | awk '{print $2}' | grep -qx Ready; then
  ok "node is Ready"
else
  fout "node is niet Ready" "Draait hij? podman start $cluster-control-plane"
fi

# --- pod ------------------------------------------------------------------
echo
echo "pod snip-api"
if [ -f "$repo/k8s/snip-api-pod.yaml" ]; then ok "k8s/snip-api-pod.yaml bestaat"; else fout "k8s/snip-api-pod.yaml niet gevonden" "Stap 13."; fi
if kubectl get pod snip-api >/dev/null 2>&1; then
  if [ "$(kubectl get pod snip-api -o jsonpath='{.status.containerStatuses[0].ready}')" = "true" ]; then
    ok "draait en is ready"
  else
    fout "draait niet (status: $(kubectl get pod snip-api --no-headers | awk '{print $3}'))" "kubectl describe pod snip-api"
  fi
  case "$(kubectl get pod snip-api -o jsonpath='{.spec.containers[0].image}')" in
    ghcr.io/*/snip-api*) ok "image uit GHCR" ;;
    *)                   fout "image is niet je snip-api uit GHCR" ;;
  esac
  if [ "$(kubectl get pod snip-api -o jsonpath='{.metadata.labels.app}')" = "snip-api" ]; then ok "label app=snip-api"; else fout "label app=snip-api ontbreekt"; fi
  if kubectl get pod snip-api -o jsonpath='{.metadata.annotations}' | grep -q last-applied-configuration; then
    ok "gemaakt met kubectl apply -f"
  else
    fout "niet gemaakt met kubectl apply -f" "kubectl delete pod snip-api && kubectl apply -f k8s/snip-api-pod.yaml"
  fi
  versie=$(kubectl exec snip-api -- node -e "fetch('http://localhost:3000/api/info').then(r => r.json()).then(i => console.log(i.versie))" 2>/dev/null)
  if [ -n "$versie" ]; then ok "API antwoordt in de pod (versie $versie)"; else fout "API antwoordt niet in de pod" "kubectl logs snip-api"; fi
else
  fout "pod snip-api niet gevonden" "kubectl apply -f k8s/snip-api-pod.yaml"
fi

rest=$(kubectl get pods --no-headers -o custom-columns=:metadata.name 2>/dev/null | grep -xE 'hallo|tikfout|crash' | tr '\n' ' ')
[ -n "$rest" ] && info "oefenpods nog niet opgeruimd: $rest→ kubectl delete pod $rest"

echo
if [ "$fouten" -eq 0 ]; then
  printf "\033[32mGeslaagd! Door naar module 09.\033[0m\n\n"
else
  printf "\033[31m%d punt(en) nog niet in orde.\033[0m\n\n" "$fouten"
  exit 1
fi
