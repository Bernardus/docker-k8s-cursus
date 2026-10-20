#!/usr/bin/env bash
# Controleert de eindopdracht van module 02.
# Gebruik: ./check.sh

fouten=0
ok()   { printf "  \033[32m✔\033[0m %s\n" "$1"; }
fout() { printf "  \033[31m✘\033[0m %s\n" "$1"; [ -n "$2" ] && printf "      → %s\n" "$2"; fouten=$((fouten + 1)); }

draait()     { [ "$(podman inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = "true" ]; }
netwerken()  { podman inspect -f '{{range $naam, $_ := .NetworkSettings.Networks}}{{$naam}} {{end}}' "$1" 2>/dev/null; }
op_snipnet() { netwerken "$1" | grep -qw snip-net; }

web_poort=${WEB_POORT:-8080}
adminer_poort=${ADMINER_POORT:-8081}

echo
echo "Module 02 — Netwerken & data"
echo

if ! podman info >/dev/null 2>&1; then
  fout "Podman-machine niet bereikbaar" "podman machine start"
  echo; exit 1
fi

# --- netwerk en volume ----------------------------------------------------
echo "netwerk & volume"
if [ "$(podman network inspect snip-net --format '{{.DNSEnabled}}' 2>/dev/null)" = "true" ]; then
  ok "netwerk snip-net bestaat, met DNS"
else
  fout "netwerk snip-net niet gevonden" "podman network create snip-net"
fi
if podman volume exists snip-data 2>/dev/null; then
  ok "volume snip-data bestaat"
else
  fout "volume snip-data niet gevonden" "podman volume create snip-data"
fi

# --- snip-db --------------------------------------------------------------
echo
echo "snip-db"
if draait snip-db; then
  ok "container draait"
  op_snipnet snip-db && ok "hangt aan snip-net" || fout "hangt niet aan snip-net" "--network snip-net"

  volume=$(podman inspect snip-db -f '{{range .Mounts}}{{if eq .Destination "/var/lib/postgresql"}}{{.Name}}{{end}}{{end}}')
  if [ "$volume" = "snip-data" ]; then
    ok "data staat in volume snip-data"
  else
    fout "volume snip-data is niet gekoppeld aan /var/lib/postgresql" "-v snip-data:/var/lib/postgresql"
  fi

  if [ -z "$(podman port snip-db 2>/dev/null)" ]; then
    ok "niet bereikbaar vanaf je Mac (geen -p)"
  else
    fout "snip-db heeft een gepubliceerde poort" "Laat -p weg: alleen containers op snip-net hoeven erbij."
  fi

  aantal=$(podman exec snip-db psql -U postgres -d snip -tAc "SELECT count(*) FROM links" 2>/dev/null)
  if [ -n "$aantal" ] && [ "$aantal" -ge 3 ]; then
    ok "tabel links heeft $aantal rijen"
  else
    fout "tabel links niet gevonden of leeg" "podman exec -i snip-db psql -U postgres -d snip < bestanden/links.sql"
  fi

  oudste=$(podman exec snip-db psql -U postgres -d snip -tAc "SELECT floor(extract(epoch FROM min(created_at))) FROM links" 2>/dev/null)
  gemaakt=$(podman inspect snip-db -f '{{.Created.Unix}}' 2>/dev/null)
  if [ -n "$oudste" ] && [ -n "$gemaakt" ] && [ "$oudste" -lt "$gemaakt" ]; then
    ok "data is ouder dan de container: overleefde een podman rm"
  else
    fout "nog geen bewijs dat de data een nieuwe container overleeft" "Gooi snip-db weg en maak hem opnieuw (stap 7)."
  fi
else
  fout "container snip-db draait niet" "podman ps -a  → podman logs snip-db"
fi

if podman run --rm --network snip-net postgres:18-alpine pg_isready -q -t 3 -h snip-db >/dev/null 2>&1; then
  ok "op snip-net bereikbaar als 'snip-db'"
else
  fout "snip-db is op snip-net niet op naam bereikbaar"
fi

# --- snip-adminer ---------------------------------------------------------
echo
echo "snip-adminer"
if draait snip-adminer; then
  ok "container draait"
  op_snipnet snip-adminer && ok "hangt aan snip-net" || fout "hangt niet aan snip-net" "--network snip-net"
  if curl -s --max-time 3 "localhost:$adminer_poort" | grep -q "Adminer"; then
    ok "bereikbaar op http://localhost:$adminer_poort"
  else
    fout "niet bereikbaar op http://localhost:$adminer_poort" "-p $adminer_poort:8080"
  fi
else
  fout "container snip-adminer draait niet" "podman ps -a  → podman logs snip-adminer"
fi

# --- snip-web -------------------------------------------------------------
echo
echo "snip-web"
if draait snip-web; then
  ok "container draait"
  mount=$(podman inspect snip-web -f '{{range .Mounts}}{{if eq .Destination "/usr/share/nginx/html"}}{{.Type}} {{.RW}} {{.Source}}{{end}}{{end}}')
  case "$mount" in
    "bind false "*/bestanden/site) ok "serveert bestanden/site via een read-only bind mount" ;;
    "bind true "*/bestanden/site)  fout "bind mount is niet read-only" "Zet :ro achter het pad." ;;
    *)                             fout "bestanden/site is niet gekoppeld aan /usr/share/nginx/html" "-v ./bestanden/site:/usr/share/nginx/html:ro" ;;
  esac
  if curl -s --max-time 3 "localhost:$web_poort" | grep -qi "snip"; then
    ok "bereikbaar op http://localhost:$web_poort"
  else
    fout "http://localhost:$web_poort toont de snip-pagina niet" "-p $web_poort:80"
  fi
else
  fout "container snip-web draait niet" "podman ps -a  → podman logs snip-web"
fi

echo
if [ "$fouten" -eq 0 ]; then
  printf "\033[32mGeslaagd! Door naar module 03.\033[0m\n\n"
else
  printf "\033[31m%d punt(en) nog niet in orde.\033[0m\n\n" "$fouten"
  exit 1
fi
