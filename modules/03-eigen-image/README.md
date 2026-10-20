# Module 03 — Je eerste eigen image

**Doel:** je verpakt de `snip`-API in een eigen image met een Dockerfile. Dat image is klein, snel
te herbouwen en draait niet als root. Daarna laat je de API praten met `snip-db` uit module 02.

**Tijd:** ±1,5–2 uur

**Nodig:** module 02 afgerond

> De app-code staat klaar in [`app/api/`](../../app/api/). Je hoeft er niets aan te veranderen of
> te begrijpen. Jij schrijft alleen de **Dockerfile** en de **.dockerignore**: die blokken kun je
> overnemen uit deze README. De uitwerking staat in [`uitwerking/`](uitwerking/).

---

## Uitleg

### Een Dockerfile is een recept

Tot nu toe gebruikte je images van anderen. Een eigen image bouw je met een **Dockerfile**: een
lijstje instructies, van boven naar beneden uitgevoerd.

| Instructie | Wat het doet | Vergelijk met |
|---|---|---|
| `FROM node:24-slim` | begin met een bestaand image als basis | `extends` |
| `WORKDIR /app` | ga in deze map staan (en maak hem aan) | `cd` |
| `COPY bron doel` | kopieer bestanden van je Mac naar het image | `cp` |
| `RUN npm ci` | voer een commando uit **tijdens het bouwen** | een stap in je build-script |
| `ENV NODE_ENV=production` | zet een environment variable | `export` |
| `USER node` | draai vanaf hier als deze gebruiker | |
| `EXPOSE 3000` | documentatie: "deze app luistert op 3000" (publiceert niets!) | een comment |
| `CMD ["node", "dist/index.js"]` | het commando dat start **als de container draait** | `npm start` |

Let op het verschil tussen `RUN` en `CMD`: `RUN` gebeurt één keer, bij het bouwen. `CMD` gebeurt
elke keer dat er een container start.

### Layers en de cache

Elke `COPY` en `RUN` maakt een nieuwe **layer**: een laag met de bestanden die die stap
veranderde. Podman onthoudt elke laag. Bouw je opnieuw en is er voor een stap niets veranderd,
dan gebruikt hij de laag uit de cache (`Using cache`) en slaat hij de stap over.

Maar: zodra één stap **wel** verandert, moeten alle stappen **daarna** opnieuw.

```
  slechte volgorde                       goede volgorde
  ────────────────                       ──────────────
  COPY . .          ← verandert altijd   COPY package*.json ./   ← verandert zelden
  RUN npm install   ← dus altijd opnieuw RUN npm ci              ← dus meestal uit cache
  RUN npm run build                      COPY src ./src          ← verandert vaak
                                         RUN npm run build       ← alleen dit opnieuw
```

Vuistregel: **wat zelden verandert bovenaan, wat vaak verandert onderaan.**

### De build context en .dockerignore

Bij `podman build .` stuurt Podman eerst de hele map (de *build context*) naar de bouwer.
Zonder afspraken gaat daar ook `node_modules` van je Mac mee: duizenden bestanden, gebouwd voor
macOS, terwijl het image Linux is. Een `.dockerignore` werkt als een `.gitignore` voor die context.

### Multi-stage: bouwen en draaien gescheiden

Om TypeScript om te zetten heb je de TypeScript-compiler en alle dev-dependencies nodig. Om de app
te **draaien** niet. Met twee `FROM`'s in één Dockerfile maak je twee fases:

```
  fase "build" (wordt weggegooid)          fase 2 (dit wordt je image)
 ┌───────────────────────────────┐        ┌─────────────────────────────────┐
 │ node:24-slim                  │        │ node:24-slim                    │
 │ + alle dependencies (ook dev) │        │ + alleen productie-dependencies │
 │ + broncode (src/)             │  dist  │ + dist/   ◄── gekopieerd        │
 │ + tsc → dist/          ───────┼───────►│ USER node                       │
 └───────────────────────────────┘        └─────────────────────────────────┘
```

Het eindresultaat bevat geen broncode, geen compiler en geen dev-tools. Het image is kleiner, er
zit minder in dat kwetsbaar kan zijn, en het is sneller te downloaden.

### Configuratie via environment variables

Het image is overal hetzelfde: op je Mac, in de pipeline en straks in Kubernetes. Wat verschilt
per omgeving, geef je mee bij het **starten**, met `-e`. De API leest:

| Variabele | Standaard | Wat |
|---|---|---|
| `DATABASE_URL` | — | waar de database is, bijv. `postgres://postgres:geheim@snip-db:5432/snip` |
| `PORT` | `3000` | op welke poort de API luistert |
| `HOST` | `0.0.0.0` | op welk netwerkadres hij luistert (zie breek-het 2) |
| `APP_VERSION` | `dev` | versienummer, te zien op `/api/info` |

---

## Lab

### Deel A — De app, eerst zonder container

**1. Rondkijken**

```bash
cd ~/Documents/local/docker-k8s-cursus/app/api
ls
```

| Bestand | Wat |
|---|---|
| `src/index.ts` | de API (TypeScript) |
| `package.json`, `package-lock.json` | dependencies en scripts |
| `tsconfig.json` | instellingen voor de TypeScript-compiler |

De API heeft deze adressen:

| Adres | Wat |
|---|---|
| `GET /health` | leeft de app? |
| `GET /health/db` | kan de app bij de database? |
| `GET /api/info` | versie en naam van de container |
| `GET /api/links` | alle korte links |
| `POST /api/links` | nieuwe korte link maken |
| `GET /<code>` | doorsturen, bijv. `/gh` → github.com |

**2. Lokaal draaien**

```bash
npm install
npm run dev
```

Open <http://localhost:3000/health>: `{"status":"ok"}`. Open daarna
<http://localhost:3000/health/db>: `onbereikbaar`. Logisch: je database draait in een container
zonder `-p`, dus je Mac kan er niet bij. Stop de app met `Ctrl+C`.

Dit werkt omdat je toevallig Node 24 op je Mac hebt. Een collega met Node 20, of een server
zonder Node, heeft daar niets aan. Daarom gaan we het verpakken.

### Deel B — Dockerfile v1: zo simpel mogelijk

**3. De eerste Dockerfile**

Maak in `app/api/` een bestand `Dockerfile` (zonder extensie) met deze inhoud:

```dockerfile
FROM node:24
WORKDIR /app
COPY . .
RUN npm install
RUN npm run build
CMD ["npm", "start"]
```

In gewone taal: begin met Node 24, kopieer alles, installeer, bouw, en start met `npm start`.

**4. Bouwen**

```bash
podman build -t snip-api:v1 .
```

- `-t snip-api:v1` geeft het image een naam (`snip-api`) en een tag (`v1`)
- `.` is de build context: deze map

Lees de output: `STEP 1/6`, `STEP 2/6`, … Elke instructie uit je Dockerfile is één stap.

**5. Hoe groot?**

```bash
podman images snip-api
```

Ruim **1,2 GB**, voor een API van 100 regels. Het volledige `node:24`-image zit erin, plus
alle dev-dependencies, plus je broncode.

**6. Wat zit erin?**

```bash
podman image history snip-api:v1
```

Kijk naar de regel met `COPY dir:...`: tientallen MB's. Dat is je `node_modules` van je Mac,
die meekwam met `COPY . .`.

**7. Hoe snel is herbouwen?**

Doe alsof je de code hebt aangepast, en bouw opnieuw:

```bash
touch src/index.ts
time podman build -t snip-api:v1 .
```

Kijk naar de stappen: na `COPY . .` staat nergens meer `Using cache`. Omdat er één bestand
veranderde, draait `npm install` helemaal opnieuw. Bij elke codewijziging.

### Deel C — Dockerfile v2: klein, snel en veilig

**8. Een .dockerignore**

Maak in `app/api/` een bestand `.dockerignore`:

```
node_modules
dist
.git
*.log
```

**9. De nieuwe Dockerfile**

Vervang de inhoud van je `Dockerfile` door:

```dockerfile
# ---- fase 1: bouwen ----------------------------------------------------------
FROM node:24-slim AS build
WORKDIR /app

# Eerst alleen de package-bestanden: deze laag blijft in de cache zolang je dependencies niet veranderen.
COPY package.json package-lock.json ./
RUN npm ci

# Dan de broncode, en TypeScript omzetten naar JavaScript.
COPY tsconfig.json ./
COPY src ./src
RUN npm run build

# ---- fase 2: draaien ---------------------------------------------------------
FROM node:24-slim
WORKDIR /app
ENV NODE_ENV=production

# Alleen de dependencies die nodig zijn om te draaien (geen TypeScript e.d.).
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

# Alleen het resultaat uit fase 1, geen broncode.
COPY --from=build /app/dist ./dist

# Niet als root draaien.
USER node

EXPOSE 3000
CMD ["node", "dist/index.js"]
```

Wat er anders is dan v1:

| | v1 | v2 |
|---|---|---|
| Basis | `node:24` (volledige Debian) | `node:24-slim` |
| Volgorde | alles in één keer | eerst package-bestanden, dan code (cache!) |
| Installeren | `npm install` | `npm ci`: installeert exact wat in `package-lock.json` staat |
| Fases | één | twee: bouwen en draaien gescheiden |
| Gebruiker | root | `node` (bestaat al in het Node-image) |
| Starten | `npm start` | direct `node` (één proces minder) |

**10. Bouwen**

```bash
podman build -t snip-api:1 .
```

Je ziet nu `[1/2] STEP ...` voor de bouwfase en `[2/2] STEP ...` voor het eindimage.

**11. Vergelijken**

```bash
podman images snip-api
```

Van ruim 1,2 GB naar ongeveer **260 MB**. Het grootste deel daarvan is Node zelf.

**12. De cache aan het werk**

```bash
touch src/index.ts
time podman build -t snip-api:1 .
```

Nu staat er bij `npm ci` wel `Using cache`. Alleen het kopiëren van de code en het bouwen worden
opnieuw gedaan. Vergelijk de tijd met stap 7.

**13. Wat zit er in het eindimage?**

```bash
podman run --rm snip-api:1 ls /app
podman run --rm snip-api:1 whoami
```

Geen `src/`, geen `tsconfig.json`, en de gebruiker is `node`, niet `root`. Je hebt hier trouwens
weer een commando achter de image-naam gezet (`ls /app`), dat het `CMD` vervangt. Net als in
module 01.

### Deel D — De API naast de database

**14. Draaien snip-net en snip-db nog?**

```bash
podman ps --filter name=snip-db
```

Staat hij er niet, maak hem dan opnieuw zoals in module 02. Het volume `snip-data` bestaat nog,
dus je data komt gewoon terug:

```bash
podman network exists snip-net || podman network create snip-net
podman run -d --name snip-db --network snip-net \
  -v snip-data:/var/lib/postgresql \
  -e POSTGRES_PASSWORD=geheim \
  -e POSTGRES_DB=snip \
  postgres:18-alpine
```

**15. De API starten**

```bash
podman run -d --name snip-api --network snip-net -p 3000:3000 \
  -e DATABASE_URL=postgres://postgres:geheim@snip-db:5432/snip \
  -e APP_VERSION=1 \
  snip-api:1
```

Herken je alles? Een eigen netwerk, zodat de API `snip-db` op naam vindt (module 02). Een poort
naar buiten, alleen voor de API. Configuratie via `-e`.

```bash
podman logs snip-api
```

`snip-api 1 luistert op http://0.0.0.0:3000`

**16. Proberen**

```bash
curl localhost:3000/health/db
curl localhost:3000/api/links
curl localhost:3000/api/info
```

Zie je links uit module 02? Die komen uit het volume `snip-data`. De API is nieuw, de data
niet.

Maak een nieuwe korte link:

```bash
curl -X POST localhost:3000/api/links \
  -H 'content-type: application/json' \
  -d '{"url": "https://kubernetes.io/docs/home/", "code": "docs"}'
```

Open nu <http://localhost:3000/docs> in je browser. Je wordt doorgestuurd naar de
Kubernetes-docs. Je URL-shortener werkt.

**17. Het geheel**

```
  browser
     │ localhost:3000
┌────▼─────────────── snip-net ──────────────────────────┐
│  snip-api ──── "snip-db:5432" ───► snip-db            │
│  (jouw image)                        └─ volume snip-data │
│                                    ▲                    │
│  snip-adminer ─────────────────────┘                    │
└─────────────────────────────────────────────────────────┘
```

Draait Adminer uit module 02 nog? Ververs dan <http://localhost:8081>, en je ziet je link `docs`
in de tabel.

---

## Breek het

### 💥 1. "Maar het werkt toch op localhost?"

```bash
podman run -d --name api-localhost --network snip-net -p 3001:3000 \
  -e DATABASE_URL=postgres://postgres:geheim@localhost:5432/snip \
  snip-api:1
curl localhost:3001/health/db
```

<details>
<summary>Hint</summary>

Vanuit wiens perspectief is `localhost` hier bedoeld? En vanuit wiens perspectief wordt het
gelezen?
</details>

<details>
<summary>Uitleg en oplossing</summary>

`connect ECONNREFUSED ::1:5432; connect ECONNREFUSED 127.0.0.1:5432`

In een container betekent `localhost` **de container zelf**, niet je Mac en niet een andere
container. In de API-container draait geen Postgres, dus niemand neemt op.

Dit is waarschijnlijk de meest gemaakte fout met containers. Op je Mac werkt `localhost`
prima in je `.env`, en in een container ineens niet meer. Gebruik de naam van de container
(`snip-db`) of, in Kubernetes, de naam van de Service.

```bash
podman rm -f api-localhost
```
</details>

### 💥 2. De app draait, maar is onbereikbaar

```bash
podman run -d --name api-host --network snip-net -p 3002:3000 \
  -e HOST=127.0.0.1 \
  -e DATABASE_URL=postgres://postgres:geheim@snip-db:5432/snip \
  snip-api:1
curl localhost:3002/health
podman logs api-host
```

<details>
<summary>Hint</summary>

De logs zeggen dat hij luistert. Maar op welk adres? En waar komt het verkeer van `-p` binnen?
</details>

<details>
<summary>Uitleg en oplossing</summary>

`Connection reset by peer`. De app luistert op `127.0.0.1`: alleen verkeer van **binnen de
container zelf** komt daar aan. Verkeer via `-p` komt binnen op het netwerkadres van de container,
en daar luistert niemand.

In een container moet een app luisteren op **`0.0.0.0`** (alle adressen). Veel dev-servers luisteren
standaard alleen op `localhost`. Vite bijvoorbeeld heeft daarvoor `--host`. Zie je in een
container `Connection reset` terwijl de logs zeggen dat alles draait, denk dan hieraan.

```bash
podman rm -f api-host
```
</details>

### 💥 3. Een oud image draaien

Bouw een nieuwe versie, maar vergeet de container te vervangen:

```bash
podman build -t snip-api:2 .
curl localhost:3000/api/info
```

<details>
<summary>Uitleg en oplossing</summary>

Er staat nog steeds `"versie":"1"`, en dat blijft zo. Een container is gemaakt van een image op het
moment van `podman run`. Een nieuw image bouwen verandert **bestaande containers niet**.

Updaten is altijd: oude container weg, nieuwe starten met het nieuwe image.

```bash
podman rm -f snip-api
podman run -d --name snip-api --network snip-net -p 3000:3000 \
  -e DATABASE_URL=postgres://postgres:geheim@snip-db:5432/snip \
  -e APP_VERSION=2 \
  snip-api:2
curl localhost:3000/api/info
```

Precies dit gaat Kubernetes later voor je automatiseren met een *rolling update*: nieuwe
containers starten, en pas als die werken de oude weggooien.

(`APP_VERSION` geven we nog met de hand mee. In module 05 zet de pipeline het versienummer
automatisch in het image.)
</details>

---

## Op je werk

- **Jouw Dockerfile, hun pipeline.** De Dockerfile hoort bij je app en is van jou. Het bouwen
  gebeurt in de centrale pipeline (deel 5). Die verwacht vaak een Dockerfile op een vaste plek in
  je repo, en voegt zelf tags, scans en labels toe. Productie-images bouw je niet op je laptop.
- **Goedgekeurde basis-images.** In plaats van `FROM node:24-slim` staat er vaak iets als
  `FROM mijnbedrijf.azurecr.io/base/node:24`. Het platformteam houdt die images bij en installeert
  de beveiligingsupdates.
- **Scannen.** Images worden gescand op bekende kwetsbaarheden, bijvoorbeeld met Trivy of
  Microsoft Defender. Hoe minder er in je image zit (slim, multi-stage), hoe minder meldingen.
- **Non-root wordt afgedwongen.** Veel clusters weigeren containers die als root draaien (module
  24). Met `USER node` zit je goed.
- **Nooit `:latest` in productie.** De pipeline tagt images met een versie of de git-commit, zodat
  je altijd weet wat er draait en terug kunt naar een vorige versie.
- **`localhost` in een `.env`-bestand** is op je werk net zo goed een valkuil. In Kubernetes is het
  adres de naam van een Service, of de hostnaam van een managed database.

---

## Checkpoint

<details>
<summary>1. Waarom kopieer je <code>package.json</code> en <code>package-lock.json</code> vóór de broncode?</summary>

Zodat de laag met `npm ci` in de cache blijft zolang je dependencies niet veranderen. Een
codewijziging maakt dan alleen de stappen daarna ongeldig.
</details>

<details>
<summary>2. Waarom twee <code>FROM</code>'s in één Dockerfile?</summary>

Multi-stage: de eerste fase bouwt (met compiler en dev-dependencies) en wordt weggegooid. De
tweede fase krijgt alleen het resultaat (`dist/`) en de productie-dependencies. Dat geeft een
kleiner en veiliger image.
</details>

<details>
<summary>3. Wat doet <code>.dockerignore</code>?</summary>

Het houdt bestanden buiten de build context, zoals `node_modules` van je Mac, `dist` en `.git`.
Dat maakt bouwen sneller, en zo komen die bestanden niet per ongeluk in je image.
</details>

<details>
<summary>4. Waarom werkt <code>DATABASE_URL=...@localhost:5432/...</code> niet in een container?</summary>

`localhost` is in een container de container zelf. De database draait in een andere container,
die je bereikt via zijn naam op het netwerk.
</details>

<details>
<summary>5. Waarom moet een app in een container op <code>0.0.0.0</code> luisteren?</summary>

Verkeer via `-p` komt binnen op het netwerkadres van de container, niet op `127.0.0.1`. Op
`0.0.0.0` luistert de app op alle adressen.
</details>

<details>
<summary>6. Je bouwt een nieuw image. Waarom ziet je draaiende container dat niet?</summary>

Een container wordt gemaakt van een image op het moment van `podman run`. Om te updaten gooi je
de container weg en start je een nieuwe.
</details>

### Eindopdracht

Ruim de API-containers en oude images uit deze module op, op naam:

```bash
podman rm -f snip-api api-localhost api-host
podman rmi snip-api:v1 snip-api:2
```

Doe daarna **zonder in het lab te kijken**:

1. Bouw vanuit `app/api` het image **`snip-api:1`**, met jouw multi-stage Dockerfile en
   `.dockerignore`.
2. Start een container **`snip-api`** van dat image: op `snip-net`, bereikbaar op
   <http://localhost:3000>, verbonden met `snip-db`, met `APP_VERSION=1`.
3. Maak via de API een korte link met code **`k3s`** naar `https://k3s.io`. Het `curl`-commando
   uit stap 16 mag je overnemen.

Controleer:

```bash
cd ~/Documents/local/docker-k8s-cursus/modules/03-eigen-image
./check.sh
```

Groen? In **module 04** zet je alles wat je nu met losse commando's start (netwerk, volume,
database, API) in één Compose-bestand. Daarna start je de hele app met één commando.

---

## Spiekbrief

| Commando | Wat het doet |
|---|---|
| `podman build -t NAAM:TAG .` | image bouwen uit de Dockerfile in deze map |
| `podman build -f PAD -t NAAM:TAG .` | een Dockerfile van een andere plek gebruiken |
| `podman images NAAM` | images met die naam, en hun grootte |
| `podman image history NAAM:TAG` | layers en hun grootte |
| `podman image inspect NAAM:TAG` | details: user, CMD, env, ... |
| `podman rmi NAAM:TAG` | image verwijderen |
| `podman image prune` | ⚠️ alle images zonder naam verwijderen (overblijfsels van builds) |

| Dockerfile | |
|---|---|
| `FROM image AS naam` | basis, en optioneel een naam voor deze fase |
| `WORKDIR /pad` | werkmap |
| `COPY bron doel` | bestanden van de build context naar het image |
| `COPY --from=fase bron doel` | bestanden uit een eerdere fase |
| `RUN commando` | uitvoeren tijdens het bouwen |
| `ENV KEY=waarde` | environment variable |
| `USER naam` | draai als deze gebruiker |
| `EXPOSE poort` | documenteert de poort (publiceert niets) |
| `CMD ["prog", "arg"]` | startcommando van de container |
