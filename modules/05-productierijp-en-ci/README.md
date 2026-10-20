# Module 05 — Productierijp image en je eerste pipeline

**Doel:** je maakt het `snip-api`-image klaar voor productie: het stopt netjes, kent zijn eigen
versie, heeft geen bekende kwetsbaarheden die je kunt oplossen, en draait op zowel ARM als Intel/AMD.
Daarna laat je het voor het eerst bouwen, scannen en publiceren door **GitHub Actions**.

**Tijd:** ±2 uur

**Nodig:** module 04 afgerond, en een GitHub-account (`gh` is al ingelogd op je Mac)

> De app-code is al aangepast. De API sluit nu netjes af bij een stopsignaal (zie deel A). Jij
> past de **Dockerfile** aan en maakt de **workflow**. De uitwerking staat in
> [`uitwerking/`](uitwerking/).

---

## Uitleg

### "Het werkt" is nog niet "productierijp"

| Eis | Waarom | Waar |
|---|---|---|
| klein, multi-stage | sneller, minder om aan te vallen | ✅ module 03 |
| draait niet als root | inbreker kan minder | ✅ module 03 |
| **stopt netjes** | geen afgebroken verzoeken bij een update | deel A |
| **kent zijn versie** | je weet wat er draait | deel B |
| **geen oplosbare kwetsbaarheden** | bekende gaten dicht | deel C |
| **draait op de server-architectuur** | servers zijn vaak `amd64`, jouw Mac is `arm64` | deel D |
| **gebouwd door een pipeline** | herhaalbaar, controleerbaar, niet "op mijn laptop" | deel E |

### Netjes stoppen: signalen en PID 1

Weet je de bonusvraag uit module 01 nog? `podman stop` op een Node-container duurde 10
seconden, op nginx niet. Zo werkt stoppen:

```
podman stop
   │
   ├─► SIGTERM  "wil je stoppen?"          ← het programma mag nu netjes afronden
   │      ... 10 seconden wachten ...
   └─► SIGKILL  "nu stoppen."              ← hard afgeschoten, niets wordt afgerond
```

nginx luistert naar SIGTERM en stopt meteen. Node doet dat **niet vanzelf** als het proces nummer 1
(PID 1) in een container is. Linux geeft PID 1 namelijk geen standaardreactie op signalen. Node
negeert de SIGTERM dus, Podman wacht 10 seconden en schiet de container dan hard af. Lopende
verzoeken worden afgebroken en databaseverbindingen niet netjes gesloten.

Kubernetes doet precies hetzelfde bij elke update (daar is de wachttijd 30 seconden). Een app die
SIGTERM negeert, maakt dus elke deploy trager en ruwer.

De oplossing zit in de app. Onderaan [`app/api/src/index.ts`](../../app/api/src/index.ts) staat
nu een stukje dat op SIGTERM reageert: geen nieuwe verzoeken meer aannemen, lopende afmaken, de
database loskoppelen en stoppen.

### Versie in het image: ARG en ENV

| | Wanneer | Voorbeeld |
|---|---|---|
| `ARG` | alleen **tijdens het bouwen** | `podman build --build-arg APP_VERSION=2.0.0` |
| `ENV` | ook **als de container draait** | de app leest `process.env.APP_VERSION` |

Met `ARG APP_VERSION` + `ENV APP_VERSION=$APP_VERSION` geef je bij het bouwen een versie mee,
en die zit daarna vast in het image. Je hoeft dan niet meer bij elke `run` `-e APP_VERSION=...`
mee te geven, en de versie klopt altijd met de code. Een `LABEL` zet dezelfde informatie in de
metadata van het image, zodat tools (en jij) het kunnen opvragen zonder het image te starten.

### Kwetsbaarheden scannen

Een **CVE** is een publiek bekend beveiligingslek in een stuk software, met een nummer
(bijv. `CVE-2026-33634`). Een scanner zoals **Trivy** kijkt welke pakketten in je image zitten,
en vergelijkt die met een database van CVE's.

Je zult zien dat de meeste meldingen **niet uit je eigen code komen**, maar uit het basis-image:
Debian-pakketten en de npm-installatie die bij het Node-image hoort. Je kunt drie dingen doen:

1. **Weghalen wat je niet nodig hebt.** npm is nodig om te bouwen, niet om te draaien.
2. **Updaten.** Debian heeft voor sommige lekken al een update die nog niet in het basis-image zit.
3. **Accepteren wat (nog) niet op te lossen is.** Daarom scannen we met `--ignore-unfixed`:
   meldingen zonder beschikbare oplossing tellen niet mee.

### Twee architecturen

Jouw Mac heeft een ARM-chip (`arm64`). De meeste servers, en ook AKS, draaien op Intel/AMD
(`amd64`). Een image is gebouwd voor één architectuur. Een **multi-arch image** is één naam
(`snip-api:latest`) met een variant per architectuur erachter. Podman of Kubernetes kiest bij
het ophalen automatisch de juiste.

```
ghcr.io/jij/snip-api:latest
        ├── linux/amd64   ← voor servers en AKS
        └── linux/arm64   ← voor je Mac en ARM-servers
```

Bouwen voor een andere architectuur gaat via **emulatie** (QEMU): werkt, maar is traag. Daarom
staat in de Dockerfile `FROM --platform=$BUILDPLATFORM ... AS build`: de bouwfase draait altijd op
de snelle, eigen architectuur van de bouwer. Het resultaat is JavaScript, en dat werkt overal.
Alleen de korte laatste fase hoeft per architectuur.

### GitHub Actions in één plaatje

```
 git push
    │
    ▼
 GitHub start een runner (een verse Linux-VM, alleen voor deze run)
    │
    ├─ checkout         je repo ophalen
    ├─ build (amd64)    image bouwen om te scannen
    ├─ trivy            scannen → bij een oplosbare HIGH/CRITICAL: ❌ stop
    ├─ login            inloggen bij GHCR met een tijdelijk token
    └─ build + push     amd64 + arm64 bouwen en publiceren
                              │
                              ▼
                ghcr.io/<jij>/snip-api:sha-abc1234
                ghcr.io/<jij>/snip-api:latest
```

| Begrip | Wat |
|---|---|
| **workflow** | een YAML-bestand in `.github/workflows/` |
| **trigger** (`on:`) | wanneer de workflow start: bij een push, een pull request, met de hand, ... |
| **job** | een reeks stappen op één runner |
| **runner** | de wegwerp-VM waarop het draait |
| **step** / **action** | één stap; een *action* is een herbruikbare stap van iemand anders (`uses:`) |
| **`GITHUB_TOKEN`** | een tijdelijk token dat GitHub per run aanmaakt, hier om naar GHCR te pushen |
| **GHCR** | GitHub Container Registry: `ghcr.io`, de image-registry van GitHub |

Op de runner van GitHub wordt met Docker gebouwd. Dat mag: het is een wegwerp-VM van GitHub, niet
jouw Mac. De Dockerfile is dezelfde, dus het image ook.

### Actions vastpinnen: de les van maart 2026

Een action gebruik je met `uses: eigenaar/naam@versie`. Die versie is meestal een **tag**, zoals
`@v0.35.0`. Een tag kan alleen **verplaatst** worden naar andere code.

In maart 2026 gebeurde precies dat met `aquasecurity/trivy-action`, de scanner die we gebruiken.
Aanvallers kregen toegang tot het project en verplaatsten 76 van de 77 versie-tags naar
kwaadaardige code. Elke pipeline die die action gebruikte, stuurde ongemerkt zijn secrets naar de
aanvallers en voerde daarna gewoon de scan uit. Alles leek normaal. (Het lek staat bekend als
CVE-2026-33634.)

Een **commit-SHA** kan niet verplaatst worden. Daarom staat in onze workflow:

```yaml
uses: aquasecurity/trivy-action@ed142fd0673e97e23eac54620cfb913e5ce36c25 # v0.36.0
```

De SHA bepaalt wat er draait, de comment is voor mensen. Om dezelfde reden pinnen we de
Trivy-versie zelf (`0.76.0`), en niet `latest`.

---

## Lab

### Deel A — Netjes stoppen

**1. Het oude probleem**

Het image `snip-api:1` uit module 03 heeft de oude code nog:

```bash
podman run -d --name stop-oud snip-api:1
time podman stop stop-oud
podman rm stop-oud
```

Ongeveer **10 seconden**.

**2. De nieuwe code**

Kijk onderaan [`app/api/src/index.ts`](../../app/api/src/index.ts). Je hoeft het niet te
begrijpen. Het belangrijkste is dat er `process.on('SIGTERM', ...)` staat: "als SIGTERM binnenkomt,
doe dit". We testen het zo meteen, in deel B.

### Deel B — Dockerfile v3

**3. De nieuwe Dockerfile**

Vervang de inhoud van `app/api/Dockerfile` door:

```dockerfile
# ---- fase 1: bouwen ----------------------------------------------------------
# --platform=$BUILDPLATFORM: deze fase draait altijd op de architectuur van de bouwer zelf
# (snel), ook als we voor een andere architectuur bouwen. Het resultaat is JavaScript, en dat
# werkt overal.
FROM --platform=$BUILDPLATFORM node:24-slim AS build
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY tsconfig.json ./
COPY src ./src
RUN npm run build

# ---- fase 2: draaien ---------------------------------------------------------
FROM node:24-slim
WORKDIR /app

# Versie die de pipeline meegeeft: podman build --build-arg APP_VERSION=...
ARG APP_VERSION=dev
ENV NODE_ENV=production \
    APP_VERSION=$APP_VERSION
LABEL org.opencontainers.image.title="snip-api" \
      org.opencontainers.image.version=$APP_VERSION

# Beveiligingsupdates van Debian die nog niet in het basis-image zitten.
RUN apt-get update && apt-get upgrade -y && rm -rf /var/lib/apt/lists/*

# Alleen productie-dependencies. Daarna npm zelf weg: de app heeft het niet nodig om te draaien,
# en elk programma minder is een kwetsbaarheid minder.
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force \
 && rm -rf /usr/local/lib/node_modules/npm /usr/local/bin/npm /usr/local/bin/npx

COPY --from=build /app/dist ./dist

USER node

EXPOSE 3000
CMD ["node", "dist/index.js"]
```

Wat er nieuw is ten opzichte van module 03:

| Regel | Waarom |
|---|---|
| `--platform=$BUILDPLATFORM` | bouwfase draait altijd native, ook bij bouwen voor een andere architectuur |
| `ARG` + `ENV APP_VERSION` | versie vast in het image |
| `LABEL` | versie ook in de metadata |
| `apt-get upgrade` | Debian-beveiligingsupdates |
| `rm -rf .../npm ...` | npm weg uit het eindimage |

**4. Bouwen met een versie**

```bash
cd ~/Documents/local/docker-k8s-cursus/app/api
podman build -t snip-api:2 --build-arg APP_VERSION=2.0.0 .
```

**5. Zit de versie erin?**

```bash
podman image inspect snip-api:2 --format '{{index .Labels "org.opencontainers.image.version"}}'
podman run --rm snip-api:2 node -p process.env.APP_VERSION
```

Twee keer `2.0.0`: één keer uit de metadata, één keer zoals de app het ziet. Zonder dat je
`-e APP_VERSION` meegaf.

**6. Netjes stoppen?**

```bash
podman run -d --name stop-nieuw snip-api:2
time podman stop stop-nieuw
podman logs stop-nieuw
podman rm stop-nieuw
```

Minder dan een seconde, en in de logs staat `SIGTERM ontvangen, netjes afsluiten...`.

**7. Is npm weg?**

```bash
podman run --rm snip-api:2 npm --version
```

Je krijgt een lange foutmelding die eindigt op `Cannot find module '/app/npm'`. Dat is goed
nieuws, al ziet het er niet zo uit. Het Node-image start elk commando via een opstartscript.
Bestaat het eerste woord als programma, dan voert het script dat uit. Zo niet, dan neemt het
aan dat je een JavaScript-bestand bedoelt en doet het `node npm --version`. npm bestaat niet
meer, dus zoekt Node een bestand `/app/npm`.

Netter controleren:

```bash
podman run --rm snip-api:2 sh -c 'command -v npm || echo "npm is weg"'
```

`npm is weg`. Precies de bedoeling.

### Deel C — Scannen

**8. Images exporteren**

Trivy draaien we zelf ook in een container. Daarom geven we het image als bestand mee:

```bash
podman save -o ~/snip-api-1.tar snip-api:1
podman save -o ~/snip-api-2.tar snip-api:2
```

**9. Het oude image scannen**

```bash
podman run --rm -v ~/snip-api-1.tar:/image.tar:ro -v trivy-cache:/root/.cache \
  docker.io/aquasec/trivy:0.76.0 \
  image --input /image.tar --severity HIGH,CRITICAL --ignore-unfixed
```

De eerste keer downloadt Trivy zijn database van bekende lekken (in het volume `trivy-cache`, zodat
het de volgende keer sneller gaat). Kijk naar de twee tabellen:

- **debian**: lekken in `perl-base`, een onderdeel van het Debian-basis-image;
- **Node.js**: lekken in pakketten zoals `brace-expansion` en `undici`. Die horen bij **npm**,
  niet bij snip.

Geen enkele melding komt uit je eigen code.

> Let op de versie: `aquasec/trivy:0.76.0`. Tijdens het incident van maart 2026 zijn ook
> kwaadaardige Trivy-images gepubliceerd (0.69.4 t/m 0.69.6). Een vaste, gecontroleerde versie
> is dus geen detail.

**10. Het nieuwe image scannen**

```bash
podman run --rm -v ~/snip-api-2.tar:/image.tar:ro -v trivy-cache:/root/.cache \
  docker.io/aquasec/trivy:0.76.0 \
  image --input /image.tar --severity HIGH,CRITICAL --ignore-unfixed
```

Twee lege tabellen: geen oplosbare HIGH- of CRITICAL-lekken meer. Ruim de bestanden op:

```bash
rm ~/snip-api-1.tar ~/snip-api-2.tar
```

> Het resultaat verandert in de tijd. Er worden elke week nieuwe lekken gevonden. Een image dat
> vandaag schoon is, kan volgende maand meldingen hebben, zonder dat jij iets veranderde. Daarom
> scant de pipeline bij **elke** build.

### Deel D — Architecturen

**11. Wat is je image?**

```bash
podman image inspect snip-api:2 --format '{{.Os}}/{{.Architecture}}'
```

`linux/arm64`: gebouwd op en voor je Mac.

**12. Een andere architectuur draaien**

```bash
podman run --rm --platform linux/amd64 node:24-slim node -p process.arch
```

`x64`: dit draaide als Intel/AMD, via emulatie. Het werkt, maar is merkbaar trager. Op een
server wil je de echte variant, en daarom bouwt de pipeline zo meteen beide.

### Deel E — Naar GitHub

**13. Een git-repo maken**

In de hoofdmap van de cursus staat al een [`.gitignore`](../../.gitignore) die `node_modules`,
`.env` en `.tar`-bestanden buiten Git houdt.

```bash
cd ~/Documents/local/docker-k8s-cursus
git init -b main
git add .
git status
```

**Controleer in de lijst dat `app/.env` er niet tussen staat.** Dan pas:

```bash
git commit -m "Docker & Kubernetes-cursus: modules 00-05"
```

**14. Op GitHub zetten**

```bash
gh repo create docker-k8s-cursus --public --source . --push
```

We maken hem **publiek**. Dan zijn GitHub Actions-minuten onbeperkt, kan iedereen je image ophalen
zonder in te loggen, en kunnen we later (deel 5) de beveiligingsregels gebruiken die anders
alleen in betaalde plannen zitten. Er staan geen geheimen in de repo: `.env` blijft lokaal.

**15. De workflow**

Maak in de **hoofdmap** van de repo de map `.github/workflows/`, en daarin het bestand
`snip-api.yml`:

```yaml
name: snip-api

on:
  push:
    branches: [main]
    paths: ["app/api/**", ".github/workflows/snip-api.yml"]
  pull_request:
    paths: ["app/api/**", ".github/workflows/snip-api.yml"]
  workflow_dispatch: # handmatig starten vanuit het Actions-tabblad

permissions:
  contents: read
  packages: write # nodig om naar GHCR te pushen

jobs:
  build:
    runs-on: ubuntu-24.04
    steps:
      # Alle actions zijn vastgepind op een commit-SHA, niet op een tag. Tags kunnen worden
      # verplaatst (zie het Trivy-incident van maart 2026), een SHA niet.
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1

      - name: Naam en versie bepalen
        run: |
          # GHCR accepteert alleen kleine letters in image-namen.
          echo "IMAGE=ghcr.io/${GITHUB_REPOSITORY_OWNER,,}/snip-api" >> "$GITHUB_ENV"
          echo "VERSION=sha-${GITHUB_SHA::7}" >> "$GITHUB_ENV"

      - name: Tags en labels bepalen
        id: meta
        uses: docker/metadata-action@dc802804100637a589fabce1cb79ff13a1411302 # v6.2.0
        with:
          images: ${{ env.IMAGE }}
          tags: |
            type=sha,format=short
            type=raw,value=latest,enable={{is_default_branch}}

      - uses: docker/setup-qemu-action@99012661954931238ded8c8b007157a8430204e1 # v4.4.0
      - uses: docker/setup-buildx-action@f87e5991a6d7451dcb8d9637bfbc97413f497069 # v4.4.1

      - name: Bouwen om te scannen (alleen amd64, blijft op de runner)
        uses: docker/build-push-action@c3c9e263c25d99ce0380d002d59b67737d91b0dc # v7.4.0
        with:
          context: app/api
          load: true
          tags: snip-api:scan
          build-args: APP_VERSION=${{ env.VERSION }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

      - name: Scannen op kwetsbaarheden
        uses: aquasecurity/trivy-action@ed142fd0673e97e23eac54620cfb913e5ce36c25 # v0.36.0
        with:
          image-ref: snip-api:scan
          version: v0.76.0
          severity: CRITICAL,HIGH
          ignore-unfixed: true
          exit-code: "1" # pipeline faalt bij een oplosbare HIGH of CRITICAL

      - name: Inloggen bij GHCR
        if: github.event_name != 'pull_request'
        uses: docker/login-action@dbcb813823bdd20940b903addbd779551569679f # v4.6.0
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Bouwen en pushen (amd64 + arm64)
        uses: docker/build-push-action@c3c9e263c25d99ce0380d002d59b67737d91b0dc # v7.4.0
        with:
          context: app/api
          platforms: linux/amd64,linux/arm64
          push: ${{ github.event_name != 'pull_request' }}
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          build-args: APP_VERSION=${{ env.VERSION }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

De belangrijkste onderdelen:

| Onderdeel | Wat |
|---|---|
| `on: push` + `paths` | alleen draaien als er iets in `app/api/` of in de workflow zelf verandert |
| `on: pull_request` | ook bij een pull request, maar dan **zonder te pushen** (zie de `if:` en `push:`) |
| `permissions` | het `GITHUB_TOKEN` mag alleen lezen en packages schrijven, niets meer |
| `${GITHUB_REPOSITORY_OWNER,,}` | je GitHub-naam in kleine letters (`,,` is bash voor "kleine letters") |
| `VERSION=sha-...` | de versie is het begin van de commit-hash: dan weet je altijd welke code erin zit |
| `metadata-action` | maakt de tags `sha-abc1234` en (op `main`) `latest`, plus standaardlabels |
| `cache-from/to: gha` | layers bewaren tussen runs, dus de tweede build is veel sneller |
| twee keer `build-push-action` | eerst één architectuur om te scannen, dan pas beide om te publiceren |

**16. Pushen en kijken**

```bash
git add .github
git commit -m "CI voor snip-api"
git push
gh run watch
```

`gh run watch` laat de stappen live zien. Je kunt ook op GitHub kijken, in het tabblad
**Actions** van je repo. De eerste run duurt een paar minuten, vooral door de arm64-variant
onder emulatie.

**17. Je image op GHCR**

Op GitHub staat nu onder **Packages** (op je profiel, of rechts op de repo-pagina) het package
`snip-api`. Haal het op je Mac op:

```bash
eigenaar=$(gh api user --jq .login | tr 'A-Z' 'a-z')
podman pull ghcr.io/$eigenaar/snip-api:latest
podman image inspect ghcr.io/$eigenaar/snip-api:latest --format '{{.Architecture}}'
podman run --rm ghcr.io/$eigenaar/snip-api:latest node -p process.env.APP_VERSION
```

Podman koos automatisch de `arm64`-variant, en de versie is `sha-` met het begin van je
commit-hash. Bekijk beide varianten:

```bash
podman manifest inspect ghcr.io/$eigenaar/snip-api:latest | grep architecture
```

> Krijg je bij `pull` een fout als `unauthorized` of `denied`? Dan staat het package op
> privé. Ga op GitHub naar het package → **Package settings** → **Change visibility** →
> **Public**.

---

## Breek het

### 💥 1. Een pull request dat de scan niet haalt

Een collega vindt de npm-regel onnodig en haalt hem weg. Speel dat na in een **pull request**:

```bash
cd ~/Documents/local/docker-k8s-cursus
git switch -c weg-met-npm-regel
sed -i '' -e '/npm cache clean --force \\$/s| \\$||' -e '/rm -rf \/usr\/local\/lib\/node_modules\/npm/d' app/api/Dockerfile
git diff
git commit -am "npm-opruimregel weg"
git push -u origin weg-met-npm-regel
gh pr create --fill
gh pr checks --watch
```

<details>
<summary>Uitleg</summary>

De check wordt rood bij **Scannen op kwetsbaarheden**. Bekijk de details op de PR-pagina: de
npm-lekken uit stap 9 zijn terug. Er is niets gepusht naar GHCR, want bij een pull request
bouwt de workflow alleen.

Dit is waarom je de scan in een pull request wilt: het probleem wordt gevonden **voordat** het
op `main` staat. In deel 5 stel je in dat een PR met een rode check niet gemerged kán worden.

Ruim op:

```bash
gh pr close --delete-branch
git switch main
git branch -D weg-met-npm-regel
```

> Gaf de scan in jouw PR toch groen? Dan zijn de npm-lekken inmiddels opgelost in een nieuwere
> Node-versie. Zo snel kan het veranderen.
</details>

### 💥 2. Wat als je geen kleine letters gebruikt?

Stel, er stond `echo "IMAGE=ghcr.io/${GITHUB_REPOSITORY_OWNER}/snip-api"` (zonder `,,`).

<details>
<summary>Uitleg</summary>

Je GitHub-naam bevat een hoofdletter. Dan zou de laatste stap falen met een fout als
`repository name must be lowercase`. Image-namen mogen alleen kleine letters bevatten, GitHub-namen
wel hoofdletters. Daar struikelen veel mensen over bij hun eerste pipeline.
</details>

### 💥 3. Wat als je een tag had gebruikt?

Stel, er stond `uses: aquasecurity/trivy-action@0.33.1`, en het was 19 maart 2026.

<details>
<summary>Uitleg</summary>

Je pipeline had de code gedraaid die de aanvallers achter die tag hadden gezet. Die zocht het
`GITHUB_TOKEN` en andere secrets bij elkaar, stuurde ze weg, en draaide daarna gewoon de echte
scan. Je pipeline was groen geweest en je had niets gemerkt.

Met een SHA had je nog steeds de oude, goede code gedraaid. Vastpinnen op SHA kost je wat
gemak bij het updaten. Tools als Dependabot of Renovate houden de SHA's voor je bij en
maken een pull request bij een nieuwe versie.
</details>

---

## Op je werk

- **De centrale workflow doet dit voor je.** Bij jullie staat dit hele blok waarschijnlijk in
  een *reusable workflow* van het platformteam. Jouw repo roept die aan met een paar regels, iets
  als:

  ```yaml
  jobs:
    build:
      uses: mijnbedrijf/platform-workflows/.github/workflows/container-build.yml@v3
      with:
        context: app/api
  ```

  Nu je weet wat erin zit, kun je een rode pipeline zelf lezen. In module 22 bouw je zo'n
  centrale workflow zelf.
- **ACR in plaats van GHCR, en OIDC in plaats van een token.** Bedrijven pushen meestal naar Azure
  Container Registry. Inloggen gaat dan via OIDC: GitHub bewijst aan Azure wie hij is, zonder
  opgeslagen wachtwoord (module 20).
- **Basis-images van het platformteam** zijn vaak al gepatcht. De `apt-get upgrade`-regel is dan
  niet nodig, en soms zelfs niet toegestaan. Kwetsbaarheden worden vaak ook centraal bijgehouden,
  bijvoorbeeld in Microsoft Defender for Cloud.
- **SHA-pinning wordt steeds vaker afgedwongen.** Een GitHub-organisatie kan instellen dat
  actions alleen met een volledige commit-SHA gebruikt mogen worden.
- **Ondertekenen en een SBOM.** Grotere organisaties ondertekenen hun images (bijv. met cosign)
  en publiceren een lijst van alles wat erin zit (een *SBOM*). Het cluster accepteert dan
  alleen ondertekende images.

---

## Checkpoint

<details>
<summary>1. Waarom duurde <code>podman stop</code> op de oude API 10 seconden?</summary>

Node draaide als PID 1 zonder eigen reactie op SIGTERM, en negeerde het signaal dus. Podman
wachtte 10 seconden en stuurde toen SIGKILL.
</details>

<details>
<summary>2. Wat is het verschil tussen <code>ARG</code> en <code>ENV</code>?</summary>

`ARG` bestaat alleen tijdens het bouwen. `ENV` zit in het image en is er ook als de container
draait. Met `ENV APP_VERSION=$APP_VERSION` maak je van een build-argument een vaste waarde in
het image.
</details>

<details>
<summary>3. Waar kwamen de kwetsbaarheden in het oude image vandaan, en hoe los je ze op?</summary>

Uit het basis-image: Debian-pakketten (`perl-base`) en de npm die met Node meekomt. Door npm uit
het eindimage te halen, de Debian-updates te installeren, en de rest pas te laten tellen als er
een oplossing is (`--ignore-unfixed`).
</details>

<details>
<summary>4. Waarom bouwt de pipeline voor twee architecturen?</summary>

Servers en AKS zijn meestal `amd64`, ARM-servers en je Mac `arm64`. Een multi-arch image heeft
een variant voor elk, en de juiste wordt automatisch gekozen.
</details>

<details>
<summary>5. Waarom pin je actions op een commit-SHA?</summary>

Een tag kan naar andere code verplaatst worden, een SHA niet. Bij het Trivy-incident van maart
2026 draaiden pipelines met tags ongemerkt kwaadaardige code.
</details>

<details>
<summary>6. Wat doet de workflow anders bij een pull request?</summary>

Hij bouwt en scant, maar pusht niet naar GHCR. Een PR is een voorstel, en alleen wat op `main`
staat, wordt gepubliceerd.
</details>

### Eindopdracht

Als je het lab hebt gedaan, heb je alles al. Controleer:

1. lokaal een image **`snip-api:2`** met versie `2.0.0`, dat netjes stopt en geen npm bevat;
2. de cursus als **publieke repo** op GitHub, met de workflow `snip-api.yml`;
3. een **geslaagde run** van die workflow op `main`;
4. een **multi-arch image** `ghcr.io/<jij>/snip-api:latest` (amd64 + arm64) dat je zonder
   inloggen kunt ophalen.

```bash
cd ~/Documents/local/docker-k8s-cursus/modules/05-productierijp-en-ci
./check.sh
```

Groen? Dan kun je containers bouwen, draaien, verbinden en automatisch laten publiceren. In
**module 06** zet je snip voor het eerst echt online, op je eigen server.

---

## Spiekbrief

| Commando | Wat het doet |
|---|---|
| `podman build --build-arg KEY=waarde ...` | waarde meegeven aan een `ARG` |
| `podman image inspect IMG --format '{{.Labels}}'` | labels van een image |
| `podman save -o bestand.tar IMG` | image als bestand exporteren |
| `podman run --platform linux/amd64 ...` | andere architectuur draaien (emulatie) |
| `podman manifest inspect IMG` | varianten van een multi-arch image |
| `time podman stop NAAM` | hoe lang duurt stoppen? |
| `gh repo create NAAM --public --source . --push` | huidige map als nieuwe GitHub-repo |
| `gh run watch` | lopende workflow live volgen |
| `gh run list` | eerdere runs |
| `gh pr create --fill` | pull request maken van je branch |
| `gh pr checks --watch` | checks van je PR volgen |

| Dockerfile | |
|---|---|
| `ARG NAAM=standaard` | build-argument |
| `ENV NAAM=$NAAM` | vastleggen in het image |
| `LABEL sleutel=waarde` | metadata |
| `FROM --platform=$BUILDPLATFORM ...` | deze fase draait op de architectuur van de bouwer |
