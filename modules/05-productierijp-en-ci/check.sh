#!/usr/bin/env bash
# Controleert de eindopdracht van module 05.
# Gebruik: ./check.sh

fouten=0
ok()   { printf "  \033[32m✔\033[0m %s\n" "$1"; }
fout() { printf "  \033[31m✘\033[0m %s\n" "$1"; [ -n "$2" ] && printf "      → %s\n" "$2"; fouten=$((fouten + 1)); }

repo="$(cd "$(dirname "$0")/../.." && pwd)"

echo
echo "Module 05 — Productierijp image en je eerste pipeline"
echo

if ! podman info >/dev/null 2>&1; then
  fout "Podman-machine niet bereikbaar" "podman machine start"
  echo; exit 1
fi

# --- lokaal image ---------------------------------------------------------
echo "image snip-api:2"
if podman image exists snip-api:2; then
  ok "image bestaat"
  if [ "$(podman image inspect snip-api:2 -f '{{index .Labels "org.opencontainers.image.version"}}')" = "2.0.0" ]; then
    ok "label met versie 2.0.0"
  else
    fout "geen label met versie 2.0.0" "podman build -t snip-api:2 --build-arg APP_VERSION=2.0.0 ."
  fi
  if [ "$(podman run --rm snip-api:2 node -p process.env.APP_VERSION 2>/dev/null)" = "2.0.0" ]; then
    ok "app ziet APP_VERSION=2.0.0"
  else
    fout "APP_VERSION zit niet in het image" "ARG APP_VERSION + ENV APP_VERSION=\$APP_VERSION"
  fi
  if [ -z "$(podman run --rm snip-api:2 sh -c 'command -v npm' 2>/dev/null)" ]; then
    ok "npm zit niet in het eindimage"
  else
    fout "npm zit nog in het eindimage" "rm -rf /usr/local/lib/node_modules/npm /usr/local/bin/npm /usr/local/bin/npx"
  fi
  podman rm -f check-stop >/dev/null 2>&1
  podman run -d --name check-stop snip-api:2 >/dev/null 2>&1; sleep 2
  start=$(date +%s); podman stop check-stop >/dev/null 2>&1; duur=$(( $(date +%s) - start ))
  podman rm -f check-stop >/dev/null 2>&1
  if [ "$duur" -lt 5 ]; then
    ok "stopt netjes (${duur}s)"
  else
    fout "stoppen duurde ${duur}s" "Is het image gebouwd met de nieuwe app-code?"
  fi
else
  fout "image snip-api:2 niet gevonden" "podman build -t snip-api:2 --build-arg APP_VERSION=2.0.0 .  (in app/api)"
fi

# --- GitHub ---------------------------------------------------------------
echo
echo "GitHub"
if git -C "$repo" remote get-url origin 2>/dev/null | grep -q "github.com"; then
  ok "repo staat op GitHub ($(git -C "$repo" remote get-url origin))"
  if [ "$(cd "$repo" && gh repo view --json visibility -q .visibility 2>/dev/null)" = "PUBLIC" ]; then
    ok "repo is publiek"
  else
    fout "repo is niet publiek" "gh repo edit --visibility public --accept-visibility-change-consequences"
  fi
else
  fout "geen GitHub-remote gevonden" "Zie stap 13 en 14."
fi

workflow="$repo/.github/workflows/snip-api.yml"
if [ -f "$workflow" ]; then
  ok "workflow .github/workflows/snip-api.yml bestaat"
  if grep -E '^\s*-?\s*uses:' "$workflow" | grep -vqE '@[0-9a-f]{40}'; then
    fout "niet alle actions zijn op een commit-SHA vastgepind"
  else
    ok "alle actions vastgepind op een commit-SHA"
  fi
else
  fout "workflow niet gevonden in .github/workflows/ (in de hoofdmap van de repo)"
fi

conclusie=$(cd "$repo" && gh run list --workflow snip-api.yml --branch main --limit 1 --json conclusion -q '.[0].conclusion' 2>/dev/null)
if [ "$conclusie" = "success" ]; then
  ok "laatste run op main is geslaagd"
else
  fout "laatste run op main: ${conclusie:-geen gevonden}" "gh run list --workflow snip-api.yml  → gh run view --log-failed"
fi

# --- GHCR -----------------------------------------------------------------
echo
echo "GHCR"
eigenaar=$(gh api user --jq .login 2>/dev/null | tr 'A-Z' 'a-z')
image="ghcr.io/$eigenaar/snip-api:latest"
manifest=$(podman manifest inspect "$image" 2>/dev/null)
if [ -n "$manifest" ]; then
  ok "$image is op te halen"
  if echo "$manifest" | grep -q '"amd64"' && echo "$manifest" | grep -q '"arm64"'; then
    ok "multi-arch: amd64 en arm64"
  else
    fout "niet beide architecturen gevonden" "platforms: linux/amd64,linux/arm64"
  fi
else
  fout "$image is niet op te halen" "Is het package publiek? (stap 17)"
fi

echo
if [ "$fouten" -eq 0 ]; then
  printf "\033[32mGeslaagd! Door naar module 06: je eigen server.\033[0m\n\n"
else
  printf "\033[31m%d punt(en) nog niet in orde.\033[0m\n\n" "$fouten"
  exit 1
fi
