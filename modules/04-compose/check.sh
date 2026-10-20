#!/usr/bin/env bash
# Controleert de eindopdracht van module 04.
# Gebruik: ./check.sh

fouten=0
ok()   { printf "  \033[32m✔\033[0m %s\n" "$1"; }
fout() { printf "  \033[31m✘\033[0m %s\n" "$1"; [ -n "$2" ] && printf "      → %s\n" "$2"; fouten=$((fouten + 1)); }

draait() { [ "$(podman inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = "true" ]; }

app="$(cd "$(dirname "$0")/../../app" && pwd)"
web_poort=${WEB_POORT:-8080}

echo
echo "Module 04 — Compose"
echo

if ! podman info >/dev/null 2>&1; then
  fout "Podman-machine niet bereikbaar" "podman machine start"
  echo; exit 1
fi
if ! podman compose version >/dev/null 2>&1; then
  fout "podman compose werkt niet" "brew install podman-compose (stap 1)"
  echo; exit 1
fi

# --- bestanden ------------------------------------------------------------
echo "app/"
if [ -f "$app/compose.yaml" ]; then
  ok "compose.yaml bestaat"
  for service in db api web adminer; do
    grep -qE "^  $service:" "$app/compose.yaml" || fout "service '$service' ontbreekt in compose.yaml"
  done
  if grep -q "geheim" "$app/compose.yaml"; then
    fout "er staat een wachtwoord in compose.yaml" "Gebruik \${POSTGRES_PASSWORD} en zet de waarde in .env."
  else
    ok "geen wachtwoord in compose.yaml"
  fi
else
  fout "app/compose.yaml niet gevonden"
fi
if [ -f "$app/.env" ] && grep -q "^POSTGRES_PASSWORD=." "$app/.env"; then
  ok ".env bevat POSTGRES_PASSWORD"
else
  fout ".env ontbreekt of is leeg" "cp .env.example .env"
fi
if grep -qx ".env" "$app/.gitignore" 2>/dev/null; then
  ok ".env staat in .gitignore"
else
  fout ".env staat niet in app/.gitignore"
fi

# --- containers -----------------------------------------------------------
echo
echo "containers"
for c in snip_db_1 snip_api_1 snip_web_1; do
  if draait "$c"; then ok "$c draait"; else fout "$c draait niet" "podman compose up -d  → podman compose logs"; fi
done
if [ "$(podman inspect -f '{{.State.Health.Status}}' snip_db_1 2>/dev/null)" = "healthy" ]; then
  ok "db is healthy"
else
  fout "db is niet healthy" "Staat de healthcheck in compose.yaml?"
fi
for c in snip_db_1 snip_api_1; do
  if draait "$c" && [ -n "$(podman port "$c" 2>/dev/null)" ]; then
    fout "$c is bereikbaar van buiten" "Haal 'ports' weg: alleen web is de voordeur."
  fi
done

# --- via de voordeur ------------------------------------------------------
echo
echo "http://localhost:$web_poort"
if curl -s --max-time 3 "localhost:$web_poort/" | grep -q "<title>snip</title>"; then
  ok "website bereikbaar"
else
  fout "website niet bereikbaar" "Draait web, met ports \"$web_poort:80\"?"
fi
if curl -s --max-time 3 "localhost:$web_poort/api/info" | grep -q '"versie":"compose"'; then
  ok "nginx stuurt /api door naar de api"
else
  fout "/api/info werkt niet via de website" "podman compose logs web api"
fi
doel=$(curl -s --max-time 3 -o /dev/null -w '%{redirect_url}' "localhost:$web_poort/compose")
case "$doel" in
  https://docs.podman.io*) ok "/compose stuurt door naar $doel" ;;
  *)                       fout "/compose stuurt niet door naar https://docs.podman.io" "Maak de link aan via de website (stap 4 van de eindopdracht)." ;;
esac

# --- overleeft de data een down + up? ---------------------------------------
oudste=$(podman exec snip_db_1 psql -U postgres -d snip -tAc "SELECT floor(extract(epoch FROM created_at)) FROM links WHERE code = 'compose'" 2>/dev/null)
gemaakt=$(podman inspect snip_db_1 -f '{{.Created.Unix}}' 2>/dev/null)
if [ -n "$oudste" ] && [ -n "$gemaakt" ] && [ "$oudste" -lt "$gemaakt" ]; then
  ok "de link is ouder dan de database-container: overleefde een down + up"
else
  fout "nog geen bewijs dat je data een down + up overleeft" "podman compose down && podman compose up -d"
fi

echo
if [ "$fouten" -eq 0 ]; then
  printf "\033[32mGeslaagd! Door naar module 05.\033[0m\n\n"
else
  printf "\033[31m%d punt(en) nog niet in orde.\033[0m\n\n" "$fouten"
  exit 1
fi
