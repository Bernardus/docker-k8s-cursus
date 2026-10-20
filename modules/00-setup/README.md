# Module 00 — Setup & denkmodel

**Doel:** je snapt wat een container is (en wat niet), Podman draait op je Mac en je
weet wat er gebeurt als je `podman run` typt.

**Tijd:** ±45 minuten

---

## Uitleg

### Het probleem: "werkt op mijn machine"

Je API draait lokaal prima. Op de server niet, want daar staat Node 20 in plaats van 24,
een andere versie van OpenSSL en Postgres 15 in plaats van 18, en een collega heeft een
environment variable vergeten. De code is hetzelfde, maar **de omgeving** is anders.

Een container lost dat op door de omgeving mee te verpakken: Node zelf, je `node_modules`,
de systeembibliotheken en de configuratie. Alles zit in één pakket dat overal hetzelfde draait.

### Wat is een container?

Een container is **een gewoon Linux-proces met oogkleppen op**. De Linux-kernel geeft dat
proces:

- **een eigen bestandssysteem**: het ziet alleen de bestanden uit zijn image, niet die van de host
- **een eigen proceslijst**: het denkt dat het proces nummer 1 is
- **een eigen netwerk**: eigen IP-adres en eigen poorten
- **grenzen**: maximaal zoveel CPU en geheugen

(De technische termen zijn *namespaces* voor de oogkleppen en *cgroups* voor de grenzen. Die
hoef je nu niet te kennen, maar je komt ze tegen.)

Een container is dus **geen virtuele machine**. Een VM emuleert een complete computer met
een eigen kernel. Containers delen de kernel van de host en zijn daardoor in milliseconden
gestart en maar megabytes groot.

```
     Virtuele machines                       Containers
┌─────────┐ ┌─────────┐ ┌─────────┐    ┌─────────┐ ┌─────────┐ ┌─────────┐
│  app A  │ │  app B  │ │  app C  │    │  app A  │ │  app B  │ │  app C  │
│  libs   │ │  libs   │ │  libs   │    │  libs   │ │  libs   │ │  libs   │
│ kernel  │ │ kernel  │ │ kernel  │    └────┬────┘ └────┬────┘ └────┬────┘
│ (gast)  │ │ (gast)  │ │ (gast)  │         └───────────┼───────────┘
└────┬────┘ └────┬────┘ └────┬────┘         ┌───────────▼───────────┐
┌────▼───────────▼───────────▼────┐         │ container-engine      │
│          hypervisor             │         │ (Podman, Docker, ...) │
├─────────────────────────────────┤         ├───────────────────────┤
│        host-hardware            │         │ host-kernel (Linux)   │
└─────────────────────────────────┘         └───────────────────────┘
   seconden om te starten, GB's                ms om te starten, MB's
```

### Image, container, registry: vertaald naar JavaScript

| Begrip | Vergelijk met | Wat het is |
|---|---|---|
| **Image** | een gepubliceerd npm-pakket | Een *read-only* snapshot: bestandssysteem plus het commando dat moet starten. Verandert nooit meer. |
| **Container** | een draaiend `node`-proces | Een *draaiende instantie* van een image, met een eigen beschrijfbare laag erbovenop. Je kunt er tien starten van hetzelfde image. |
| **Registry** | de npm-registry | Opslag voor images. Docker Hub is de bekendste; later gebruiken we ook GHCR (GitHub) en ACR (Azure). |
| **Tag** | een versie (`^24.1.0`) | Label op een image, bijv. `node:24-alpine`. `latest` is gewoon een tag, géén garantie dat het de nieuwste is. |
| **Dockerfile** | een build-script | Recept om een image te bouwen (module 03). Podman noemt het ook wel `Containerfile`. |

Een image is een class, een container een `new`-instantie. Een image verandert nooit, een
container kan dat wel, maar alleen zolang die container bestaat. (Dat laatste komt in module 01 nog
pijnlijk terug.)

### Docker, Podman en "Docker-images"

**Docker** heeft containers populair gemaakt. Het image-formaat en de Dockerfile zijn daarna
een open standaard geworden: **OCI** (Open Container Initiative). Daardoor zijn er nu meerdere
tools die dezelfde images bouwen en draaien:

- **Podman** (open source, van Red Hat): wat jij gebruikt. Bijna alle commando's zijn
  hetzelfde als bij Docker: `podman run` doet wat `docker run` doet.
- **Kubernetes** gebruikt zelf Docker noch Podman, maar *containerd* of *CRI-O*. Die draaien
  wel precies dezelfde OCI-images. Een image dat je met Podman bouwt, draait dus overal.

De cursus heet "Docker & Kubernetes" omdat "Docker" het woord voor het concept is geworden.
In tutorials en documentatie zie je overal `docker ...`. Typ dan gewoon `podman ...`.

De verschillen die je gaat merken:

| | Docker | Podman |
|---|---|---|
| Op de achtergrond | één centrale *daemon* (dockerd) die als root alle containers beheert | **geen daemon**: elke container is een gewoon proces, bewaakt door een klein hulpje (`conmon`) |
| Rootless (zonder root draaien) | optioneel | standaard |
| Pods | nee | **ja**: groepjes containers, net als in Kubernetes (zie module 08) |
| Korte image-namen (`nginx`) | betekent altijd Docker Hub | wordt aangevuld via een lijst bekende namen (zie module 01) |
| Compose | ingebouwd | via een aparte *compose provider* (zie module 04) |

### Podman op een Mac: er zit een Linux-VM tussen

Containers hebben een **Linux-kernel** nodig, en macOS is geen Linux. Podman start daarom
een kleine Linux-VM, de **podman machine**, en daarin draaien je containers. Het
`podman`-commando in je terminal is op de Mac een *client* die via SSH opdrachten doorstuurt
naar Podman in die VM:

```
  jouw Mac                                  Linux-VM ("podman machine")
┌──────────────────────┐   SSH + API   ┌──────────────────────────────────────────┐
│ $ podman run nginx   │ ────────────► │  Podman                                  │
│   (CLI = client)     │               │    ├──► conmon ──► container: nginx      │
└──────────────────────┘               │    └──► conmon ──► container: postgres   │
                                       └──────────────────────────────────────────┘
        Podman Desktop = een grafische schil om ditzelfde geheel
```

Daarom toont `podman version` straks twee blokken: **Client** (op je Mac) en **Server** (in
de VM). En daarom zie je in een container `Linux` als je `uname` typt, ook al zit je op een
Mac.

Nog iets dat later belangrijk wordt: jouw Mac heeft een **ARM-chip** (`arm64`), veel servers
draaien op **Intel/AMD** (`amd64`). Een image is gebouwd voor één of meer architecturen. Daar
komen we op terug als we gaan deployen.

### En Kubernetes?

Podman start containers op **één machine**. Kubernetes regelt containers over **een heel
cluster van machines**: jij beschrijft *wat* je wilt ("3 kopieën van de api, altijd"), en
Kubernetes zorgt dat het zo blijft. Crasht er een, dan start het een nieuwe. Valt een server
weg, dan verhuist het de containers. Maar eerst moet je containers zelf goed snappen. Daarom
komen containers eerst.

---

## Lab

### Stap 1: Is Podman er?

Podman Desktop en het `podman`-commando staan al op je Mac. Open een **nieuwe** terminal en typ:

```bash
podman --version
```

`command not found`? Het commando staat in `/opt/podman/bin`, en een nieuwe terminal pakt dat
normaal vanzelf op. Lukt het dan nog niet, open dan Podman Desktop. Dat ziet zelf dat Podman
ontbreekt en biedt aan het te installeren.

### Stap 2: De machine (de Linux-VM)

```bash
podman machine list
```

Je ziet je machine, met onder meer:

- `VM TYPE`: de virtualisatietechniek van macOS die gebruikt wordt (`libkrun` of `applehv`)
- `CPUS` en `MEMORY`: hoeveel de VM van je Mac mag gebruiken
- `LAST UP`: wanneer hij voor het laatst draaide

Staat er geen machine? Maak er dan een met `podman machine init`. Start hem:

```bash
podman machine start
```

Dat kan ook met de knop in Podman Desktop. Voor deel 1 is 4 GB geheugen genoeg. In module 08
geven we hem meer, omdat Kubernetes meer geheugen nodig heeft.

> **Rootless of rootful?** Een machine draait containers standaard *rootless*, dus als gewone
> gebruiker in de VM. Dat is veiliger. *Rootful* draait ze als root, wat sommige tools nodig
> hebben (bijv. lokaal Kubernetes in module 08). Wat jouw machine doet, zie je met
> `podman machine inspect --format '{{.Rootful}}'`. Voor deel 1 maakt het niet uit.

### Stap 3: Client én server?

```bash
podman version
```

Je ziet een blok **Client** en een blok **Server**. Kijk bij beide naar `OS/Arch`:

- Client: `darwin/arm64`, de CLI op je Mac
- Server: `linux/arm64`, Podman in de Linux-VM

Krijg je een fout als `Cannot connect to Podman`? Dan draait de machine niet (stap 2).

### Stap 4: Met welke machine praat je CLI?

```bash
podman system connection list
```

Je CLI kan met meerdere machines of verbindingen praten. De kolom `Default` laat zien welke hij nu
gebruikt. Bij een rootful machine zie je er twee: `podman-machine-default` (rootless) en
`podman-machine-default-root` (rootful).

> **Onthoud dit.** Containers die je via de ene verbinding start, zijn via de andere
> **onzichtbaar**. Denk je ooit "waar zijn mijn containers gebleven?", kijk dan eerst hier.
> Wisselen doe je met `podman system connection default <naam>`.

### Stap 5: Je eerste container

```bash
podman run hello-world
```

Je ziet een zeehond en `Hello Podman World`. Dit gebeurde er:

1. Het `podman`-commando op je Mac nam contact op met **Podman in de machine**.
2. Podman zag dat het image er nog niet was en **haalde het op** (een *pull*). Kijk naar de eerste
   regel: `Trying to pull quay.io/podman/hello:latest`. Jouw korte naam `hello-world` is
   aangevuld tot een volledige naam, en wel bij een andere registry dan je misschien dacht:
   Quay.io van Red Hat.
3. Podman **maakte een container** van dat image en startte het programma erin.
4. De **output** werd teruggestuurd naar jouw terminal, en daarna stopte de container.

Draai het commando nog een keer. Valt je iets op? Er staat geen `Trying to pull` meer, want
het image staat nu lokaal in de cache.

Draai nu het test-image van Docker, met de **volledige** naam:

```bash
podman run docker.io/library/hello-world
```

Nu staat er `Hello from Docker!`. Omdat images een standaard zijn, draait het image van Docker
gewoon op Podman. De tekst heeft het over een "Docker daemon", maar die is er bij Podman niet.

> **Les:** dezelfde korte naam (`hello-world`) kan bij verschillende tools een ander image
> opleveren. Daarom schrijf je in pipelines en op je werk altijd de volledige naam. Meer
> hierover in module 01.

### Stap 6: Rondkijken

```bash
podman info
```

Dat is veel informatie. Zoek de regels `arch`, `cpus`, `memTotal` en `rootless`. Zoveel heeft de
Linux-VM van je Mac gekregen.

```bash
podman compose version
```

Krijg je hier een foutmelding (`looking up compose provider failed`)? Dat klopt. Compose richten
we pas in module 04 in.

### Stap 7: Overige tools

| Tool | Waarvoor | Vanaf |
|---|---|---|
| `node` 24, `npm` | de app bouwen en lokaal draaien | module 03 |
| `git`, `gh` | versiebeheer, GitHub (CI/CD, GHCR) | module 05 |
| `kubectl` | praten met Kubernetes | module 08 |

Ze staan al op je Mac. Een tool voor een lokaal Kubernetes-cluster (kind of minikube, allebei
werken met Podman) kiezen we in module 08.

> **Tip:** veel mensen zetten `alias docker=podman` in hun shell, zodat tutorials 1-op-1
> werken. Voor deze cursus raad ik aan om `podman` te typen. Dan weet je altijd wat je
> gebruikt.

---

## Op je werk

- **Waarom Podman?** In enterprises is Podman populair. Er zijn geen licentiekosten (Docker
  Desktop is betaald vanaf 250 medewerkers), er draait geen root-daemon (beter voor security),
  en het komt uit de Red Hat/OpenShift-wereld. Dat je op je werk Podman moet gebruiken, is dus
  heel normaal.
- **Lokaal vs. productie:** op je werk gebruik je containers op je laptop om te ontwikkelen
  en te testen. Wat in productie draait, start niemand met de hand. Dat gaat via de centrale
  pipeline en Argo CD (deel 3 en 5).
- **Architectuur:** de meeste bedrijfsclusters (ook AKS) draaien op `amd64`, jouw Mac op
  `arm64`. Een image dat je lokaal bouwt, draait daar dus niet zomaar. Daarom bouwt de pipeline
  de images en niet jij. Daar komen we in module 05 op terug.
- **Bedrijfsnetwerk:** werkt het ophalen van images niet op een beheerde Mac (time-outs,
  certificaatfouten)? Dan gebruikt je bedrijf waarschijnlijk een proxy of een eigen
  registry-mirror. Vraag IT om de juiste instellingen in plaats van eromheen te werken.

---

## Checkpoint

Probeer eerst zelf te antwoorden, klap dan open.

<details>
<summary>1. Wat is het verschil tussen een image en een container?</summary>

Een image is een read-only sjabloon (bestandssysteem plus startcommando). Een container is een
draaiende instantie ervan, met een eigen beschrijfbare laag. Van één image kun je veel
containers starten.
</details>

<details>
<summary>2. Waarom draait er een Linux-VM op je Mac als je Podman gebruikt?</summary>

Containers zijn Linux-processen die de kernel van de host delen. macOS heeft geen
Linux-kernel, dus Podman levert er een in een lichte VM: de podman machine.
</details>

<details>
<summary>3. Een collega zegt: "een container is gewoon een lichte VM". Klopt dat?</summary>

Niet helemaal. Een VM heeft een eigen kernel en emuleert hardware. Een container is een
afgeschermd proces dat de kernel van de host deelt. Daardoor start het veel sneller en is
het veel kleiner, maar het is ook minder strikt geïsoleerd.
</details>

<details>
<summary>4. Wat is het belangrijkste verschil tussen Docker en Podman?</summary>

Docker gebruikt een centrale daemon die alle containers beheert. Podman heeft geen daemon:
containers zijn gewone processen, standaard zonder root. Images, Dockerfiles en de meeste
commando's zijn hetzelfde.
</details>

<details>
<summary>5. Je weet zeker dat je een container hebt gestart, maar <code>podman ps</code> laat niks zien. Wat check je?</summary>

`podman system connection list`. Misschien heb je de container via de rootful verbinding
gestart en kijk je nu via de rootless verbinding, of andersom.
</details>

### Eindcontrole

```bash
./check.sh
```

Alles groen? Door naar **[Module 01 — Eerste containers](../01-eerste-containers/)**.

---

## Spiekbrief

```bash
podman --version                       # is podman er?
podman machine list                    # welke machines (VM's) zijn er?
podman machine start / stop            # machine aan/uit
podman machine inspect                 # details, o.a. Rootful
podman version                         # client + server info
podman info                            # details over de engine in de VM
podman system connection list          # met welke machine/verbinding praat de CLI?
podman system connection default NAAM  # wissel van verbinding
podman run hello-world                 # rooktest
```
