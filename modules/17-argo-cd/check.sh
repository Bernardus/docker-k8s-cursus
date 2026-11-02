#!/usr/bin/env bash
# Controleert de eindopdracht van module 17.
# Gebruik: ./check.sh

fouten=0
ok()   { printf "  \033[32m✔\033[0m %s\n" "$1"; }
fout() { printf "  \033[31m✘\033[0m %s\n" "$1"; [ -n "$2" ] && printf "      → %s\n" "$2"; fouten=$((fouten + 1)); }

repo="$(cd "$(dirname "$0")/../.." && pwd)"
context=${CONTEXT:-kind-snip}
k() { kubectl --context "$context" "$@"; }
app() { k get application -n argocd "$1" -o jsonpath="$2" 2>/dev/null; }

echo
echo "Module 17 — Argo CD"
echo

if [ -z "$CONTEXT" ] && [ "$(kubectl config current-context 2>/dev/null)" != "kind-snip" ]; then
  fout "actieve context is '$(kubectl config current-context 2>/dev/null)'" "kubectl config use-context kind-snip"
fi
if ! k get nodes >/dev/null 2>&1; then
  fout "cluster $context niet bereikbaar" "podman start snip-control-plane"
  echo; exit 1
fi

# --- Git --------------------------------------------------------------------
echo "Git"
for f in k8s/platform/argocd-values.yaml k8s/platform/argocd/snip-test.yaml k8s/platform/argocd/snip-prod.yaml; do
  [ -f "$repo/$f" ] && ok "$f" || fout "$f niet gevonden"
done
git -C "$repo" fetch -q origin 2>/dev/null
[ -z "$(git -C "$repo" status --porcelain -- k8s app)" ] \
  && ok "k8s/ en app/ zijn gecommit" || fout "er staan nog wijzigingen in k8s/ of app/ die niet gecommit zijn" "git status"
[ -z "$(git -C "$repo" rev-list origin/main..HEAD 2>/dev/null)" ] \
  && ok "alles is gepusht" || fout "er zijn commits die nog niet op GitHub staan" "git push (Argo CD leest GitHub, niet je laptop)"

# --- Argo CD ----------------------------------------------------------------
echo
echo "Argo CD"
for d in argocd-server argocd-repo-server; do
  k rollout status -n argocd deploy/$d --timeout=5s >/dev/null 2>&1 \
    && ok "$d draait" || fout "$d draait niet" "helm install argocd ... (stap 2)"
done
k rollout status -n argocd statefulset/argocd-application-controller --timeout=5s >/dev/null 2>&1 \
  && ok "argocd-application-controller draait" || fout "argocd-application-controller draait niet"

# --- Applications -----------------------------------------------------------
echo
echo "Applications"
remote=${REPO_URL:-$(git -C "$repo" remote get-url origin 2>/dev/null)}
norm() { echo "$1" | tr 'A-Z' 'a-z' | sed -e 's#\.git$##' -e 's#/$##'; }
for omg in test prod; do
  naam=snip-$omg
  if [ -z "$(app $naam '{.metadata.name}')" ]; then
    fout "Application $naam bestaat niet" "kubectl apply -f k8s/platform/argocd/$naam.yaml"
    continue
  fi
  [ "$(norm "$(app $naam '{.spec.source.repoURL}')")" = "$(norm "$remote")" ] \
    && ok "$naam leest jouw repo" || fout "$naam leest $(app $naam '{.spec.source.repoURL}'), niet $remote"
  [ "$(app $naam '{.spec.source.path}')" = "k8s/overlays/$omg" ] \
    && ok "$naam gebruikt k8s/overlays/$omg" || fout "$naam heeft path '$(app $naam '{.spec.source.path}')'"
  sync=$(app $naam '{.status.sync.status}'); health=$(app $naam '{.status.health.status}')
  [ "$sync" = "Synced" ] && [ "$health" = "Healthy" ] \
    && ok "$naam is Synced en Healthy" || fout "$naam is $sync en $health" "Kijk in de UI wat er anders is (App Diff)"
done

auto=$(app snip-test '{.spec.syncPolicy.automated}')
echo "$auto" | grep -q '"prune":true' && echo "$auto" | grep -q '"selfHeal":true' \
  && ok "snip-test rolt zelf uit, met prune en selfHeal" || fout "snip-test heeft geen automated sync met prune en selfHeal" "Stap 6."
[ -z "$(app snip-prod '{.spec.syncPolicy.automated}')" ] \
  && ok "snip-prod wacht op jou" || fout "snip-prod rolt zelf uit" "Prod: geen automated (stap 9)."

# --- self-heal --------------------------------------------------------------
echo
echo "self-heal"
voor=$(k get deploy -n snip-test snip-web -o jsonpath='{.spec.replicas}' 2>/dev/null)
k scale deploy -n snip-test snip-web --replicas=$((voor + 3)) >/dev/null 2>&1
terug=""
for i in $(seq 1 15); do
  sleep 2
  [ "$(k get deploy -n snip-test snip-web -o jsonpath='{.spec.replicas}')" = "$voor" ] && { terug=$((i * 2)); break; }
done
[ -n "$terug" ] && ok "snip-web met de hand opgeschaald: na ${terug}s teruggezet" \
  || fout "snip-web is na 30s niet teruggezet" "selfHeal: true (stap 6)"

echo
if [ "$fouten" -eq 0 ]; then
  printf "\033[32mGeslaagd! Door naar module 18.\033[0m\n\n"
else
  printf "\033[31m%d punt(en) nog niet in orde.\033[0m\n\n" "$fouten"
  exit 1
fi
