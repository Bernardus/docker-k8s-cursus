#!/usr/bin/env bash
# Controleert de eindopdracht van module 07. Draai dit op je Mac.
# Gebruik: ./check.sh

fouten=0
ok()   { printf "  \033[32m✔\033[0m %s\n" "$1"; }
fout() { printf "  \033[31m✘\033[0m %s\n" "$1"; [ -n "$2" ] && printf "      → %s\n" "$2"; fouten=$((fouten + 1)); }
op_server() { ssh -o BatchMode=yes -o ConnectTimeout=5 snip "$@" 2>/dev/null; }

repo="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$repo" || exit 1
domein=$(gh variable get SNIP_DOMAIN --env production 2>/dev/null)
domein=${domein:-209-38-110-50.sslip.io}

echo
echo "Module 07 — Automatisch deployen, met HTTPS"
echo

# --- HTTPS ----------------------------------------------------------------
echo "HTTPS (https://$domein)"
if [ "$(curl -s --max-time 10 -o /dev/null -w '%{http_code}' "https://$domein/")" = "200" ]; then
  uitgever=$(curl -svI --max-time 10 "https://$domein/" 2>&1 | grep -i 'issuer:' | sed 's/.*O=//; s/;.*//' | head -1)
  ok "geldig certificaat (${uitgever:-uitgever onbekend})"
else
  fout "https://$domein geeft geen geldige HTTPS-verbinding" "ssh snip 'cd snip && docker compose logs caddy'"
fi
doorsturing=$(curl -s --max-time 10 -o /dev/null -w '%{http_code} %{redirect_url}' "http://$domein/")
case "$doorsturing" in
  30[18]\ https://*) ok "http stuurt door naar https" ;;
  *)                 fout "http stuurt niet door naar https ($doorsturing)" ;;
esac

# --- server ---------------------------------------------------------------
echo
echo "server"
poorten=$(op_server "docker ps --format '{{.Names}}={{.Ports}}'" | grep -E '0\.0\.0\.0:|\[::\]:' | cut -d= -f1 | sort -u | tr '\n' ' ')
if [ "$poorten" = "snip-caddy-1 " ]; then
  ok "alleen caddy is van buiten bereikbaar"
else
  fout "containers met een poort naar buiten: ${poorten:-geen}" "Alleen caddy hoort 'ports' te hebben."
fi
if op_server "docker volume inspect snip_caddy-data" >/dev/null; then
  ok "certificaten staan in het volume snip_caddy-data"
else
  fout "volume voor de certificaten ontbreekt" "caddy-data:/data"
fi

# --- GitHub ---------------------------------------------------------------
echo
echo "GitHub"
secrets=$(gh secret list --env production 2>/dev/null | awk '{print $1}' | tr '\n' ' ')
for s in DEPLOY_SSH_KEY DEPLOY_KNOWN_HOSTS; do
  case " $secrets" in *" $s "*) ok "secret $s" ;; *) fout "secret $s ontbreekt in environment production" "Stap 9." ;; esac
done
for v in DEPLOY_HOST SNIP_DOMAIN; do
  if gh variable get "$v" --env production >/dev/null 2>&1; then ok "variable $v"; else fout "variable $v ontbreekt in environment production" "Stap 9."; fi
done

run=$(gh run list --workflow snip-api.yml --branch main --limit 1 --json databaseId,headSha,conclusion -q '.[0] | "\(.databaseId) \(.headSha) \(.conclusion)"' 2>/dev/null)
read -r run_id sha conclusie <<< "$run"
if [ "$conclusie" = "success" ]; then
  ok "laatste run op main is geslaagd"
else
  fout "laatste run op main: ${conclusie:-geen gevonden}" "gh run view --log-failed"
fi
if gh run view "$run_id" --json jobs -q '.jobs[] | "\(.name) \(.conclusion)"' 2>/dev/null | grep -qx "deploy success"; then
  ok "die run heeft gedeployd"
else
  fout "die run heeft geen geslaagde deploy-job" "Staat de job 'deploy' in de workflow? (stap 10)"
fi

versie="sha-${sha:0:7}"
if curl -s --max-time 10 "https://$domein/api/info" | grep -q "\"versie\":\"$versie\""; then
  ok "de site draait $versie: precies de laatste commit op main"
else
  fout "de site draait niet $versie" "curl https://$domein/api/info"
fi

echo
if [ "$fouten" -eq 0 ]; then
  printf "\033[32mGeslaagd! Deel 1 is af. Door naar deel 2: Kubernetes.\033[0m\n\n"
else
  printf "\033[31m%d punt(en) nog niet in orde.\033[0m\n\n" "$fouten"
  exit 1
fi
