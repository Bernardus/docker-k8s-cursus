#!/usr/bin/env bash
# Controleert of je omgeving klaar is voor de cursus.
# Gebruik: ./check.sh

fouten=0
ok()   { printf "  \033[32m✔\033[0m %s\n" "$1"; }
fout() { printf "  \033[31m✘\033[0m %s\n" "$1"; [ -n "$2" ] && printf "      → %s\n" "$2"; fouten=$((fouten + 1)); }
info() { printf "  \033[34mℹ\033[0m %s\n" "$1"; }

echo
echo "Module 00 — Setup"
echo

# --- Podman ---------------------------------------------------------------
if command -v podman >/dev/null 2>&1; then
  ok "podman gevonden ($(podman --version | awk '{print $3}'))"
elif [ -x /opt/podman/bin/podman ]; then
  fout "podman staat wel in /opt/podman/bin, maar niet in je PATH" "Open een nieuwe terminal. Helpt dat niet: overschrijft je ~/.zshrc je PATH? (echo \$PATH)"
  echo; exit 1
else
  fout "podman niet gevonden" "Open Podman Desktop en installeer Podman (stap 1)."
  echo; exit 1
fi

if [ -z "$(podman machine list --format '{{.Name}}' 2>/dev/null)" ]; then
  fout "geen podman machine gevonden" "podman machine init && podman machine start"
  echo; exit 1
fi

if podman machine list --format '{{.Running}}' 2>/dev/null | grep -q true; then
  ok "podman machine draait"
else
  fout "podman machine draait niet" "podman machine start"
  echo; exit 1
fi

if podman info >/dev/null 2>&1; then
  ok "Podman in de machine bereikbaar (server $(podman version --format '{{.Server.Version}}' 2>/dev/null))"
else
  fout "Podman in de machine niet bereikbaar" "podman system connection list  → klopt de default?"
  echo; exit 1
fi

verbinding=$(podman system connection list --format '{{.Name}} {{.Default}}' 2>/dev/null | awk '$2=="true"{print $1}')
info "actieve verbinding: $verbinding"
info "architectuur: $(podman info --format '{{.Host.Arch}}'), rootless: $(podman info --format '{{.Host.Security.Rootless}}')"

if podman run --rm hello-world 2>/dev/null | grep -qE "Hello Podman World|Hello from Docker"; then
  ok "hello-world container draait"
else
  fout "hello-world kon niet draaien" "Probeer 'podman run hello-world' en lees de foutmelding."
fi

# --- Overige tools --------------------------------------------------------
node_major=$(node -v 2>/dev/null | sed -E 's/^v([0-9]+).*/\1/')
if [ -n "$node_major" ] && [ "$node_major" -ge 22 ]; then
  ok "node $(node -v)"
else
  fout "node 22+ niet gevonden" "brew install node"
fi

for tool in git gh kubectl; do
  if command -v "$tool" >/dev/null 2>&1; then
    ok "$tool gevonden"
  else
    fout "$tool niet gevonden" "brew install $tool"
  fi
done

echo
if [ "$fouten" -eq 0 ]; then
  printf "\033[32mAlles in orde. Door naar module 01!\033[0m\n\n"
else
  printf "\033[31m%d punt(en) nog niet in orde.\033[0m\n\n" "$fouten"
  exit 1
fi
