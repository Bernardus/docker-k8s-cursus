# Module 06 — Je eigen server

**Doel:** je huurt een server (een *droplet*) bij DigitalOcean, maakt hem veilig, installeert Docker, en zet snip
online met Compose. Je kunt het hele internet een korte link laten maken.

**Tijd:** ±2 uur

**Nodig:**
- module 05 afgerond: `ghcr.io/<jij>/snip-api:latest` staat publiek op GHCR
- een creditcard of PayPal voor DigitalOcean (ca. $12 per maand, per seconde afgerekend; je
  kunt hem na de cursus weggooien)

> Op de server gebruiken we **Docker**. De bedrijfsregel "geen Docker" geldt voor je Mac, niet
> voor je eigen server. Je `compose.yaml` en je commando's werken hetzelfde: `docker compose`
> in plaats van `podman compose`.

---

## Uitleg

### Wat is een VPS?

Een **VPS** (*virtual private server*) is een virtuele machine in een datacenter, die je per
maand of per uur huurt. Je krijgt een Linux-installatie, een publiek IP-adres, en volledige
toegang (*root*). Wat er verder op komt, regel je zelf.

Dat "zelf" is het verschil met je Mac. Er is geen Podman Desktop en geen grafische schil, en de
server staat **24 uur per dag aan het internet**. Binnen een paar minuten na het aanmaken
proberen bots al in te loggen. Daarom maken we hem eerst veilig, en pas daarna zetten we er iets
op.

### Wat we bouwen

```
  internet
     │
     ▼
┌──────────── DigitalOcean Cloud Firewall ──────────────┐  alleen 22 (SSH), 80, 443 open
│                                                       │
│   VPS (Ubuntu)                                        │
│   ├── SSH: alleen met sleutel, niet als root          │
│   └── Docker                                          │
│        └── compose: snip                              │
│             web (nginx) :80 ──► api ──► db + volume   │
└───────────────────────────────────────────────────────┘
```

### Inloggen met een sleutel, niet met een wachtwoord

Met **SSH** log je in op een server en krijg je daar een terminal. Je kunt dat met een wachtwoord
doen, maar dat is precies wat die bots proberen te raden. Daarom gebruiken we een
**SSH-sleutelpaar**:

| Deel | Waar | Delen? |
|---|---|---|
| **privésleutel** (`~/.ssh/snip_vps`) | alleen op je Mac | **nooit** |
| **publieke sleutel** (`~/.ssh/snip_vps.pub`) | op de server | mag iedereen zien |

De server stuurt een puzzel die alleen de privésleutel kan oplossen. Er gaat geen wachtwoord over
de lijn, en er valt niets te raden. Daarna zetten we inloggen met een wachtwoord helemaal uit.

### Twee firewalls: waarom de firewall van DigitalOcean

Op Linux is `ufw` de bekendste firewall. Maar **Docker gaat eromheen**: als je een poort
publiceert (`ports: "5432:5432"`), past Docker zelf de netwerkregels van de server aan, en die
gaan vóór de regels van `ufw`. Je denkt dan dat poort 5432 dicht zit, terwijl hij wijd open staat.
Dit is een van de bekendste valkuilen met Docker op een server.

Daarom gebruiken we de **Cloud Firewall van DigitalOcean**. Die zit **buiten** de server, in het
netwerk van DigitalOcean. Wat Docker binnen de server ook doet, wat daar niet open staat, komt er niet in.

### Lokaal vs. server

| | Lokaal (module 04) | Server (deze module) |
|---|---|---|
| Engine | Podman | Docker |
| API | `build: ./api` (zelf bouwen) | `image: ghcr.io/...` (kant-en-klaar) |
| Na een reboot | niets | `restart: unless-stopped`: alles komt terug |
| Poort | 8080 | 80, de standaardpoort voor http |
| Wachtwoord | `geheim` in `.env` | lang en willekeurig, alleen op de server |
| Adminer | ja, met profiel | nee |

---

## Lab

### Deel A — Een SSH-sleutel

**1. Sleutel maken**

Op je Mac:

```bash
ssh-keygen -t ed25519 -C "snip-vps" -f ~/.ssh/snip_vps
```

Kies een wachtwoordzin (*passphrase*). Die beschermt de sleutel als iemand je laptop in handen
krijgt. macOS kan hem onthouden in de sleutelhanger.

```bash
cat ~/.ssh/snip_vps.pub
```

Dit is de publieke sleutel, één regel die begint met `ssh-ed25519`. Die heb je zo nodig.

### Deel B — De server huren

**2. DigitalOcean-account**

Maak een account op <https://cloud.digitalocean.com> en maak een **project** aan, bijvoorbeeld
`snip`.

**3. Je publieke sleutel toevoegen**

**Settings → Security → SSH Keys → Add SSH Key**. Plak de regel uit stap 1 en noem hem
`snip-vps`.

**4. De droplet**

**Create → Droplets**:

| Instelling | Kies |
|---|---|
| Region | **Amsterdam** (AMS3) of Frankfurt (FRA1) |
| Image | **Ubuntu 26.04 (LTS)** (staat hij er niet, dan 24.04) |
| Size | **Basic → Regular → 1 vCPU / 2 GB** ($12/maand) |
| Authentication | **SSH Key** → `snip-vps` |
| Hostname | `snip` |

Laat de rest op de standaardwaarden staan, en klik **Create Droplet**. Na een minuut staat je
droplet er, met een **IPv4-adres**. Noteer dat; in de rest van de module staat het als `<IP>`.

> **Kosten.** Je betaalt per seconde, ook als de droplet **uit** staat. Alleen een
> **verwijderde** droplet kost niets meer. Ben je klaar met de cursus, of neem je een lange
> pauze? Verwijder hem dan (en maak eerst een back-up, stap 19).

**5. Een firewall**

**Networking → Firewalls → Create Firewall**, naam `snip-fw`. Zet bij **Inbound Rules** precies
deze regels:

| Type | Poort | Waarvoor |
|---|---|---|
| ICMP | — | `ping` (handig om te testen) |
| SSH | 22 | inloggen |
| HTTP | 80 | http |
| HTTPS | 443 | https (module 07) |

Laat **Outbound Rules** op de standaardwaarde staan (alles mag): de server moet updates en
images kunnen downloaden. Kies onderaan bij **Apply to Droplets** je droplet `snip`, en klik
**Create Firewall**.

### Deel C — Inloggen en veilig maken

**6. Eerste keer inloggen**

```bash
ssh -i ~/.ssh/snip_vps root@<IP>
```

De eerste keer vraagt SSH of je deze server vertrouwt (`fingerprint`): typ `yes`. Je zit nu als
**root** op je server. Kijk rond:

```bash
cat /etc/os-release
uname -m
df -h /
free -h
```

`uname -m` geeft `x86_64`: een Intel/AMD-machine. Docker pakt straks dus de `amd64`-variant van je
image uit module 05.

**7. Updates**

```bash
apt update && apt full-upgrade -y
```

> **Een paarse vraag over `sshd_config`?** DigitalOcean heeft dat bestand bij het aanmaken
> aangepast, en de update heeft een nieuwe standaardversie. Kies **keep the local version
> currently installed**: daarmee ben je net ingelogd, dus die werkt. Je eigen instellingen
> zet je in stap 10 in een apart bestand, dat geen update ooit overschrijft. Komt er nog zo'n
> vraag over een ander bestand, kies dan ook de lokale versie.

Ubuntu installeert beveiligingsupdates daarna automatisch (*unattended-upgrades* staat standaard
aan). Moet de server herstarten voor een update, dan zie je dat bij het inloggen.

**8. Een eigen gebruiker**

Werken als root is gevaarlijk: één tikfout kan alles slopen. Maak een gebruiker `deploy` aan, die
met jouw sleutel kan inloggen en via `sudo` beheerder kan worden:

```bash
adduser --disabled-password --gecos "" deploy
usermod -aG sudo deploy
echo "deploy ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/deploy
install -d -m 700 -o deploy -g deploy /home/deploy/.ssh
install -m 600 -o deploy -g deploy /root/.ssh/authorized_keys /home/deploy/.ssh/authorized_keys
```

- `--disabled-password`: deze gebruiker heeft geen wachtwoord, alleen je sleutel.
- `NOPASSWD`: `sudo` vraagt niet om een wachtwoord, want er is er geen. Voor een eigen
  leerserver is dat acceptabel; op je werk zou dit niet mogen.
- `authorized_keys`: de lijst met publieke sleutels die mogen inloggen. We kopiëren die van root.

**9. Een snelkoppeling op je Mac**

Open een **tweede terminal** op je Mac (laat de root-sessie open!) en voeg dit toe aan je
SSH-configuratie:

```bash
cat >> ~/.ssh/config <<EOF

Host snip
  HostName <IP>
  User deploy
  IdentityFile ~/.ssh/snip_vps
  AddKeysToAgent yes
  UseKeychain yes
EOF
```

Vervang `<IP>` door je echte IP-adres. Probeer:

```bash
ssh snip
```

Je bent nu `deploy` op je server. Test of `sudo` werkt:

```bash
sudo whoami
```

`root`. Mooi.

**10. Root en wachtwoorden uitzetten**

Nog steeds als `deploy` op de server:

```bash
sudo tee /etc/ssh/sshd_config.d/10-snip.conf <<EOF
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
EOF
sudo sshd -t && sudo systemctl reload ssh
```

`sshd -t` controleert eerst of de configuratie klopt. Pas dan wordt SSH herladen. Een fout in de
SSH-configuratie kan je namelijk buitensluiten.

**Test dit in een derde terminal, voordat je de andere sessies sluit:**

```bash
ssh snip whoami
ssh -i ~/.ssh/snip_vps root@<IP>
```

Het eerste geeft `deploy`, het tweede `Permission denied`. Werkt het eerste? Dan kun je de
root-sessie uit stap 6 sluiten met `exit`.

> **Sluit je jezelf toch buiten?** Bij je droplet in DigitalOcean staat onder **Access** de
> **Recovery Console**: een terminal in je browser, die niet via SSH loopt. Root heeft geen
> wachtwoord; via **Reset Root Password** (ook onder Access) mailt DigitalOcean je een tijdelijk
> wachtwoord, waarmee je in die console kunt inloggen en het herstellen.

### Deel D — Docker installeren

**11. De officiële Docker-pakketbron**

Ubuntu heeft zelf ook een `docker.io`-pakket, maar dat loopt achter. We gebruiken de pakketbron
van Docker zelf (dit zijn de stappen uit de officiële documentatie):

```bash
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
```

In gewone taal: vertrouw de sleutel van Docker, en voeg hun pakketbron toe voor jouw versie en
architectuur van Ubuntu.

**12. Installeren**

```bash
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker deploy
```

De tweede regel zet `deploy` in de groep `docker`, zodat je niet steeds `sudo docker` hoeft te
typen. Log uit en weer in, zodat dat actief wordt:

```bash
exit
```

```bash
ssh snip
docker version
docker compose version
docker run --rm hello-world
```

`Hello from Docker!`: hier is het écht Docker, met een daemon. Kijk bij `docker version` naar
`Server`: `linux/amd64` of `linux/arm64`, zonder VM ertussen. De server ís Linux.

> **Let op:** wie in de groep `docker` zit, kan via Docker alles op de server, net als root.
> Zet er alleen gebruikers in die je ook root zou geven.

### Deel E — snip online

**13. Het compose-bestand voor de server**

Op je **Mac**, in `app/`, maak een bestand `compose.server.yaml`:

```yaml
# compose.yaml voor de server. Verschillen met de lokale versie:
#   - api komt als kant-en-klaar image uit GHCR (op de server wordt niets gebouwd)
#   - restart: unless-stopped, zodat alles na een reboot vanzelf terugkomt
#   - web op poort 80, de standaardpoort voor http
#   - wachtwoord verplicht: zonder .env stopt Compose met een duidelijke melding
#   - geen adminer
name: snip

services:
  db:
    image: postgres:18-alpine
    restart: unless-stopped
    environment:
      POSTGRES_DB: snip
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:?zet POSTGRES_PASSWORD in .env}
    volumes:
      - db-data:/var/lib/postgresql
      - ./db/links.sql:/docker-entrypoint-initdb.d/links.sql:ro
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "postgres", "-d", "snip"]
      interval: 5s
      timeout: 3s
      retries: 10

  api:
    image: ghcr.io/bernardus/snip-api:${SNIP_VERSION:-latest}
    restart: unless-stopped
    environment:
      DATABASE_URL: postgres://postgres:${POSTGRES_PASSWORD}@db:5432/snip
    depends_on:
      db:
        condition: service_healthy

  web:
    image: nginx:alpine
    restart: unless-stopped
    ports:
      - "80:80"
    volumes:
      - ./web/site:/usr/share/nginx/html:ro
      - ./web/nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - api

volumes:
  db-data:
```

Wat er nieuw is:

| Regel | Betekenis |
|---|---|
| `restart: unless-stopped` | start opnieuw na een crash of reboot, behalve als jij hem zelf stopte |
| `${POSTGRES_PASSWORD:?...}` | **verplicht**: ontbreekt de waarde, dan weigert Compose te starten (vergelijk breek-het 1 van module 04, waar hij stilletjes leeg bleef) |
| `${SNIP_VERSION:-latest}` | welke versie van de API; standaard `latest`. In module 07 zet de pipeline hier een vaste versie neer |
| `image: ghcr.io/...` | geen `build`: de server bouwt niets, hij haalt het image dat GitHub Actions maakte |

**14. Bestanden naar de server**

Op je Mac, in de hoofdmap van de cursus:

```bash
cd ~/Documents/local/docker-k8s-cursus
ssh snip mkdir -p snip
rsync -av app/web app/db snip:snip/
rsync -av app/compose.server.yaml snip:snip/compose.yaml
```

`rsync` kopieert bestanden over SSH, en bij een volgende keer alleen wat er veranderd is. Op de
server heet het bestand gewoon `compose.yaml`.

**15. Het geheime wachtwoord**

Op de **server** (`ssh snip`):

```bash
cd ~/snip
printf 'POSTGRES_PASSWORD=%s\n' "$(openssl rand -hex 24)" > .env
chmod 600 .env
ls -la
```

`openssl rand` maakt een willekeurig wachtwoord van 48 tekens. Je hoeft het niet te kennen: alleen
de containers gebruiken het. `chmod 600` zorgt dat alleen `deploy` het bestand kan lezen. Het
wachtwoord staat dus **alleen op de server**, niet op je Mac en niet in Git.

**16. Starten**

```bash
docker compose up -d
docker compose ps
```

Docker haalt de images op (ook jouw `snip-api` uit GHCR) en start alles. Wacht tot `db`
`healthy` is.

Open op je Mac **`http://<IP>`**. Daar is snip, op het internet. Maak een korte link en stuur
hem naar iemand: `http://<IP>/jouwcode` werkt overal ter wereld.

**17. Kijken wat er draait**

```bash
docker compose logs -f
docker compose exec api node -p process.env.APP_VERSION
docker image inspect ghcr.io/bernardus/snip-api:latest --format '{{.Architecture}}'
```

De versie is de `sha-...` uit je pipeline. De architectuur past bij je server, zonder dat je iets
hoefde te kiezen.

**18. Overleeft het een reboot?**

```bash
sudo reboot
```

Je SSH-verbinding wordt verbroken. Wacht een halve minuut en ververs `http://<IP>`. snip is er
weer, inclusief je links. Docker start bij het opstarten automatisch, en dankzij
`restart: unless-stopped` start Docker daarna je containers.

**19. Een back-up**

Vanaf je **Mac**:

```bash
ssh snip 'cd snip && docker compose exec -T db pg_dump -U postgres snip' > snip-backup.sql
head snip-backup.sql
```

`pg_dump` schrijft de hele database als SQL naar je terminal, en `>` zet het in een bestand op je
Mac. `-T` betekent: geen terminal (geen `-t`), want er zit geen mens aan de andere kant.

---

## Breek het

### 💥 1. Alles draait, maar de site is weg

Haal bij DigitalOcean in je firewall `snip-fw` de regel voor **HTTP (80)** weg. Ververs
`http://<IP>`.

<details>
<summary>Hint</summary>

Draait alles nog? Kijk met `ssh snip 'cd snip && docker compose ps'`. Werkt de site
**op** de server? Kijk met `ssh snip curl -s localhost | head -3`.
</details>

<details>
<summary>Uitleg en oplossing</summary>

De containers draaien en de site werkt op de server zelf, maar van buiten krijg je een time-out.
Verkeer gaat door meerdere lagen, en elke laag kan het tegenhouden:

```
 browser → cloud-firewall → server:80 → Docker → web-container:80 → api → db
             ▲ hier stopt het
```

Debuggen doe je laag voor laag, van binnen naar buiten: werkt het in de container? Op de server?
Van buiten? De laag waar het stopt werken, is je probleem. Dat geldt straks ook in Kubernetes.

Zet de regel voor TCP 80 terug.
</details>

### 💥 2. De vergeten `.env`

Op de server:

```bash
cd ~/snip
mv .env .env.weg
docker compose up -d
```

<details>
<summary>Uitleg</summary>

`required variable POSTGRES_PASSWORD is missing a value: zet POSTGRES_PASSWORD in .env`

Compose weigert te starten, met precies jouw melding. Vergelijk met module 04, waar de database
startte met een leeg wachtwoord en het daarna misging. Met `:?` zie je de fout **voordat** er
iets kapot gaat.

```bash
mv .env.weg .env
```
</details>

### 💥 3. Een privé-image

Zet op GitHub je package `snip-api` tijdelijk op **Private** (Package settings → Change
visibility). Dan op de server:

```bash
cd ~/snip
docker compose pull api
```

<details>
<summary>Uitleg en oplossing</summary>

`denied` of `unauthorized`. De server is niet ingelogd bij GHCR, en een privé-image mag
alleen opgehaald worden door wie toegang heeft.

Voor een privé-image zou je op de server inloggen met een *personal access token* met alleen het
recht `read:packages`: `docker login ghcr.io`. Op je werk gaat dat netter, met een
*managed identity* die Azure regelt, zodat er nergens een wachtwoord op de server staat.

Zet je package terug op **Public**.
</details>

---

## Op je werk

- **Niemand logt in op productieservers.** Wat jij hier met de hand doet (inloggen, installeren,
  bestanden kopiëren), gebeurt in een enterprise met code. Servers worden gemaakt met
  Terraform, ingericht met tools als Ansible of cloud-init, en bij een probleem vervangen in
  plaats van gerepareerd. Je behandelt ze als vee, niet als huisdieren, net als containers.
- **SSH-toegang loopt via een tussenstation.** Als het al nodig is, gaat het via een *bastion*
  of *Azure Bastion*, met tijdelijke rechten en alles gelogd.
- **Updates en patches** zijn de taak van het platformteam. Op AKS beheert Microsoft de
  besturingssystemen van de nodes grotendeels.
- **Secrets staan niet in een `.env` op een server**, maar in Key Vault. De app krijgt ze via een
  managed identity of via Kubernetes.
- **Waarom dan toch deze module?** Omdat je nu weet wat er onder al die abstracties zit: een
  Linux-machine, een firewall, een container-engine en een paar containers. Als er op je werk
  iets misgaat, denk je in dezelfde lagen.

---

## Checkpoint

<details>
<summary>1. Waarom log je in met een sleutel en niet met een wachtwoord?</summary>

Een wachtwoord kan geraden worden, en bots proberen dat continu. Bij een sleutel gaat er geen
geheim over de lijn, en de privésleutel verlaat je Mac nooit.
</details>

<details>
<summary>2. Waarom gebruiken we de firewall van DigitalOcean en niet <code>ufw</code>?</summary>

Docker past bij gepubliceerde poorten zelf de netwerkregels aan, en gaat daarmee langs `ufw`.
De firewall van DigitalOcean zit buiten de server, en Docker kan daar niet omheen.
</details>

<details>
<summary>3. Wat doet <code>restart: unless-stopped</code>?</summary>

De container wordt opnieuw gestart na een crash of een reboot, behalve als je hem zelf
hebt gestopt.
</details>

<details>
<summary>4. Waarom staat er op de server <code>image:</code> en geen <code>build:</code>?</summary>

Bouwen gebeurt in de pipeline. De server haalt alleen het kant-en-klare, gescande image op.
Zo draait er precies wat getest is, en hoeft de server geen broncode of build-tools te hebben.
</details>

<details>
<summary>5. Wat is het verschil tussen <code>${VAR:-x}</code> en <code>${VAR:?melding}</code>?</summary>

`:-x` gebruikt `x` als standaardwaarde als `VAR` leeg is. `:?melding` stopt met een foutmelding als
`VAR` leeg is.
</details>

<details>
<summary>6. De site is van buiten niet bereikbaar. Hoe zoek je het uit?</summary>

Laag voor laag, van binnen naar buiten: draaien de containers? Werkt het op de server zelf
(`curl localhost`)? Staat de poort open in de firewall?
</details>

### Eindopdracht

Als je het lab hebt gedaan, heb je alles. Controleer vanaf je **Mac**:

```bash
cd ~/Documents/local/docker-k8s-cursus/modules/06-eigen-server
./check.sh
```

Het script logt in via `ssh snip` en controleert: veilige SSH, Docker, de drie containers, dat
ze na een reboot terugkomen, dat alleen de website van buiten bereikbaar is, en dat het
wachtwoord goed is opgeborgen.

Groen? In **module 07** hoef je niet meer met de hand te deployen: na elke push zet GitHub
Actions de nieuwe versie zelf op je server. Plus HTTPS.

---

## Spiekbrief

| Commando | Waar | Wat het doet |
|---|---|---|
| `ssh-keygen -t ed25519 -f ~/.ssh/NAAM` | Mac | sleutelpaar maken |
| `ssh snip` | Mac | inloggen (via `~/.ssh/config`) |
| `ssh snip 'commando'` | Mac | één commando op de server uitvoeren |
| `rsync -av BRON snip:DOEL` | Mac | bestanden naar de server kopiëren |
| `sudo apt update && sudo apt full-upgrade -y` | server | updates installeren |
| `sudo sshd -t` | server | SSH-configuratie controleren vóór herladen |
| `docker compose up -d` / `ps` / `logs -f` | server | zoals `podman compose` |
| `docker compose pull` | server | nieuwe versies van images ophalen |
| `docker compose exec -T db pg_dump -U postgres snip` | server | back-up van de database |
| `sudo reboot` | server | herstarten |

| compose.yaml | |
|---|---|
| `restart: unless-stopped` | terugkomen na crash en reboot |
| `${VAR:-standaard}` | standaardwaarde als `VAR` leeg is |
| `${VAR:?melding}` | verplicht; stoppen met melding als `VAR` leeg is |
