# Module 04 — Compose: de hele app met één commando

**Doel:** je beschrijft de hele snip-app (database, API en website) in één bestand,
`compose.yaml`. Je start en stopt alles met één commando, en je weet welke `podman run`-opties
waar in dat bestand terechtkomen.

**Tijd:** ±1,5 uur

**Nodig:** module 03 afgerond (er staat een `Dockerfile` in `app/api/`)

> Ook hier schrijf je geen app-code. De website, de nginx-configuratie en de seed-data staan
> klaar in [`app/`](../../app/). Jij bouwt `compose.yaml` op, met blokken die je kunt overnemen.
> De uitwerking staat in [`uitwerking/`](uitwerking/).

---

## Uitleg

### Het probleem: lange commando's

Om snip te draaien typte je in module 02 en 03 dit allemaal:

```bash
podman network create snip-net
podman volume create snip-data
podman run -d --name snip-db --network snip-net -v snip-data:/var/lib/postgresql \
  -e POSTGRES_PASSWORD=geheim -e POSTGRES_DB=snip postgres:18-alpine
podman build -t snip-api:1 .
podman run -d --name snip-api --network snip-net -p 3000:3000 \
  -e DATABASE_URL=postgres://postgres:geheim@snip-db:5432/snip snip-api:1
```

Dat is foutgevoelig, moeilijk te delen met een collega en lastig netjes op te ruimen. **Compose**
zet hetzelfde in een bestand:

```yaml
services:
  db:
    image: postgres:18-alpine
    ...
  api:
    build: ./api
    ...
```

`podman compose up -d` maakt dan zelf het netwerk, de volumes, de images en de containers aan,
in de goede volgorde. `podman compose down` ruimt het weer op.

### Van `podman run` naar `compose.yaml`

Alles wat je al kent, heeft een plek in het bestand:

| `podman run`-optie | In `compose.yaml` |
|---|---|
| `--name snip-db` | de naam van de service: `db:` |
| `postgres:18-alpine` | `image: postgres:18-alpine` |
| `podman build ./api` | `build: ./api` |
| `-e KEY=waarde` | `environment:` |
| `-p 8080:80` | `ports: ["8080:80"]` |
| `-v snip-data:/pad` | `volumes: ["db-data:/pad"]` + onderaan `volumes: db-data:` |
| `-v ./map:/pad:ro` | `volumes: ["./map:/pad:ro"]` |
| `--network snip-net` | hoeft niet: Compose maakt zelf één netwerk voor alle services |

En twee dingen die met losse commando's niet kunnen:

- **`depends_on`**: start de API pas als de database echt klaar is.
- **`healthcheck`**: een commando waarmee Podman controleert of een container gezond is.

### De service-naam is het adres

Compose zet alle services op één netwerk, met DNS (net als `snip-net` in module 02). De
**service-naam** is het adres. Vanuit de API is de database dus gewoon `db`:

```
DATABASE_URL=postgres://postgres:...@db:5432/snip
```

### De opbouw van snip

```
  browser
     │ localhost:8080
┌────▼─────────────── netwerk van Compose ───────────────────┐
│  web (nginx)                                               │
│    /          → webpagina uit ./web/site                   │
│    /api/...   → api:3000 ─────┐                            │
│    /<code>    → api:3000 ─────┤                            │
│                         ┌─────▼──────┐        ┌─────────┐  │
│                         │ api (Node) │──db───►│   db    │  │
│                         └────────────┘  :5432 └────┬────┘  │
│                                                    └ volume db-data
└────────────────────────────────────────────────────────────┘
```

Nieuw is dat **alleen `web` een poort heeft**. nginx is de voordeur: het serveert de
webpagina en stuurt `/api` en de korte links door naar de API. De API en de database zijn van buiten
niet bereikbaar. Zo zie je het straks ook in Kubernetes en op je werk: één ingang, de rest intern.

### Wachtwoorden in een `.env`-bestand

Een wachtwoord hoort niet in `compose.yaml`, want dat bestand gaat in Git. Compose leest
automatisch een bestand `.env` in dezelfde map, en vult `${POSTGRES_PASSWORD}` daaruit in:

```
 .env  (niet in Git)              compose.yaml  (wel in Git)
 ───────────────────              ──────────────────────────
 POSTGRES_PASSWORD=geheim  ──►    POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
```

In de repo staat een `.env.example` als voorbeeld, en `.env` zelf staat in `.gitignore`.

---

## Lab

### Deel A — Voorbereiding

**1. Compose installeren**

Podman heeft een *compose provider* nodig: een apart programma dat `compose.yaml` leest. We
gebruiken **podman-compose**, de open-source variant uit het Podman-project:

```bash
brew install podman-compose
```

Homebrew installeert daarbij ook een eigen, tweede `podman`. Je hebt die van Podman Desktop al,
dus verwijder de extra versie weer (podman-compose blijft gewoon werken):

```bash
brew uninstall --ignore-dependencies podman
```

Controleer, in een **nieuwe** terminal:

```bash
podman --version
podman compose version
```

Je wilt zien: `podman version 5.7.1` (je eigen Podman) en `podman-compose version 1.6.0`.

> Toont `podman --version` ooit een andere versie dan Podman Desktop, bijvoorbeeld na een
> `brew upgrade`? Dan heeft Homebrew de extra `podman` teruggezet. Doe dan het
> `uninstall`-commando hierboven nog een keer.

**2. Opruimen**

De losse containers uit module 02 en 03 bezetten poorten die Compose zo nodig heeft:

```bash
podman ps -a
podman rm -f -v snip-db snip-api snip-web snip-adminer api-localhost api-host
```

(Bestaan sommige niet, dan meldt Podman dat; geen probleem.) Het volume `snip-data` mag blijven
staan. Compose maakt zijn eigen volume aan.

**3. Wat staat er klaar?**

```bash
cd ~/Documents/local/docker-k8s-cursus/app
ls -a
```

| Wat | Waarvoor |
|---|---|
| `api/` | de API, met jouw `Dockerfile` uit module 03 |
| `web/site/index.html` | de webpagina |
| `web/nginx.conf` | nginx als voordeur: pagina serveren en `/api` doorsturen |
| `db/links.sql` | voorbeelddata voor de database |
| `.env.example` | voorbeeld van de geheime instellingen |

Staat er geen `Dockerfile` in `api/`? Kopieer dan de uitwerking van module 03:
`cp ../modules/03-eigen-image/uitwerking/{Dockerfile,.dockerignore} api/`

**4. Het `.env`-bestand**

```bash
cp .env.example .env
cat .env
```

### Deel B — compose.yaml opbouwen

**5. Eerst alleen de database**

Maak in `app/` een bestand `compose.yaml`:

```yaml
name: snip

services:
  db:
    image: postgres:18-alpine
    environment:
      POSTGRES_DB: snip
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - db-data:/var/lib/postgresql
      - ./db/links.sql:/docker-entrypoint-initdb.d/links.sql:ro
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "postgres", "-d", "snip"]
      interval: 5s
      timeout: 3s
      retries: 10

volumes:
  db-data:
```

Wat er nieuw is:

- `name: snip`: de projectnaam. Alle containers, netwerken en volumes krijgen die als voorvoegsel.
- **`/docker-entrypoint-initdb.d/`**: het Postgres-image voert SQL-bestanden in deze map uit bij
  de **allereerste** start. Herken je dat? Het is hetzelfde moment als waarop het wachtwoord wordt
  ingesteld (breek-het 3 van module 02). Je hoeft `links.sql` dus niet meer met de hand in te laden.
- **`healthcheck`**: elke 5 seconden draait Podman `pg_isready` in de container. Zo weet
  Podman wanneer de database echt klaar is, en niet alleen dat de container draait.

Starten:

```bash
podman compose up -d
podman compose ps
```

Kijk naar `STATUS`: eerst `(starting)`, na een paar seconden `(healthy)`. En naar `NAMES`:
`snip_db_1`, dus projectnaam, service-naam en een volgnummer.

```bash
podman compose exec db psql -U postgres -d snip -c "SELECT * FROM links;"
```

De data uit `links.sql` staat er al. `podman compose exec db` werkt als `podman exec`, maar dan
met de service-naam.

**6. De API erbij**

Voeg onder `services:` (op dezelfde hoogte als `db:`) toe:

```yaml
  api:
    build: ./api
    image: snip-api:compose
    environment:
      DATABASE_URL: postgres://postgres:${POSTGRES_PASSWORD}@db:5432/snip
      APP_VERSION: compose
    depends_on:
      db:
        condition: service_healthy
```

- `build: ./api`: bouw het image uit `api/Dockerfile`, en noem het `snip-api:compose`.
- `@db:5432`: de service-naam is het adres.
- `depends_on` met `service_healthy`: de API start pas als de healthcheck van `db` groen is.
- **Geen `ports`**: de API is alleen intern bereikbaar.

```bash
podman compose up -d
podman compose logs api
```

Compose bouwt het image, ziet dat `db` al draait, en start alleen de API erbij. Test de API van
binnenuit, want van buiten kun je er niet bij:

```bash
podman compose exec api node -e "fetch('http://localhost:3000/health/db').then(r => r.text()).then(console.log)"
```

`{"database":"ok"}`. (Hier klopt `localhost` wél: het commando draait in de API-container zelf.)

**7. De website erbij**

Voeg toe onder `services:`:

```yaml
  web:
    image: nginx:alpine
    ports:
      - "8080:80"
    volumes:
      - ./web/site:/usr/share/nginx/html:ro
      - ./web/nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - api
```

Twee bind mounts: de webpagina, en de nginx-configuratie die de standaardconfiguratie vervangt.
Bekijk [`web/nginx.conf`](../../app/web/nginx.conf) gerust: `proxy_pass http://api:3000` is
weer de service-naam als adres.

```bash
podman compose up -d
```

Open <http://localhost:8080>. Daar is snip, met een formulier. Maak een korte link aan en klik
erop. Onderaan zie je welke API-container antwoordde.

```bash
podman compose ps
```

Drie containers. Alleen `web` heeft een poort naar buiten.

### Deel C — Werken met Compose

**8. Logs van alles tegelijk**

```bash
podman compose logs -f
```

Gebruik de website even en kijk mee. Elke regel begint met de naam van de container. `Ctrl+C`
stopt het meekijken.

**9. Stoppen en weer starten**

```bash
podman compose stop
podman compose start
```

Containers gaan uit en weer aan, net als `podman stop` en `podman start`. Alles blijft bestaan.

**10. Helemaal opruimen, en weer opbouwen**

```bash
podman compose down
podman ps -a --filter name=snip_
podman volume ls --filter name=snip_
```

De containers en het netwerk zijn weg, maar het volume `snip_db-data` staat er nog. Start alles
weer:

```bash
podman compose up -d
```

Ververs <http://localhost:8080>: je zelfgemaakte link staat er nog.

**11. Hulpmiddelen alleen als je ze nodig hebt**

Adminer wil je niet altijd hebben draaien. Met een *profiel* start een service alleen als je
daarom vraagt. Voeg toe onder `services:`:

```yaml
  adminer:
    image: adminer
    profiles: ["tools"]
    ports:
      - "8081:8080"
    environment:
      ADMINER_DEFAULT_SERVER: db
```

```bash
podman compose up -d                     # adminer start níet
podman compose --profile tools up -d     # nu wel
```

Op <http://localhost:8081> staat de server al op `db` ingevuld. Het wachtwoord staat in je
`.env`.

---

## Breek het

### 💥 1. Het vergeten .env-bestand

Een collega haalt je repo op en start meteen. Speel dat na:

```bash
podman compose --profile tools down -v
mv .env .env.weg
podman compose up -d
podman compose ps -a
```

<details>
<summary>Hint</summary>

Welke container ontbreekt of is gestopt? Lees zijn logs met `podman compose logs <service>`.
</details>

<details>
<summary>Uitleg en oplossing</summary>

`db` stopt meteen: `superuser password is not specified`. Zonder `.env` wordt
`${POSTGRES_PASSWORD}` stilletjes **leeg**. podman-compose geeft daar geen waarschuwing voor.

Dit is waarom er een `.env.example` in de repo staat, en waarom je in een README zet:
"`cp .env.example .env`". Herstel:

```bash
podman compose down -v
mv .env.weg .env
podman compose up -d
```

(`down -v` gooit ook het volume weg, zodat je zeker weet dat de database opnieuw en mét
wachtwoord wordt aangemaakt. Zie ook breek-het 3.)
</details>

### 💥 2. Code aangepast, niets te zien

Doe alsof je de API hebt aangepast. Dit commando verandert één tekst in de code:

```bash
sed -i '' "s/app: 'snip-api'/app: 'snip-api (nieuw)'/" api/src/index.ts
podman compose up -d --build
curl localhost:8080/api/info
```

<details>
<summary>Hint</summary>

Kijk naar `podman images snip-api`: is er een nieuw image gebouwd? En welk image gebruikt de
draaiende container? (`podman inspect snip_api_1 --format '{{.Image}}'`)
</details>

<details>
<summary>Uitleg en oplossing</summary>

Er staat nog steeds `"app":"snip-api"`. `--build` heeft wel een nieuw image gebouwd, maar
podman-compose vervangt een bestaande container alleen als zijn **configuratie** in
`compose.yaml` veranderde. Een nieuw image telt daar niet voor mee. (Docker Compose doet dat
wel. Dit is een verschil tussen de twee.)

Dwing het af:

```bash
podman compose up -d --build --force-recreate api
curl localhost:8080/api/info
```

Zet de code terug:

```bash
sed -i '' "s/app: 'snip-api (nieuw)'/app: 'snip-api'/" api/src/index.ts
podman compose up -d --build --force-recreate api
```

Dit is hetzelfde principe als breek-het 3 van module 03: een nieuw image verandert geen
bestaande container. Je moet de container vervangen.
</details>

### 💥 3. Het verschil tussen `down` en `down -v`

```bash
podman compose down -v
podman compose up -d
```

Open <http://localhost:8080>.

<details>
<summary>Uitleg</summary>

Je zelfgemaakte links zijn weg. Alleen de voorbeelden uit `links.sql` staan er weer, want het
volume was nieuw en dus draaide het init-script opnieuw.

- `podman compose down`: containers en netwerk weg, **volumes blijven**.
- `podman compose down -v`: ook de **volumes** weg, dus al je data.

Handig om opnieuw te beginnen, gevaarlijk als je dat niet van plan was. Typ `-v` nooit
uit gewoonte.
</details>

---

## Op je werk

- **Compose is voor je laptop.** Veel teams leveren een `compose.yaml` mee waarmee je de app met
  database en andere afhankelijkheden lokaal start. Je `pricemeister`-project doet precies dat.
  In productie draait niets op Compose, maar op Kubernetes.
- **Van Compose naar Kubernetes.** De begrippen komen terug onder andere namen:

  | Compose | Kubernetes |
  |---|---|
  | service | Deployment + Service |
  | service-naam als adres | naam van de Service als adres |
  | `ports` | Service van type LoadBalancer, of Ingress/Gateway |
  | volume | PersistentVolumeClaim |
  | `environment` / `.env` | ConfigMap / Secret |
  | `healthcheck` | liveness- en readiness-probes |
  | `depends_on` | **bestaat niet** |

- **Er is geen `depends_on` in Kubernetes.** Containers starten in willekeurige volgorde en
  kunnen op elk moment herstarten. Een app moet er dus tegen kunnen dat de database even weg is,
  en het opnieuw proberen. Onze API doet dat: hij start ook zonder database, en `/health/db` laat
  zien of hij er al bij kan.
- **`.env` gaat nooit in Git.** Op je werk staan secrets in Azure Key Vault, en lokaal vaak in
  een `.env` die je van een collega of uit een kluis haalt. Een `.env.example` met nep-waarden is
  wel gebruikelijk.

---

## Checkpoint

<details>
<summary>1. Waarom heeft de API in <code>compose.yaml</code> geen <code>ports</code>, terwijl de website wel bij de API kan?</summary>

Alle services zitten op hetzelfde netwerk van Compose. nginx praat rechtstreeks met `api:3000`.
`ports` is alleen nodig voor verkeer van buiten, en daar is `web` de enige ingang.
</details>

<details>
<summary>2. Hoe weet de API dat de database <code>db</code> heet?</summary>

Compose geeft elke service een DNS-naam op het netwerk, gelijk aan de service-naam. Die staat
in `DATABASE_URL`.
</details>

<details>
<summary>3. Wat is het verschil tussen <code>depends_on: [db]</code> en <code>depends_on: {db: {condition: service_healthy}}</code>?</summary>

De eerste wacht alleen tot de container van `db` is **gestart**. De tweede wacht tot de
healthcheck **groen** is, dus tot Postgres echt verbindingen accepteert.
</details>

<details>
<summary>4. Waarom staat het wachtwoord in <code>.env</code> en niet in <code>compose.yaml</code>?</summary>

`compose.yaml` gaat in Git, `.env` niet. Zo deel je de opzet, maar niet het geheim.
</details>

<details>
<summary>5. Wanneer draait <code>links.sql</code> uit <code>/docker-entrypoint-initdb.d/</code>?</summary>

Alleen bij de allereerste start, als het volume nog leeg is. Net als het instellen van het
wachtwoord.
</details>

<details>
<summary>6. Je raakt je data kwijt na <code>podman compose down</code>. Wat heb je waarschijnlijk getypt?</summary>

`podman compose down -v`. Zonder `-v` blijven de volumes staan.
</details>

### Eindopdracht

Begin schoon:

```bash
cd ~/Documents/local/docker-k8s-cursus/app
podman compose --profile tools down -v
```

Zorg daarna dat:

1. `app/compose.yaml` de services `db`, `api`, `web` en (met profiel `tools`) `adminer` bevat,
   zoals in het lab;
2. er **geen wachtwoord** in `compose.yaml` staat, alleen in `.env`;
3. de hele app draait met `podman compose up -d`, met **alleen `web`** bereikbaar van buiten
   (op 8080);
4. je via de website een korte link met code **`compose`** hebt gemaakt naar
   `https://docs.podman.io`;
5. die link een `podman compose down` + `up -d` overleeft.

```bash
cd ~/Documents/local/docker-k8s-cursus/modules/04-compose
./check.sh
```

Groen? Dan heb je het containerdeel onder de knie. In **module 05** maak je het image
productierijp en laat je het voor het eerst bouwen door GitHub Actions.

---

## Spiekbrief

Alle commando's draai je in de map met `compose.yaml`.

| Commando | Wat het doet |
|---|---|
| `podman compose up -d` | alles bouwen (indien nodig), aanmaken en starten |
| `podman compose up -d --build --force-recreate SERVICE` | opnieuw bouwen én de container vervangen |
| `podman compose --profile tools up -d` | ook services met dat profiel starten |
| `podman compose ps` | status van alle containers, inclusief health |
| `podman compose logs [-f] [SERVICE]` | logs, van alles of van één service |
| `podman compose exec SERVICE commando` | commando in een draaiende service |
| `podman compose stop` / `start` | stoppen / weer starten |
| `podman compose down` | containers en netwerk weg, **volumes blijven** |
| `podman compose down -v` | ⚠️ ook de volumes weg: **data weg** |

| compose.yaml | |
|---|---|
| `name:` | projectnaam (voorvoegsel van alles) |
| `services: NAAM:` | een container; de naam is ook het adres |
| `image:` / `build:` | bestaand image gebruiken / zelf bouwen |
| `environment:` | env vars; `${VAR}` komt uit `.env` |
| `ports:` | `"buiten:binnen"` |
| `volumes:` | `naam:/pad` (volume) of `./map:/pad` (bind mount) |
| `depends_on:` | volgorde, optioneel met `condition: service_healthy` |
| `healthcheck:` | commando dat controleert of de container gezond is |
| `profiles:` | service alleen starten als je om dat profiel vraagt |
