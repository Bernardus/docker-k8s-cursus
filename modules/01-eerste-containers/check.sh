#!/usr/bin/env bash
# Controleert de eindopdracht van module 01.
# Gebruik: ./check.sh

fouten=0
ok()   { printf "  \033[32m✔\033[0m %s\n" "$1"; }
fout() { printf "  \033[31m✘\033[0m %s\n" "$1"; [ -n "$2" ] && printf "      → %s\n" "$2"; fouten=$((fouten + 1)); }
info() { printf "  \033[34mℹ\033[0m %s\n" "$1"; }

draait() { [ "$(podman inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = "true" ]; }
image_van() { podman inspect -f '{{.Config.Image}}' "$1" 2>/dev/null; }

echo
echo "Module 01 — Eerste containers"
echo

if ! command -v podman >/dev/null 2>&1; then
  fout "podman niet gevonden" "Open een nieuwe terminal, of zie module 00."
  echo; exit 1
fi

if ! podman info >/dev/null 2>&1; then
  fout "Podman-machine niet bereikbaar" "podman machine start"
  echo; exit 1
fi

# --- snip-web -------------------------------------------------------------
echo "snip-web"
if draait snip-web; then
  ok "container draait"
  case "$(image_van snip-web)" in
    *nginx*) ok "gebaseerd op $(image_van snip-web)" ;;
    *)      fout "image is $(image_van snip-web), verwacht nginx:alpine" ;;
  esac
  if podman port snip-web 80 2>/dev/null | grep -q ":8080$"; then
    ok "poort 8080 → 80 gepubliceerd"
  else
    fout "poort 80 van de container is niet gepubliceerd op 8080" "Gebruik -p buiten:binnen"
  fi
  if curl -s --max-time 3 localhost:8080 | grep -qi "snip"; then
    ok "http://localhost:8080 toont jouw pagina"
  else
    fout "http://localhost:8080 toont nog niet de snip-pagina" "podman cp bestanden/index.html snip-web:/usr/share/nginx/html/"
  fi
else
  fout "container 'snip-web' draait niet" "podman ps -a  → bestaat hij wel? podman logs snip-web"
fi

# --- snip-db --------------------------------------------------------------
echo
echo "snip-db"
if draait snip-db; then
  ok "container draait"
  case "$(image_van snip-db)" in
    *postgres*) ok "gebaseerd op $(image_van snip-db)" ;;
    *)         fout "image is $(image_van snip-db), verwacht postgres:18-alpine" ;;
  esac
  aantal=$(podman exec snip-db psql -U postgres -d snip -tAc "SELECT count(*) FROM links" 2>/dev/null)
  if [ -z "$aantal" ]; then
    fout "tabel 'links' in database 'snip' niet gevonden" "POSTGRES_DB=snip meegegeven? bestanden/links.sql ingeladen?"
  elif [ "$aantal" -ge 2 ]; then
    ok "tabel 'links' heeft $aantal rijen"
  else
    fout "tabel 'links' heeft $aantal rij(en), verwacht minstens 2"
  fi
else
  fout "container 'snip-db' draait niet" "podman ps -a  → bestaat hij wel? podman logs snip-db"
fi

# --- opgeruimd? -----------------------------------------------------------
# Alleen containers uit deze module; andere projecten laten we met rust.
echo
rest=$(podman ps -a --format '{{.Names}}' | grep -E '^(web[0-9]|node-bg|db-kapot)$' | tr '\n' ' ')
if [ -n "$rest" ]; then
  info "nog niet opgeruimd uit de oefeningen: $rest → podman rm -f $rest"
fi

echo
if [ "$fouten" -eq 0 ]; then
  printf "\033[32mGeslaagd! Door naar module 02.\033[0m\n\n"
else
  printf "\033[31m%d punt(en) nog niet in orde.\033[0m\n\n" "$fouten"
  exit 1
fi
