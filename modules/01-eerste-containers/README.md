# Module 01 — Eerste containers

**Doel:** je kunt containers starten, bekijken, binnenstappen, stoppen en opruimen. Je
weet hoe je een poort openzet, en bij een kapotte container weet je waar je moet kijken.

**Tijd:** ±1,5 uur

**Nodig:** module 00 afgerond (`../00-setup/check.sh` is groen)

---

## Uitleg

### De levenscyclus van een container

```
               podman create           podman start
   image  ─────────────────►  created ─────────────►  running
                                                        │  ▲
                                   hoofdproces stopt of │  │ podman start
                                   podman stop          ▼  │
                                                       exited
                                                          │
                                                          │ podman rm
                                                          ▼
                                                     (weg, inclusief
                                                      alle wijzigingen)
```

`podman run` is drie stappen in één: **pull** (als het image er nog niet is) → **create** → **start**.

De belangrijkste regel van deze module:

> **Een container leeft precies zo lang als zijn hoofdproces (PID 1).**
> Stopt dat proces, dan stopt de container. Ook als jij dat niet de bedoeling vond.

### Poorten: buiten en binnen

Een container heeft een eigen netwerk. Een webserver die *in* de container op poort 80
luistert, is van buitenaf **onbereikbaar** totdat jij een poort *publiceert*:

```
  browser                     jouw Mac                         container
 ─────────►  localhost:8080  ══════════ Podman ═════════►  :80  (nginx)

                       podman run -p 8080:80 nginx
                                  ▲    ▲
                       host (buiten)  container (binnen)
```

Ezelsbruggetje: **`-p buiten:binnen`**. Links staat jouw kant.

### Image-namen: kort en voluit

Een image-naam bestaat eigenlijk uit drie delen:

```
   docker.io / library / nginx : alpine
   ─────────   ───────   ─────   ──────
   registry    eigenaar  naam    tag
```

In de labs typen we kort `nginx:alpine`. Podman vult dat aan tot een volledige naam:

1. Eerst kijkt Podman in een lijst met bekende korte namen (*aliases*). `nginx`, `node` en
   `alpine` staan daarin en wijzen naar Docker Hub. `hello-world` wijst naar Quay.io, zoals je
   in module 00 zag.
2. Staat de naam niet in die lijst (bijv. `postgres`), dan zoekt Podman op je Mac standaard
   op Docker Hub (`docker.io`).

Daarom zie je in `podman ps` en `podman images` altijd de volledige naam.

> In een pipeline, een Kubernetes-manifest of op je werk schrijf je altijd de **volledige naam**
> (bijv. `mijnbedrijf.azurecr.io/snip-api:1.4.2`). Dan staat er zwart op wit uit welke registry
> een image komt.

### Image-varianten

Bij populaire images kies je vaak uit varianten via de tag:

| Tag | Basis | Grootte (ruwweg) | Wanneer |
|---|---|---|---|
| `node:24` | volledig Debian | ~1 GB | zelden; alles zit erin, ook wat je niet nodig hebt |
| `node:24-slim` | uitgeklede Debian | ~250 MB | goede standaard voor productie |
| `node:24-alpine` | Alpine Linux | ~170 MB | klein. Gebruikt *musl* in plaats van *glibc*, wat soms botst met native npm-pakketten |

In deze module gebruiken we `alpine`-varianten omdat ze snel binnen zijn. In module 03 kiezen
we bewust wat het beste past voor onze API.

---

## Lab

### Deel A — In een container stappen

**1. Een interactieve Linux-shell**

```bash
podman run -it alpine sh
```

- `-i` houdt de invoer open (interactive)
- `-t` geeft je een echte terminal (tty)
- `sh` is het commando dat in de container moet draaien

Je zit nu *in* de container. Probeer:

```sh
hostname            # een ID-achtige naam: dat is het container-ID
ps                  # slechts 2 processen! sh is PID 1
ls /                # een compleet Linux-bestandssysteem, afkomstig uit het image
cat /etc/os-release # Alpine Linux
uname -a            # Linux, de kernel van de Podman-machine (VM)
whoami              # root (binnen de container)
touch /hallo.txt    # maak een bestand aan
exit
```

Zie je in `ps` maar twee processen? Dat zijn de oogkleppen uit module 00. Op je Mac
draaien honderden processen, maar deze container ziet alleen zichzelf.

**2. Waar is hij gebleven?**

```bash
podman ps        # draaiende containers → leeg
podman ps -a     # álle containers → daar is hij, status "Exited (0)"
```

Je typte `exit`, dus `sh` (PID 1) stopte en daarmee de container. Kijk ook naar de kolom
`NAMES`: Podman verzon een naam als `quirky_turing`, omdat jij er geen opgaf.

**3. Een nieuwe container is een schone lei**

```bash
podman run -it alpine sh
```

```sh
ls /hallo.txt       # No such file or directory!
exit
```

Waarom? Dit is een **nieuwe** container van hetzelfde (onveranderlijke) image. Je bestand
zit in de *vorige* container. Die kun je terughalen:

```bash
podman ps -a                     # zoek de naam van je eerste container
podman start -ai <naam>          # -a = attach, -i = interactive
```

```sh
ls /hallo.txt       # daar is hij weer
exit
```

**4. Een Node-REPL zonder Node te installeren**

```bash
podman run -it --rm node:24-alpine
```

```js
> process.version
> process.platform      // 'linux', niet 'darwin'
> process.arch          // 'arm64'
> .exit
```

`--rm` ruimt de container automatisch op zodra hij stopt. Controleer met `podman ps -a`:
er staat geen nieuwe container bij.

**5. Eén commando uitvoeren en weer weg**

Alles wat je ná de image-naam typt, vervangt het standaardcommando van het image:

```bash
podman run --rm node:24-alpine node -e "console.log('Hallo vanuit', process.version, process.platform, process.arch)"
```

Met een environment variable (`-e`):

```bash
podman run --rm -e NAAM=wereld node:24-alpine node -e "console.log('Hallo ' + process.env.NAAM)"
```

Handig voor later: je kunt zo elke Node-versie testen zonder iets te installeren.

```bash
podman run --rm node:20-alpine node -v
podman run --rm node:24-alpine node -v
```

### Deel B — Een webserver op de achtergrond

**6. Start nginx, detached, met een gepubliceerde poort**

```bash
podman run -d --name snip-web -p 8080:80 nginx:alpine
```

- `-d` (detached): draait op de achtergrond, je krijgt je terminal terug
- `--name snip-web`: een eigen naam in plaats van een verzonnen naam
- `-p 8080:80`: poort 8080 op je Mac → poort 80 in de container

Open <http://localhost:8080> of:

```bash
curl localhost:8080
```

**7. Wat draait er?**

```bash
podman ps
```

Lees de kolommen: `IMAGE`, `STATUS` (hoe lang al up), `PORTS` (`0.0.0.0:8080->80/tcp`
= buiten:binnen) en `NAMES`.

**8. Logs**

```bash
podman logs snip-web
podman logs -f snip-web      # -f = follow, live meekijken
```

Ververs de pagina een paar keer in je browser en kijk hoe de access-log meeloopt. Met
`Ctrl+C` stop je met meekijken. De container blijft gewoon draaien.

**9. Binnenstappen in een draaiende container**

```bash
podman exec -it snip-web sh
```

```sh
ps                                          # PID 1 is nginx, met een paar workers
cat /etc/nginx/conf.d/default.conf          # zoek de regel "root": waar staan de bestanden?
echo '<h1>snip — binnenkort online</h1>' > /usr/share/nginx/html/index.html
exit
```

Ververs je browser. Jouw tekst staat er.

> **`run` vs `exec`:** `podman run` maakt een **nieuwe** container. `podman exec` start een
> **extra proces in een bestaande** container. Debuggen doe je dus met `exec`.

**10. Stoppen en weer starten**

```bash
podman stop snip-web       # ververs je browser: weg
podman ps -a               # status: Exited
podman start snip-web      # ververs: je eigen tekst staat er nog!
```

Een gestopte container onthoudt zijn wijzigingen.

**11. Weggooien en opnieuw maken**

```bash
podman rm -f snip-web                                   # -f = ook als hij draait
podman run -d --name snip-web -p 8080:80 nginx:alpine
```

Ververs je browser. Je ziet weer de standaardpagina van nginx en **je wijziging is weg.**

Dit is misschien wel de belangrijkste les van het containerdenken: **containers zijn
wegwerpbaar.** Je behandelt ze als vee, niet als huisdieren. Daaruit volgt:

- wat bij je app hoort (code, html), stop je in het **image** → module 03
- data die moet blijven bestaan (database!), zet je **buiten** de container → module 02

**12. Kijken onder de motorkap**

```bash
podman stats                                  # live CPU/geheugen per container (Ctrl+C)
podman inspect snip-web | jq '.[0].State'     # de volledige status als JSON
podman inspect -f '{{.Config.Image}} is {{.State.Status}}' snip-web
```

`podman inspect` geeft *alles* wat Podman over een container weet. Het is veel, maar je
kunt er gericht in zoeken.

### Deel C — Een database

**13. Postgres starten met configuratie via env vars**

```bash
podman run -d --name snip-db \
  -e POSTGRES_PASSWORD=geheim \
  -e POSTGRES_DB=snip \
  postgres:18-alpine
```

Hoe weet je welke env vars een image snapt? Die staan in de documentatie van het image. Kijk op
<https://hub.docker.com/_/postgres> onder *Environment Variables*. Het lezen van de docs van een
image is een vaardigheid op zich.

**14. Wachten tot hij klaar is**

```bash
podman logs -f snip-db
```

Wacht op `database system is ready to accept connections`. Die regel komt **twee keer**
voorbij: eerst draait er een tijdelijke server die de database aanmaakt, daarna start de
echte. `Ctrl+C`.

**15. Een tabel maken met psql in de container**

```bash
podman exec -it snip-db psql -U postgres -d snip
```

Je zit nu in `psql`, de Postgres-console. Plak het blok hieronder; je hoeft geen SQL te
kennen. Het gaat erom dat je een programma *in* de container gebruikt.

```sql
CREATE TABLE links (
  code       text PRIMARY KEY,
  url        text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO links (code, url) VALUES
  ('gh',  'https://github.com'),
  ('k8s', 'https://kubernetes.io');

SELECT * FROM links;
\q
```

Je hoeft geen psql op je Mac te installeren, want het zit in het image. Voor een enkel
commando zonder interactie laat je `-it` weg:

```bash
podman exec snip-db psql -U postgres -d snip -c "SELECT count(*) FROM links;"
```

> Merk op dat we **geen** `-p` gebruikten. De database is dus niet vanaf je Mac bereikbaar,
> alleen vanuit andere containers. Prima, want straks praat de `api`-container ermee via een
> container-netwerk (module 02).

### Deel D — Images beheren

**16. Wat heb je nu lokaal?**

```bash
podman images
```

Je ziet o.a. de hello-images uit module 00 en `alpine`, `node`, `nginx` en `postgres`, allemaal
opgehaald door je `podman run`'s en voluit geschreven (`docker.io/library/...`). Staan er ook images van
eerdere projecten? Prima, laat die gewoon staan.

**17. Varianten vergelijken**

```bash
podman pull node:24-slim
podman pull node:24          # groot, dit duurt even
podman images node
```

Vergelijk de groottes met de tabel bovenaan.

**18. Layers bekijken**

```bash
podman image history nginx:alpine
```

Een image bestaat uit **layers**, gestapelde lagen met bestanden. Elke regel hier is een
stap uit de Dockerfile waarmee het image gebouwd is. In module 03 schrijf je zelf zo'n
Dockerfile (Podman noemt het ook wel `Containerfile`, maar het is hetzelfde). Dan worden layers
belangrijk voor snelheid en grootte.

**19. Opruimen**

```bash
podman rmi node:24              # image verwijderen
podman rmi nginx:alpine         # ❌ lukt niet: snip-web gebruikt dit image nog
podman system df                # hoeveel schijfruimte gebruikt Podman?
```

Containers ruim je op **op naam** met `podman rm`. Er bestaan ook commando's die alles in één
keer opruimen:

| Commando | Ruimt op |
|---|---|
| `podman container prune` | **alle** gestopte containers |
| `podman system prune` | alle gestopte containers, ongebruikte netwerken en losse images |

> ⚠️ "Alle" betekent ook die van **andere projecten**. Heb je containers van een ander project
> die nu gestopt zijn, dan zijn die na een prune weg, inclusief hun instellingen (poorten, env vars).
> Data in volumes blijft wel bestaan; daarover meer in module 02. Kijk dus altijd eerst met
> `podman ps -a` wat er staat, en ruim bij twijfel op naam op.

---

## Breek het

Elke opdracht gaat mis. Zoek uit **waarom** voordat je de hints opent. De reflexen die je
hier oefent, gebruik je straks in Kubernetes precies zo.

### 💥 1. De Node-container die meteen sterft

```bash
podman run -d --name node-bg node:24-alpine
podman ps
```

Hij staat er niet bij. Waarom niet?

<details>
<summary>Hint</summary>

Kijk met `podman ps -a` naar de status. Wat is het standaardcommando van `node:24-alpine`?
Wat doet dat commando zonder terminal (`-it`)?
</details>

<details>
<summary>Uitleg en oplossing</summary>

Het standaardcommando is `node` zonder argumenten, oftewel de REPL. Zonder `-it` is er geen
invoer, dus de REPL stopt meteen. PID 1 stopt, dus de container stopt (`Exited (0)`).

Geef hem iets dat blijft draaien:

```bash
podman rm node-bg
podman run -d --name node-bg node:24-alpine \
  node -e "setInterval(() => console.log('tik', new Date().toISOString()), 2000)"
podman logs -f node-bg
```

**Bonusvraag:** stop hem met `podman stop node-bg`. Waarom duurt dat ongeveer 10 seconden, terwijl
nginx meteen stopt? (Het antwoord komt in module 05. Wie het nu al uitzoekt, krijgt een
denkbeeldige medaille.)

```bash
podman rm node-bg
```
</details>

### 💥 2. De database die niet wil

```bash
podman run -d --name db-kapot postgres:18-alpine
podman ps
```

Gebruik **alleen podman-commando's** om erachter te komen wat er mis is.

<details>
<summary>Hint</summary>

Twee commando's: één om de status te zien, één om te lezen wat de container zelf zei
voordat hij stopte.
</details>

<details>
<summary>Uitleg en oplossing</summary>

```bash
podman ps -a           # Exited (1): een foutcode
podman logs db-kapot   # "Database is uninitialized and superuser password is not specified..."
```

Het Postgres-image weigert te starten zonder `POSTGRES_PASSWORD`. Oplossing: `-e
POSTGRES_PASSWORD=...` meegeven, zoals bij `snip-db`.

**Leer deze reflex uit je hoofd:** container stuk → `podman ps -a` (status en exitcode) →
`podman logs <naam>`. In Kubernetes wordt dat `kubectl get pods` → `kubectl logs`. Het is hetzelfde
denkpatroon.

```bash
podman rm db-kapot
```
</details>

### 💥 3. Bezet!

Terwijl `snip-web` draait:

```bash
podman run -d --name web2 -p 8080:80 nginx:alpine
```

<details>
<summary>Uitleg en oplossing</summary>

`bind: address already in use`: poort 8080 **op je Mac** is al bezet door `snip-web`. Een
hostpoort kan maar door één container (of programma) tegelijk gebruikt worden.

Poort 80 **in** de container is geen probleem, want elke container heeft zijn eigen netwerk.
Tien nginx-containers kunnen allemaal op hun eigen poort 80 luisteren.

Kijk ook eens naar `podman ps -a`: `web2` bestaat wel, in de status `Created`. Het aanmaken
lukte, het starten niet.

```bash
podman rm web2
podman run -d --name web2 -p 8081:80 nginx:alpine   # andere hostpoort → werkt
curl localhost:8081
podman rm -f web2
```
</details>

### 💥 4. Naam al in gebruik

```bash
podman run -d --name snip-web -p 8082:80 nginx:alpine
```

<details>
<summary>Uitleg en oplossing</summary>

`the container name "snip-web" is already in use`. Namen zijn uniek, **ook voor gestopte
containers**. Verwijder eerst de oude (`podman rm -f snip-web`) of kies een andere naam.

Podman heeft hiervoor een handige extra: `podman run --replace --name snip-web ...` gooit
de oude container met die naam weg en maakt een nieuwe. Docker kent die optie niet.
</details>

### 💥 5. Alles draait, maar niks werkt

```bash
podman run -d --name web3 -p 8083:8080 nginx:alpine
curl localhost:8083
```

De container draait (`podman ps`), maar je krijgt `Connection reset by peer`. Waarom?

<details>
<summary>Hint</summary>

Op welke poort luistert nginx **binnen** de container? Kijk nog eens naar `-p buiten:binnen`.
</details>

<details>
<summary>Uitleg en oplossing</summary>

nginx luistert binnen de container op **80**. Wij stuurden het verkeer naar poort **8080**
in de container, en daar luistert niets. Podman staat klaar om door te sturen, maar aan de
andere kant neemt niemand op.

```bash
podman rm -f web3
podman run -d --name web3 -p 8083:80 nginx:alpine
curl localhost:8083
podman rm -f web3
```

Dit komt in het echt vaak voor: je app luistert op 3000, de config zegt 8080. In Kubernetes
gaat het op precies dezelfde manier mis.
</details>

---

## Op je werk

- **Waar images vandaan komen:** in een enterprise pull je zelden rechtstreeks van Docker Hub.
  Images staan in een eigen registry (bij Azure meestal **ACR**). Vaak mag je alleen
  *goedgekeurde basis-images* van het platformteam gebruiken, en loopt Docker Hub via een
  proxy of cache, vanwege rate limits en security.
- **Niet sleutelen in productie:** in stap 9 paste je een bestand aan met `podman exec`. In
  productie is dat taboe. Je wijziging is weg bij de volgende deploy, en niemand kan zien wat er
  veranderd is. Wijzigingen gaan altijd via Git → pipeline → nieuw image. Stap 11 (weggooien en
  opnieuw maken) is wat er bij elke deploy gebeurt.
- **Dezelfde reflex, ander gereedschap:** `podman ps -a` → `podman logs` wordt op je werk
  `kubectl get pods` → `kubectl logs`, of je kijkt in de Argo CD-UI of in Grafana/Azure Monitor.
  Vaak heb je alleen leesrechten in je eigen namespace. Dat is genoeg om te debuggen.
- **`docker` in tutorials:** op internet en in documentatie staat bijna altijd `docker ...`. Met
  Podman typ je `podman ...`; commando's en opties zijn vrijwel hetzelfde.

---

## Checkpoint

<details>
<summary>1. Wat is het verschil tussen <code>podman run</code> en <code>podman start</code>?</summary>

`run` maakt een **nieuwe** container van een image en start die. `start` start een
**bestaande**, gestopte container opnieuw, inclusief de wijzigingen die erin zaten.
</details>

<details>
<summary>2. En tussen <code>podman run</code> en <code>podman exec</code>?</summary>

`run` maakt een nieuwe container. `exec` start een extra proces in een container die al
draait, bijvoorbeeld een shell om rond te kijken.
</details>

<details>
<summary>3. Je start <code>-p 3000:8080</code>. Welke poort open je in je browser, en op welke poort moet je app luisteren?</summary>

Browser: `localhost:3000`. App in de container: poort `8080`.
</details>

<details>
<summary>4. Waarom was je aangepaste index.html weg na <code>podman rm</code> + <code>podman run</code>?</summary>

Wijzigingen staan in de beschrijfbare laag van díe container. `rm` gooit de container
inclusief die laag weg. `run` maakt een nieuwe container vanaf het onveranderde image.
</details>

<details>
<summary>5. Wanneer stopt een container vanzelf?</summary>

Als zijn hoofdproces (PID 1) stopt, om welke reden dan ook.
</details>

<details>
<summary>6. Een container staat op <code>Exited (1)</code>. Wat zijn je eerste twee commando's?</summary>

`podman ps -a` (status en exitcode bekijken) en `podman logs <naam>` (lezen wat er misging).
</details>

### Eindopdracht

Ruim eerst op wat je in deze module hebt gemaakt. Dat doe je op naam, zodat containers van andere
projecten blijven staan:

```bash
podman ps -a                    # wat staat er nog?
podman rm -f -v snip-web snip-db   # -v: ruimt ook naamloze volumes op (zie module 02)
```

Doe daarna **zonder in het lab te kijken** het volgende (de spiekbrief hieronder mag je wel gebruiken).
De bestanden die je nodig hebt, staan klaar in de map [`bestanden/`](bestanden/).

1. Start een container **`snip-web`** van `nginx:alpine`, op de achtergrond, bereikbaar op
   <http://localhost:8080>.
2. Zet het klaargezette [`bestanden/index.html`](bestanden/index.html) in de container met
   **`podman cp`** (nieuw commando; zoek zelf uit hoe het werkt met `podman cp --help`). nginx
   serveert de bestanden uit `/usr/share/nginx/html/`.
3. Start een container **`snip-db`** van `postgres:18-alpine` met een database `snip`.
4. Vul de database met het klaargezette [`bestanden/links.sql`](bestanden/links.sql). Dat maakt
   de tabel `links` aan, met een paar rijen erin.

<details>
<summary>Hint bij stap 4</summary>

`podman exec` kan invoer van je Mac doorgeven aan een programma in de container. Daarvoor
gebruik je `-i` (wel invoer, maar geen terminal, dus géén `-t`) en `<` om een bestand als invoer te
gebruiken.
</details>

Controleer:

```bash
./check.sh
```

Groen? Dan beheers je de basis. In **module 02** laat je containers met elkaar praten
en zorg je dat je data een `podman rm` overleeft.

---

## Spiekbrief

| Commando | Wat het doet |
|---|---|
| `podman run IMAGE [CMD]` | nieuwe container maken en starten |
| `  -it` | interactief, met terminal |
| `  -d` | op de achtergrond (detached) |
| `  --name NAAM` | eigen naam geven |
| `  -p BUITEN:BINNEN` | poort publiceren |
| `  -e KEY=WAARDE` | environment variable |
| `  --rm` | automatisch opruimen na stoppen |
| `  --replace` | bestaande container met dezelfde naam vervangen (alleen Podman) |
| `podman ps` / `podman ps -a` | draaiende / alle containers |
| `podman logs [-f] NAAM` | logs bekijken (live met `-f`) |
| `podman exec -it NAAM sh` | shell in een draaiende container |
| `podman cp BRON DOEL` | bestanden kopiëren tussen Mac en container (`NAAM:/pad`) |
| `podman stop` / `start NAAM` | stoppen / opnieuw starten |
| `podman rm [-f] NAAM` | container verwijderen |
| `podman inspect NAAM` | alle details als JSON |
| `podman stats` | live CPU/geheugen |
| `podman images` | lokale images |
| `podman pull IMAGE` | image ophalen |
| `podman image history IMAGE` | layers van een image |
| `podman rmi IMAGE` | image verwijderen |
| `podman system df` | schijfgebruik |
| `podman container prune` | ⚠️ **alle** gestopte containers opruimen, ook die van andere projecten |
| `podman system prune` | ⚠️ alles opruimen wat niet in gebruik is |
