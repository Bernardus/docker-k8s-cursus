#!/usr/bin/env bash
# Controleert de eindopdracht van module 03.
# Gebruik: ./check.sh

fouten=0
ok()   { printf "  \033[32m✔\033[0m %s\n" "$1"; }
fout() { printf "  \033[31m✘\033[0m %s\n" "$1"; [ -n "$2" ] && printf "      → %s\n" "$2"; fouten=$((fouten + 1)); }

draait() { [ "$(podman inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = "true" ]; }

app="$(cd "$(dirname "$0")/../../app/api" && pwd)"
api_poort=${API_POORT:-3000}

echo
echo "Module 03 — Je eerste eigen image"
echo

if ! podman info >/dev/null 2>&1; then
  fout "Podman-machine niet bereikbaar" "podman machine start"
  echo; exit 1
fi

# --- bestanden ------------------------------------------------------------
echo "app/api"
if grep -qx "node_modules" "$app/.dockerignore" 2>/dev/null; then
  ok ".dockerignore houdt node_modules buiten de build"
else
  fout ".dockerignore ontbreekt of mist node_modules" "Maak app/api/.dockerignore (stap 8)."
fi
fases=$(grep -ci '^FROM ' "$app/Dockerfile" 2>/dev/null)
if [ "${fases:-0}" -ge 2 ]; then
  ok "Dockerfile is multi-stage"
else
  fout "Dockerfile heeft geen twee fases" "Zie stap 9: twee keer FROM."
fi

# --- image ----------------------------------------------------------------
echo
echo "image snip-api:1"
if podman image exists snip-api:1; then
  ok "image bestaat"
  mb=$(( $(podman image inspect snip-api:1 -f '{{.Size}}') / 1000000 ))
  if [ "$mb" -lt 400 ]; then
    ok "grootte: ${mb} MB"
  else
    fout "image is ${mb} MB, verwacht minder dan 400" "Gebruik node:24-slim en een multi-stage build."
  fi
  gebruiker=$(podman image inspect snip-api:1 -f '{{.Config.User}}')
  if [ -n "$gebruiker" ] && [ "$gebruiker" != "root" ]; then
    ok "draait als '$gebruiker', niet als root"
  else
    fout "image draait als root" "USER node"
  fi
  if podman run --rm snip-api:1 test -e /app/src 2>/dev/null; then
    fout "broncode (src/) zit in het eindimage" "Kopieer in fase 2 alleen dist/ met COPY --from=build."
  else
    ok "geen broncode in het eindimage"
  fi
else
  fout "image snip-api:1 niet gevonden" "podman build -t snip-api:1 .  (in app/api)"
fi

# --- container ------------------------------------------------------------
echo
echo "container snip-api"
if draait snip-api; then
  ok "container draait"
  case "$(podman inspect snip-api -f '{{.ImageName}}')" in
    *snip-api:1) ok "gemaakt van snip-api:1" ;;
    *)           fout "gemaakt van $(podman inspect snip-api -f '{{.ImageName}}'), verwacht snip-api:1" ;;
  esac
  if podman inspect snip-api -f '{{range $naam, $_ := .NetworkSettings.Networks}}{{$naam}} {{end}}' | grep -qw snip-net; then
    ok "hangt aan snip-net"
  else
    fout "hangt niet aan snip-net" "--network snip-net"
  fi
  if curl -s --max-time 3 "localhost:$api_poort/health" | grep -q '"ok"'; then
    ok "bereikbaar op http://localhost:$api_poort"
  else
    fout "niet bereikbaar op http://localhost:$api_poort" "-p $api_poort:3000"
  fi
  db=$(curl -s --max-time 3 "localhost:$api_poort/health/db")
  if echo "$db" | grep -q '"database":"ok"'; then
    ok "API praat met de database"
  else
    fout "API kan niet bij de database: $db" "DATABASE_URL=postgres://postgres:geheim@snip-db:5432/snip"
  fi
  if curl -s --max-time 3 "localhost:$api_poort/api/info" | grep -q '"versie":"1"'; then
    ok "APP_VERSION is 1"
  else
    fout "/api/info toont niet versie 1" "-e APP_VERSION=1"
  fi
  doel=$(curl -s --max-time 3 -o /dev/null -w '%{redirect_url}' "localhost:$api_poort/k3s")
  if [ "$doel" = "https://k3s.io" ] || [ "$doel" = "https://k3s.io/" ]; then
    ok "/k3s stuurt door naar $doel"
  else
    fout "/k3s stuurt niet door naar https://k3s.io" "Maak de link aan met curl -X POST (stap 16)."
  fi
else
  fout "container snip-api draait niet" "podman ps -a  → podman logs snip-api"
fi

# --- database nog steeds dicht? --------------------------------------------
echo
if draait snip-db && [ -z "$(podman port snip-db 2>/dev/null)" ]; then
  ok "snip-db draait en is nog steeds niet bereikbaar vanaf je Mac"
elif draait snip-db; then
  fout "snip-db heeft een gepubliceerde poort" "Niet nodig: de API zit op hetzelfde netwerk."
else
  fout "snip-db draait niet" "Zie stap 14."
fi

echo
if [ "$fouten" -eq 0 ]; then
  printf "\033[32mGeslaagd! Door naar module 04.\033[0m\n\n"
else
  printf "\033[31m%d punt(en) nog niet in orde.\033[0m\n\n" "$fouten"
  exit 1
fi
