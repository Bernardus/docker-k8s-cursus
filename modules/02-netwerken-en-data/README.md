# Module 02 — Netwerken & data

**Doel:** je laat containers samenwerken via een eigen netwerk, waarin ze elkaar op naam
vinden. En je bewaart data buiten de container, zodat die een `podman rm` overleeft.

**Tijd:** ±1,5 uur

**Nodig:** module 01 afgerond

---

## Uitleg

### Twee soorten verkeer

```
  jouw Mac
     │ localhost:8080   ← alleen hier is -p voor nodig
┌────▼──────────── container-netwerk ──────────────────────┐
│  snip-web ───► snip-api ───► snip-db:5432                │
│  (nginx)       (Node)        (postgres, géén -p)         │
└──────────────────────────────────────────────────────────┘
```

- **Van buiten naar binnen** (je browser → een container) gaat via een gepubliceerde poort: `-p`.
- **Tussen containers** gaat het rechtstreeks, binnen het container-netwerk, naar de poort waarop
  de container luistert (bij Postgres 5432). Daar is géén `-p` voor nodig.

Dat de database geen `-p` heeft, is dus geen beperking maar juist goed: van buitenaf kan
niemand erbij.

De API bouwen we pas in module 03. In deze module gebruiken we als stand-in **Adminer**, een
kant-en-klare webapp om databases te beheren. Het is een container die met de database praat,
precies zoals onze API straks doet.

### Het standaardnetwerk en eigen netwerken

Elke container hangt aan een netwerk. Geef je niets op, dan is dat het standaardnetwerk
`podman`.

| | Standaardnetwerk `podman` | Eigen netwerk (`podman network create`) |
|---|---|---|
| Container krijgt een IP-adres | ja | ja |
| Containers vinden elkaar **op naam** | **nee**: er is geen DNS | **ja**: ingebouwde DNS |
| Gebruik je voor | losse, snelle experimenten | alles wat samenwerkt |

```
   eigen netwerk "snip-net"
  ┌───────────────────────────────────────────────────┐
  │   DNS:  snip-db  →  10.89.1.2                      │
  │                                                   │
  │   snip-adminer ──── "snip-db:5432" ────► snip-db   │
  │     :8080                                 :5432   │
  └─────┬─────────────────────────────────────────────┘
        │ -p 8081:8080
   localhost:8081  (jouw Mac)
```

Waarom op naam en niet op IP-adres? Containers zijn wegwerpbaar (module 01). Elke keer dat je
`snip-db` opnieuw maakt, kan hij een ander IP-adres krijgen. De naam blijft hetzelfde.

### Data: waar laat je het?

In module 01 zag je het al: alles wat in de container zelf wordt geschreven, is weg bij
`podman rm`. Voor een database is dat onacceptabel. Je koppelt daarom opslag van **buiten** de
container aan een map **in** de container:

```
                     ┌──────────────── container ──────────────────┐
  volume "snip-data" ──►  /var/lib/postgresql       (database-data)  │
  (beheerd door Podman)  │                                            │
                     │                                              │
  map op je Mac     ──►  /usr/share/nginx/html     (websitebestanden)│
  ./bestanden/site   │                                              │
                     │   al het andere: beschrijfbare laag          │
                     │   → weg bij podman rm                        │
                     └──────────────────────────────────────────────┘
```

| | Volume | Bind mount |
|---|---|---|
| Wat is het | opslag die Podman voor je beheert | een map van je Mac, doorgegeven aan de container |
| Waar staat het | in de podman machine (de VM) | op je Mac, gewoon in Finder te zien |
| Schrijfwijze | `-v snip-data:/pad/in/container` | `-v ./bestanden/site:/pad/in/container` |
| Typisch voor | databases, alles wat moet blijven bestaan | ontwikkelen: bestanden die je live wilt aanpassen |

Ezelsbruggetje: begint het deel vóór de `:` met `./` of `/`, dan is het een **map** (bind
mount). Is het een kale naam, dan is het een **volume**.

---

## Lab

Werk in de map van deze module; de paden naar `bestanden/` gaan daarvan uit:

```bash
cd ~/Documents/local/docker-k8s-cursus/modules/02-netwerken-en-data
```

Ruim eerst de containers uit module 01 op, op naam:

```bash
podman ps -a
podman rm -f -v snip-web snip-db
```

Heb je nog containers met de oude namen `kort-web` en `kort-db`? Die mogen ook weg:

```bash
podman rm -f -v kort-web kort-db
```

### Deel A — Een eigen netwerk

**1. Welke netwerken zijn er?**

```bash
podman network ls
```

Je ziet in elk geval `podman`, het standaardnetwerk. Zie je ook netwerken van andere
projecten? Die zijn door Compose gemaakt (module 04). Laat ze gewoon staan.

**2. Eerst het probleem**

Start een database op het standaardnetwerk en probeer hem vanuit een tweede container op naam
te bereiken:

```bash
podman run -d --name snip-db -e POSTGRES_PASSWORD=geheim -e POSTGRES_DB=snip postgres:18-alpine
podman run --rm postgres:18-alpine pg_isready -h snip-db
```

`pg_isready` is een klein hulpprogramma uit het Postgres-image dat controleert of er op een adres
een database antwoordt. Hier: `no response`. Op het standaardnetwerk kent niemand de naam
`snip-db`.

```bash
podman rm -f -v snip-db
```

**3. Een eigen netwerk maken**

```bash
podman network create snip-net
podman network inspect snip-net
```

Zoek in de output naar `"subnet"` (de reeks IP-adressen van dit netwerk) en
`"dns_enabled": true`. Dat laatste is het verschil met het standaardnetwerk.

**4. De database op het netwerk zetten**

```bash
podman run -d --name snip-db --network snip-net \
  -e POSTGRES_PASSWORD=geheim \
  -e POSTGRES_DB=snip \
  postgres:18-alpine
```

Wacht tot `podman logs snip-db` twee keer `ready to accept connections` laat zien.

**5. Nu wel op naam?**

```bash
podman run --rm --network snip-net postgres:18-alpine pg_isready -h snip-db
```

`accepting connections`. Het enige verschil met stap 2 is `--network snip-net`.

**6. Hoe vindt hij die naam?**

```bash
podman run --rm --network snip-net alpine getent hosts snip-db
```

Je ziet het IP-adres dat het netwerk aan `snip-db` heeft gegeven, met de naam erachter. Dit is de
ingebouwde DNS van het netwerk.

**7. Data inladen**

```bash
podman exec -i snip-db psql -U postgres -d snip < bestanden/links.sql
```

Het klaargezette [`links.sql`](bestanden/links.sql) maakt de tabel `links` en vult hem met een
paar rijen. Met `-i` (zonder `-t`) en `<` geef je een bestand van je Mac als invoer aan `psql`
in de container.

**8. Adminer: een webapp die met de database praat**

```bash
podman run -d --name snip-adminer --network snip-net -p 8081:8080 adminer
```

Open <http://localhost:8081> en log in. Adminer volgt de taal van je browser.

| Veld | Waarde |
|---|---|
| Databasesysteem | **PostgreSQL** (staat standaard op MySQL!) |
| Server | `snip-db` (er staat standaard `db`; vervang dat) |
| Gebruikersnaam | `postgres` |
| Wachtwoord | `geheim` |
| Database | `snip` |

Klik op **Aanmelden**, daarna links op de tabel `links`, en open de gegevens. Daar zijn je rijen.

Kijk goed naar het veld **Server**: daar vulde je gewoon `snip-db` in. Adminer draait in een
container op `snip-net` en vindt de database via de DNS van het netwerk. Zo gaat onze API dat
straks ook doen.

**9. En vanaf je Mac?**

```bash
nc -z localhost 5432 && echo "open" || echo "dicht"
```

`dicht`. Adminer kan bij de database, je Mac niet. Alleen Adminer heeft een voordeur (`-p`).

### Deel B — Data die blijft

**10. Eerst het probleem**

```bash
podman rm -f -v snip-db
podman run -d --name snip-db --network snip-net \
  -e POSTGRES_PASSWORD=geheim \
  -e POSTGRES_DB=snip \
  postgres:18-alpine
```

Wacht even en kijk dan:

```bash
podman exec snip-db psql -U postgres -d snip -c "SELECT count(*) FROM links;"
```

`relation "links" does not exist`. De nieuwe container begon met een lege database, en al je
data is weg. (Ververs Adminer maar eens.)

**11. Een volume maken en gebruiken**

```bash
podman volume create snip-data
podman rm -f -v snip-db
podman run -d --name snip-db --network snip-net \
  -v snip-data:/var/lib/postgresql \
  -e POSTGRES_PASSWORD=geheim \
  -e POSTGRES_DB=snip \
  postgres:18-alpine
```

Nieuw is `-v snip-data:/var/lib/postgresql`: het volume `snip-data` wordt gekoppeld aan de
map waar Postgres 18 zijn data bewaart. Laad de data opnieuw in:

```bash
podman exec -i snip-db psql -U postgres -d snip < bestanden/links.sql
```

**12. Het bewijs**

Gooi de container weg en maak hem opnieuw, met exact hetzelfde commando als in stap 11:

```bash
podman rm -f -v snip-db
podman run -d --name snip-db --network snip-net \
  -v snip-data:/var/lib/postgresql \
  -e POSTGRES_PASSWORD=geheim \
  -e POSTGRES_DB=snip \
  postgres:18-alpine
```

```bash
podman exec snip-db psql -U postgres -d snip -c "SELECT * FROM links;"
```

Je rijen zijn er nog, met hun oorspronkelijke `created_at`. De container is nieuw, de data
niet. Ververs Adminer: ook daar staat alles nog.

**13. Waar staat dat volume?**

```bash
podman volume ls
podman volume inspect snip-data
```

Kijk naar `Mountpoint`: `/var/lib/containers/storage/volumes/snip-data/_data`. Dat is een pad
**in de podman machine** (de VM), niet op je Mac. Je ziet het dus niet in Finder. Podman beheert
het voor je.

> Zie je in `podman volume ls` ook volumes van andere projecten? Daar zit hun data in. Laat
> die staan.

**Naamloze volumes.** In `podman volume ls` zie je misschien ook volumes met een lange,
cryptische naam. Die maakt het Postgres-image zelf aan als je géén `-v` opgeeft, zoals in
module 01 en in stap 2 en 10 hierboven. Een gewone `podman rm` laat ze staan, zodat ze zich
ongemerkt opstapelen. Daarom gebruiken we in deze module `podman rm -f -v`:

- `-v` ruimt de **naamloze** volumes van die container mee op;
- een volume **met een naam** (zoals `snip-data`) blijft altijd staan, dat verwijder je alleen
  met `podman volume rm`;
- `podman run --rm` ruimt naamloze volumes ook automatisch op.

Losgeraakte naamloze volumes (van containers die niet meer bestaan) vind je zo:

```bash
podman volume ls --filter dangling=true
```

Zitten daar volumes tussen uit je eigen oefeningen, dan kun je ze met `podman volume rm <naam>`
weggooien. Laat volumes waarvan je niet weet waar ze vandaan komen met rust.

**14. Een bind mount: bestanden van je Mac**

```bash
podman run -d --name snip-web -p 8080:80 \
  -v ./bestanden/site:/usr/share/nginx/html:ro \
  nginx:alpine
```

Open <http://localhost:8080>. nginx serveert [`bestanden/site/index.html`](bestanden/site/index.html)
rechtstreeks vanaf je Mac. De `:ro` aan het eind betekent *read-only*: de container mag
lezen, niet schrijven.

**15. Live meekijken**

Kopieer een klaargezet bestand in de map op je Mac:

```bash
cp bestanden/extra/nieuws.html bestanden/site/
```

Open <http://localhost:8080/nieuws.html>. Het staat er meteen, zonder herstart en zonder nieuw
image. De container kijkt rechtstreeks in je map. Haal het weer weg:

```bash
rm bestanden/site/nieuws.html
```

Ververs: `404 Not Found`.

**16. Read-only is echt read-only**

```bash
podman exec snip-web sh -c 'echo hoi > /usr/share/nginx/html/hoi.html'
```

`Read-only file system`. Handig: een gehackte of buggy container kan je bestanden niet
overschrijven.

**17. Overzicht**

```bash
podman inspect snip-db  --format '{{range .Mounts}}{{.Type}}: {{.Name}} → {{.Destination}}{{end}}'
podman inspect snip-web --format '{{range .Mounts}}{{.Type}}: {{.Source}} → {{.Destination}}{{end}}'
```

Dit heb je nu staan:

```
   eigen netwerk "snip-net"
  ┌────────────────────────────────────────────────────────┐
  │  snip-adminer ─────────────────► snip-db               │
  │      │                             │                   │
  │      │                             └─ volume snip-data │
  └──────┼─────────────────────────────────────────────────┘
         │ :8081
   ──────┴────────── jouw Mac ──────────────────────────────
         │ :8080
  ┌──────┴──────┐
  │  snip-web   │ ← bind mount ./bestanden/site (read-only)
  └─────────────┘   (standaardnetwerk; praat met niemand)
```

---

## Breek het

### 💥 1. Een oude tutorial

Op internet (en in veel AI-antwoorden) staat dat je Postgres-data koppelt aan
`/var/lib/postgresql/data`. Probeer het:

```bash
podman run -d --name db-oud -e POSTGRES_PASSWORD=geheim \
  -v db-oud:/var/lib/postgresql/data \
  postgres:18-alpine
podman ps -a --filter name=db-oud
```

<details>
<summary>Hint</summary>

`Exited (1)`. Je weet inmiddels welk commando je nu typt.
</details>

<details>
<summary>Uitleg en oplossing</summary>

```bash
podman logs db-oud
```

Het image legt het zelf uit. Vanaf Postgres 18 bewaart het image zijn data op een andere plek, en
koppel je je volume aan **`/var/lib/postgresql`**. Het oude pad was correct tot en met
Postgres 17.

Twee lessen:
- **Lees de logs.** Goede images vertellen precies wat er mis is.
- **Zet altijd een versie in de tag** (`postgres:18`, niet `postgres:latest`). Anders krijg je
  ongemerkt een nieuwe hoofdversie, en die kan je bestaande data niet altijd lezen.

```bash
podman rm db-oud
podman volume rm db-oud
```
</details>

### 💥 2. Adminer op het verkeerde netwerk

```bash
podman run -d --name adminer-los -p 8082:8080 adminer
```

Log in op <http://localhost:8082> met dezelfde gegevens als in stap 8.

<details>
<summary>Uitleg en oplossing</summary>

`could not translate host name "snip-db" to address`. Deze Adminer hangt aan het
standaardnetwerk. Daar is geen DNS, en `snip-db` zit daar ook niet.

Je kunt een draaiende container alsnog aan een netwerk hangen:

```bash
podman network connect snip-net adminer-los
```

Probeer opnieuw in te loggen: nu lukt het wel.

```bash
podman rm -f adminer-los
```
</details>

### 💥 3. Nieuw wachtwoord, oude data

Je besluit dat `geheim` geen goed wachtwoord is:

```bash
podman rm -f -v snip-db
podman run -d --name snip-db --network snip-net \
  -v snip-data:/var/lib/postgresql \
  -e POSTGRES_PASSWORD=nieuw \
  -e POSTGRES_DB=snip \
  postgres:18-alpine
```

Log in Adminer in met wachtwoord `nieuw`.

<details>
<summary>Hint</summary>

Lukt het met het **oude** wachtwoord wel? Kijk in `podman logs snip-db` naar een regel met
`Skipping initialization`.
</details>

<details>
<summary>Uitleg en oplossing</summary>

`password authentication failed`. Met `geheim` lukt het wel.

De `POSTGRES_*`-variabelen worden alleen gebruikt bij de **allereerste start**, als de datamap
nog leeg is. Dan wordt de database aangemaakt en het wachtwoord *in de database zelf*
opgeslagen. Bij elke volgende start ziet het image dat er al data is (`Skipping
initialization`) en negeert het de variabelen.

Wil je echt een ander wachtwoord, dan wijzig je het in de database (`ALTER USER`), of je begint
opnieuw met een leeg volume. In Kubernetes loop je tegen precies hetzelfde aan als je een
secret vervangt.

Zet het terug:

```bash
podman rm -f -v snip-db
podman run -d --name snip-db --network snip-net \
  -v snip-data:/var/lib/postgresql \
  -e POSTGRES_PASSWORD=geheim \
  -e POSTGRES_DB=snip \
  postgres:18-alpine
```
</details>

### 💥 4. Tikfout

```bash
podman run -d --name web-tik -p 8083:80 -v ./bestanden/stie:/usr/share/nginx/html:ro nginx:alpine
```

<details>
<summary>Uitleg</summary>

`lstat bestanden/stie: no such file or directory`. Podman controleert of de map bestaat.
Docker maakt in dit geval stilletjes een lege map aan, waarna nginx `403 Forbidden` geeft.
Dat is verwarrender. Podman is hier strenger, en dat is fijn.
</details>

---

## Op je werk

- **Netwerken in Kubernetes:** daar maak je geen netwerken aan. Elke pod kan in principe
  elke andere pod bereiken. Een vaste naam (zoals `snip-db`) krijg je via een **Service**
  (module 10). Wie met wie mag praten, regel je met **NetworkPolicies** (module 15). Platformteams
  zetten vaak standaard *alles dicht* per namespace, en dan moet jij expliciet toestaan dat de
  api met de database praat.
- **Een eigen Podman-netwerk scheidt vooral namen, geen verkeer.** Een container op een ander
  netwerk kan een IP-adres in `snip-net` nog steeds bereiken. Dat heb ik op jouw Mac getest.
  Echte afscherming is in Kubernetes het werk van NetworkPolicies.
- **Databases:** in een enterprise draait de productiedatabase zelden in een container die
  jij beheert. Meestal is het een managed dienst, zoals *Azure Database for PostgreSQL*. Je app
  krijgt alleen een adres en inloggegevens, uit Key Vault. Volumes in Kubernetes heten
  *PersistentVolumeClaims* en zijn op AKS meestal Azure Disks (module 12).
- **Bind mounts zijn voor ontwikkelen.** In productie zit je code in het image (module 03) en
  komt je configuratie uit ConfigMaps (module 11). Er wordt nooit een map van een server in een
  container gekoppeld.
- **Wachtwoorden op de command line zijn zichtbaar.** Probeer:
  `podman inspect snip-db --format '{{.Config.Env}}'`. Daar staat `POSTGRES_PASSWORD=geheim`,
  voor iedereen met toegang, en het staat ook in je shell-history. In productie gebruik je
  secrets (Key Vault → Kubernetes Secret). Daar komen we op terug.

---

## Checkpoint

<details>
<summary>1. Waarom heeft <code>snip-db</code> geen <code>-p</code> nodig, terwijl Adminer er wel bij kan?</summary>

`-p` is alleen voor verkeer van buiten (je Mac) naar een container. Adminer en `snip-db` zitten
op hetzelfde netwerk en praten rechtstreeks met elkaar, op poort 5432 van de container.
</details>

<details>
<summary>2. Waarom vindt Adminer <code>snip-db</code> op naam in <code>snip-net</code>, maar niet op het standaardnetwerk?</summary>

Een eigen netwerk heeft ingebouwde DNS, die namen van containers omzet naar hun IP-adres. Het
standaardnetwerk `podman` heeft dat niet.
</details>

<details>
<summary>3. Volume of bind mount: wat kies je voor (a) de data van Postgres, (b) HTML die je tijdens het ontwikkelen aanpast?</summary>

(a) Een volume: Podman beheert het, en het overleeft containers. (b) Een bind mount: je past
het bestand op je Mac aan, en de container ziet het meteen.
</details>

<details>
<summary>4. Je maakt <code>snip-db</code> opnieuw met een nieuw wachtwoord en het oude volume. Inloggen met het nieuwe wachtwoord mislukt. Waarom?</summary>

De `POSTGRES_*`-variabelen worden alleen gebruikt als de datamap leeg is. Het wachtwoord staat
in de bestaande data, en de nieuwe waarde wordt genegeerd.
</details>

<details>
<summary>5. Waar staat een volume fysiek in jouw opstelling?</summary>

In de podman machine, de Linux-VM op je Mac, onder `/var/lib/containers/storage/volumes/`.
Niet ergens in je Mac-mappen.
</details>

### Eindopdracht

Ruim alles uit deze module op, op naam:

```bash
podman rm -f -v snip-db snip-adminer snip-web
podman volume rm snip-data
podman network rm snip-net
```

Bouw daarna **zonder in het lab te kijken** het volgende (de spiekbrief mag wel):

1. Een netwerk **`snip-net`**.
2. Een volume **`snip-data`**.
3. **`snip-db`**: `postgres:18-alpine` op `snip-net`, data in `snip-data`, met een database
   `snip`, en **niet** bereikbaar vanaf je Mac.
4. Laad [`bestanden/links.sql`](bestanden/links.sql) in.
5. **`snip-adminer`**: `adminer` op `snip-net`, bereikbaar op <http://localhost:8081>.
6. **`snip-web`**: `nginx:alpine` op <http://localhost:8080>, dat `bestanden/site` read-only
   serveert via een bind mount.
7. **Bewijs dat je data blijft bestaan:** gooi `snip-db` weg en maak hem opnieuw. Het
   controlescript ziet aan de tijdstempels of je data ouder is dan je container.

```bash
./check.sh
```

Groen? In **module 03** bouw je je eerste eigen image: de `snip`-API. Die praat dan met
`snip-db`, net zoals Adminer nu doet.

---

## Spiekbrief

| Commando | Wat het doet |
|---|---|
| `podman network ls` | netwerken tonen |
| `podman network create NAAM` | eigen netwerk maken (met DNS) |
| `podman network inspect NAAM` | details: subnet, DNS |
| `podman network connect NET CONTAINER` | draaiende container aan een netwerk hangen |
| `podman network rm NAAM` | netwerk verwijderen |
| `podman run --network NAAM ...` | container op een netwerk starten |
| `podman volume ls` | volumes tonen |
| `podman volume create NAAM` | volume maken |
| `podman volume inspect NAAM` | details, o.a. waar het staat |
| `podman volume rm NAAM` | volume verwijderen (**data weg!**) |
| `podman rm -v NAAM` | container weg, inclusief zijn naamloze volumes |
| `podman volume ls --filter dangling=true` | volumes die door geen enkele container gebruikt worden |
| `-v VOLUME:/pad` | volume koppelen |
| `-v ./map:/pad[:ro]` | bind mount: map van je Mac koppelen (`:ro` = alleen lezen) |
| `podman exec -i NAAM cmd < bestand` | bestand van je Mac als invoer gebruiken |
| `podman volume prune` | ⚠️ alle volumes die geen container gebruikt verwijderen, ook die van andere projecten |
