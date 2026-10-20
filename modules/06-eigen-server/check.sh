#!/usr/bin/env bash
# Controleert de eindopdracht van module 06. Draai dit op je Mac.
# Gebruik: ./check.sh

fouten=0
ok()   { printf "  \033[32m✔\033[0m %s\n" "$1"; }
fout() { printf "  \033[31m✘\033[0m %s\n" "$1"; [ -n "$2" ] && printf "      → %s\n" "$2"; fouten=$((fouten + 1)); }
op_server() { ssh -o BatchMode=yes -o ConnectTimeout=5 snip "$@" 2>/dev/null; }

echo
echo "Module 06 — Je eigen server"
echo

# --- SSH ------------------------------------------------------------------
echo "SSH"
ip=$(ssh -G snip 2>/dev/null | awk '/^hostname /{print $2}')
if [ -z "$ip" ] || [ "$ip" = "snip" ]; then
  fout "geen 'Host snip' in ~/.ssh/config" "Zie stap 9."
  echo; exit 1
fi
gebruiker=$(op_server whoami)
if [ "$gebruiker" = "deploy" ]; then
  ok "ssh snip werkt, als deploy ($ip)"
else
  fout "inloggen met 'ssh snip' lukt niet zonder vragen" "Probeer zelf: ssh snip. Moet je een wachtwoordzin typen? Dan: ssh-add --apple-use-keychain ~/.ssh/snip_vps"
  echo; exit 1
fi
if ssh -o BatchMode=yes -o ConnectTimeout=5 -i ~/.ssh/snip_vps "root@$ip" true 2>/dev/null; then
  fout "inloggen als root is nog mogelijk" "PermitRootLogin no (stap 10)"
else
  ok "inloggen als root is uitgeschakeld"
fi
methoden=$(ssh -o BatchMode=yes -o ConnectTimeout=5 -o PreferredAuthentications=none -o PubkeyAuthentication=no "nobody@$ip" 2>&1 | grep -o 'Permission denied (.*)')
if echo "$methoden" | grep -q password; then
  fout "inloggen met een wachtwoord is nog mogelijk" "PasswordAuthentication no (stap 10)"
else
  ok "alleen inloggen met een sleutel ($methoden)"
fi

# --- Docker en containers -------------------------------------------------
echo
echo "Docker"
if op_server docker version --format '{{.Server.Version}}' >/dev/null; then
  ok "Docker $(op_server docker version --format '{{.Server.Version}}') op $(op_server uname -m)"
else
  fout "Docker werkt niet voor deploy" "Stap 11–12, en daarna opnieuw inloggen."
fi
for c in snip-db-1 snip-api-1 snip-web-1; do
  status=$(op_server "docker inspect -f '{{.State.Status}} {{.HostConfig.RestartPolicy.Name}}' $c")
  case "$status" in
    "running unless-stopped") ok "$c draait, met restart: unless-stopped" ;;
    running*)                 fout "$c draait, maar zonder restart: unless-stopped" ;;
    *)                        fout "$c draait niet" "ssh snip 'cd snip && docker compose ps'" ;;
  esac
done
case "$(op_server docker inspect -f '{{.Config.Image}}' snip-api-1)" in
  ghcr.io/*) ok "api komt uit GHCR" ;;
  *)         fout "api komt niet uit GHCR" "image: ghcr.io/<jij>/snip-api:\${SNIP_VERSION:-latest}" ;;
esac
opgestart=$(op_server "date -d \"\$(uptime -s)\" +%s")
gemaakt=$(op_server 'date -d "$(docker inspect -f "{{.Created}}" snip-db-1)" +%s')
if [ -n "$opgestart" ] && [ -n "$gemaakt" ] && [ "$gemaakt" -lt "$opgestart" ]; then
  ok "containers zijn ouder dan de laatste reboot: ze kwamen vanzelf terug"
else
  fout "nog geen reboot gedaan sinds de containers zijn gemaakt" "ssh snip sudo reboot  (stap 18)"
fi

# --- secrets ---------------------------------------------------------------
echo
echo "wachtwoord"
if [ "$(op_server stat -c %a snip/.env)" = "600" ]; then
  ok ".env op de server is alleen leesbaar voor deploy"
else
  fout ".env ontbreekt of is voor anderen leesbaar" "chmod 600 ~/snip/.env"
fi
if op_server grep -q geheim snip/.env; then
  fout "je gebruikt het wachtwoord 'geheim' op de server" "Maak een willekeurig wachtwoord (stap 15)."
else
  ok "geen 'geheim' als wachtwoord"
fi

# --- van buiten ----------------------------------------------------------
echo
echo "van buiten (http://$ip)"
if curl -s --max-time 5 "http://$ip/" | grep -q "<title>snip</title>"; then
  ok "website bereikbaar"
else
  fout "website niet bereikbaar" "Draait web? Staat poort 80 open in de firewall van DigitalOcean?"
fi
if curl -s --max-time 5 "http://$ip/api/info" | grep -q '"versie":"sha-'; then
  ok "api bereikbaar via de website, met een versie uit de pipeline"
else
  fout "/api/info werkt niet via de website"
fi
open_poorten=""
for poort in 5432 3000 8080; do
  nc -z -G 3 "$ip" "$poort" 2>/dev/null && open_poorten="$open_poorten $poort"
done
if [ -z "$open_poorten" ]; then
  ok "database en api niet rechtstreeks bereikbaar (5432, 3000 dicht)"
else
  fout "van buiten bereikbaar:$open_poorten" "Alleen 22, 80 en 443 horen open te staan."
fi

echo
if [ "$fouten" -eq 0 ]; then
  printf "\033[32mGeslaagd! snip staat online. Door naar module 07.\033[0m\n\n"
else
  printf "\033[31m%d punt(en) nog niet in orde.\033[0m\n\n" "$fouten"
  exit 1
fi
