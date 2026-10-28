# Module 08 — Waarom Kubernetes, en je eerste cluster

**Doel:** je weet welk probleem Kubernetes oplost en hoe het in elkaar zit. Je maakt een
lokaal cluster op je Mac, praat ermee met `kubectl`, en draait je eigen `snip-api`-image als pod.

**Tijd:** ±2 uur

**Nodig:** deel 1 afgerond (`ghcr.io/bernardus/snip-api` staat publiek op GHCR)

> **Achtergrond:** een uitgebreide introductie tot Kubernetes (in het Engels), met alle
> onderdelen en objecttypes op een rij, staat in
> [`docs/kubernetes-introduction.md`](../../docs/kubernetes-introduction.md). Lees hem gerust
> vóór of na deze module, en pak hem erbij als een latere module iets nieuws introduceert.

`CKAD` Deze module dekt de basis van het CKAD-examen: pods, `kubectl run`, `describe`, `logs`,
`exec`, en YAML genereren met `--dry-run`.

---

## Uitleg

### Wat Compose niet kan

In module 06 en 07 draaide snip met Compose op één server. Dat werkt, maar alleen zolang die ene
server leeft, en zolang er iemand is die ingrijpt als er iets misgaat:

| Situatie | Compose | Kubernetes |
|---|---|---|
| server valt uit | snip is weg | containers verhuizen naar een andere server |
| nieuwe versie | even onbereikbaar | rolling update, zonder onderbreking |
| druk op de site | met de hand opschalen, op die ene server | `replicas: 3`, of automatisch |
| container start, maar werkt niet | blijft "Up" | wordt pas verkeer gestuurd als hij gezond is |
| hoe het werkt | doet één keer wat je zegt | **blijft controleren** en herstellen |

Dat laatste is het kernidee.

### Gewenste toestand: je beschrijft wát, niet hóe

Met Podman geef je **opdrachten**: "start deze container". Met Kubernetes geef je een
**beschrijving**: "er moeten altijd 3 van deze containers draaien". Kubernetes vergelijkt die
beschrijving continu met wat er werkelijk draait, en lost elk verschil op:

```
        ┌───────────────────────────────────────┐
        │  gewenst (jouw YAML):  3 × snip-api   │
        └──────────────────┬────────────────────┘
                           │ vergelijken
                           ▼
        ┌───────────────────────────────────────┐
        │  werkelijk:  2 × snip-api (1 crashte) │
        └──────────────────┬────────────────────┘
                           │ verschil → 1 starten
                           ▼
                     ... en opnieuw, en opnieuw
```

Dit heet de **reconciliation loop** ("gelijktrek-lus"). Die draait altijd. Daardoor herstelt
Kubernetes zichzelf, ook om 3 uur 's nachts.

### Hoe een cluster in elkaar zit

```
 jij
  │ kubectl apply -f snip.yaml
  ▼
┌──────────────────────── control plane ("het brein") ────────────────────────┐
│  API server          de enige ingang: alles en iedereen praat hiermee         │
│  etcd                de database waarin de gewenste en werkelijke stand staat │
│  scheduler           kiest op welke node een nieuwe pod komt                  │
│  controller manager  de gelijktrek-lussen: "er moeten 3 zijn, er zijn er 2"   │
└───────────────────────────────────┬──────────────────────────────────────────┘
                                    │
          ┌─────────────────────────┼─────────────────────────┐
          ▼                         ▼                         ▼
┌──── node 1 ─────┐       ┌──── node 2 ─────┐       ┌──── node 3 ─────┐
│ kubelet         │       │ kubelet         │       │ kubelet         │  zorgt dat de pods
│ container       │       │ container       │       │ container       │  op deze node
│ runtime         │       │ runtime         │       │ runtime         │  draaien
│  ├─ pod         │       │  ├─ pod         │       │  ├─ pod         │
│  └─ pod         │       │  └─ pod         │       │  └─ pod         │
└─────────────────┘       └─────────────────┘       └─────────────────┘
```

| Onderdeel | Waar | Wat het doet |
|---|---|---|
| **API server** | control plane | voordeur van het cluster; `kubectl` praat alleen hiermee |
| **etcd** | control plane | slaat alles op wat het cluster weet |
| **scheduler** | control plane | kiest een node voor elke nieuwe pod |
| **controller manager** | control plane | voert de gelijktrek-lussen uit |
| **kubelet** | elke node | ontvangt "draai deze pod" en zorgt dat het gebeurt |
| **container runtime** | elke node | start echt de containers (*containerd* of *CRI-O*, geen Docker of Podman) |
| **kube-proxy** | elke node | regelt het netwerkverkeer naar pods (module 10) |

Op AKS beheert Microsoft de control plane. Jij (of het platformteam) ziet alleen de nodes.

### De pod: de kleinste eenheid

Kubernetes draait geen losse containers, maar **pods**. Een pod is een groepje van één of meer
containers die:
- **dezelfde `localhost`** delen (één netwerk, één IP-adres);
- samen op dezelfde node staan, en samen starten en stoppen.

Meestal zit er **één** container in een pod: je app. Soms komt er een kleine helper bij, een
*sidecar*. Een database zet je **niet** in dezelfde pod als je app (je weet nog waarom: apart
schalen, apart updaten).

Weet je nog dat `localhost` altijd "de container zelf" is? In een pod is het preciezer: "de pod
zelf". Containers in dezelfde pod bereiken elkaar via `localhost`.

Podman kent pods ook, en daarmee begint het lab.

### Een cluster op je Mac: kind

Een echt cluster bestaat uit meerdere servers. Om te leren gebruiken we **kind** ("Kubernetes in
Docker", werkt ook met Podman). Dat zet een complete Kubernetes-node in **één container**:

```
 je Mac
 └─ podman machine (Linux-VM)
     └─ container "snip-control-plane"    ← dit is je hele cluster: control plane + node
         └─ containerd
             ├─ pod: etcd, API server, scheduler, ...
             └─ pod: jouw snip-api
```

Containers in een container in een VM. Klinkt gek, maar voor Kubernetes is dat gewoon een node.
Alles wat je hier leert, werkt op AKS precies hetzelfde.

---

## Lab

### Deel A — Pods in Podman: het bruggetje

**1. Een pod met twee containers**

```bash
podman pod create --name demo -p 8085:80
podman run -d --pod demo --name demo-web nginx:alpine
podman run -d --pod demo --name demo-kijker alpine \
  sh -c 'while true; do wget -qO- localhost:80 | grep -o "<title>.*</title>"; sleep 3; done'
```

Let op: `-p` staat bij de **pod**, niet bij de container. Alle containers in de pod delen één
netwerk.

```bash
podman logs demo-kijker
```

`<title>Welcome to nginx!</title>`. De `demo-kijker` vraagt `localhost:80`, en krijgt nginx: een
**andere** container. In een pod delen ze hun `localhost`.

```bash
podman pod ps
podman ps --pod --filter pod=demo
```

De pod heeft **drie** containers: jouw twee, plus een kleine `infra`-container die het gedeelde
netwerk vasthoudt. (Kubernetes doet hetzelfde; daar heet hij de *pause*-container.)

> Zie je ook een pod `pod_snip`? Die maakte podman-compose in module 04 stilletjes aan: het zet
> alle services van een project in één pod. Laat hem staan.

**2. Van Podman naar Kubernetes-YAML**

```bash
mkdir -p ~/Documents/local/docker-k8s-cursus/k8s
cd ~/Documents/local/docker-k8s-cursus/k8s
podman kube generate demo > demo-pod.yaml
cat demo-pod.yaml
```

Dit is een **Kubernetes-manifest**: een beschrijving van een pod, in het formaat dat Kubernetes
begrijpt. Podman schreef het voor je. Herken je `kind: Pod`, `containers`, `image`, `ports`?

En Podman kan het ook weer lezen:

```bash
podman pod rm -f demo
podman kube play demo-pod.yaml
curl -s localhost:8085 | grep -o "<title>.*</title>"
podman kube down demo-pod.yaml
```

Eén bestand, en alles staat er weer. Dat is de manier van werken in Kubernetes. Gooi het bestand
weg; we schrijven straks onze eigen manifests:

```bash
rm demo-pod.yaml
```

### Deel B — Een cluster

**3. kind installeren, en kubectl bijwerken**

```bash
brew install kind
brew upgrade kubernetes-cli
```

kind moet weten dat het Podman moet gebruiken in plaats van Docker. Zet dat in je shell:

```bash
echo 'export KIND_EXPERIMENTAL_PROVIDER=podman' >> ~/.zshrc
exec zsh -l
```

Controleer:

```bash
kind version
kubectl version --client
```

> **Waarom kubectl bijwerken?** `kubectl` mag maximaal één versie verschillen van het cluster. kind
> start Kubernetes 1.37; met een oudere `kubectl` krijg je waarschuwingen en vreemde fouten.

**4. Het cluster maken**

```bash
kind create cluster --name snip
```

Dit duurt ongeveer een minuut. kind haalt een image op met een complete Kubernetes-node, en
start het als container. Daarna:

```bash
podman ps --filter name=snip-control-plane
```

Daar is je cluster: één container.

**5. Met welk cluster praat kubectl?**

```bash
kubectl config get-contexts
kubectl config current-context
```

`kubectl` kan met meerdere clusters praten. Elk cluster is een **context**, en die staan in
`~/.kube/config`. kind heeft `kind-snip` toegevoegd en actief gemaakt (het sterretje).

> **Altijd eerst kijken waar je bent.** Zie je hier ook clusters van je werk? Dan is dit de
> belangrijkste gewoonte van deze module: kijk vóór elk `apply` of `delete` naar je context.
> Hetzelfde commando op het verkeerde cluster is een klassieke ramp.

**6. Rondkijken**

```bash
kubectl cluster-info
kubectl get nodes -o wide
```

Eén node, `snip-control-plane`, status `Ready`. Kijk naar `CONTAINER-RUNTIME`: **containerd**.
Kubernetes gebruikt Docker noch Podman (module 00).

```bash
kubectl get pods -A
```

`-A` betekent: in **alle namespaces**. Dit zijn de onderdelen uit de uitleg, zelf draaiend als
pods in de namespace `kube-system`:

| Pod | Is |
|---|---|
| `etcd-...` | de database |
| `kube-apiserver-...` | de API server |
| `kube-scheduler-...` | de scheduler |
| `kube-controller-manager-...` | de gelijktrek-lussen |
| `coredns-...` | DNS: namen zoals `snip-db` (module 10) |
| `kube-proxy-...` | netwerkverkeer naar pods |
| `kindnet-...` | het netwerk tussen pods (specifiek voor kind) |
| `local-path-provisioner-...` | opslag voor volumes (module 12) |

### Deel C — Je eerste pods

**7. Een pod starten, de snelle manier**

```bash
kubectl run hallo --image=nginx:alpine
kubectl get pods --watch
```

Je ziet `ContainerCreating` en daarna `Running`. Stop het meekijken met `Ctrl+C`.

**8. Wat gebeurde er?**

```bash
kubectl describe pod hallo
```

Scrol naar **Events** onderaan. Daar zie je de reis langs alle onderdelen:

| Event | Wie | Wat |
|---|---|---|
| `Scheduled` | scheduler | "deze pod gaat naar node `snip-control-plane`" |
| `Pulling` / `Pulled` | kubelet | image ophalen |
| `Created` / `Started` | kubelet | container gemaakt en gestart |

`kubectl describe` en de Events zijn je eerste stop bij elk probleem. Dat is de Kubernetes-versie
van `podman ps -a` + `podman logs`.

**9. Vertrouwde commando's**

```bash
kubectl logs hallo
kubectl exec -it hallo -- sh
```

In de pod:

```sh
hostname      # de naam van de pod
exit
```

Let op de `--` bij `exec`: alles daarna is het commando voor in de container.

**10. Er zelf bij kunnen**

```bash
kubectl port-forward pod/hallo 8086:80
```

Open <http://localhost:8086>: nginx, vanuit je cluster. `port-forward` maakt een tijdelijke
tunnel van je Mac naar een pod. Handig om te testen; echte toegang regel je in module 10.
`Ctrl+C` stopt de tunnel.

**11. Een pod is sterfelijk**

```bash
kubectl delete pod hallo
kubectl get pods
```

Weg, en hij komt niet terug. Een losse pod wordt niet bewaakt door een gelijktrek-lus. Dat
doet een **Deployment**, en dat is module 09. In de praktijk maak je daarom bijna nooit losse
pods. We doen het hier om de bouwsteen te leren kennen.

### Deel D — Je eigen image, met een manifest

**12. YAML laten genereren**

YAML uit je hoofd schrijven hoeft niet. Laat `kubectl` het begin maken:

```bash
kubectl run snip-api --image=ghcr.io/bernardus/snip-api:latest --port=3000 \
  --dry-run=client -o yaml
```

`--dry-run=client` betekent: niets aanmaken, alleen laten zien. `-o yaml`: als YAML. Dit is dé
truc voor het CKAD-examen.

**13. Het manifest**

Maak `k8s/snip-api-pod.yaml` (in de hoofdmap van de cursus):

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: snip-api
  labels:
    app: snip-api
spec:
  containers:
    - name: api
      image: ghcr.io/bernardus/snip-api:latest
      ports:
        - containerPort: 3000
```

Elk Kubernetes-manifest heeft dezelfde vier delen:

| Veld | Wat |
|---|---|
| `apiVersion` | welke versie van de Kubernetes-API dit type beschrijft |
| `kind` | wat het is: `Pod`, `Deployment`, `Service`, ... |
| `metadata` | naam en **labels** (etiketten, daar zoeken andere onderdelen straks op) |
| `spec` | de gewenste toestand: wat er moet draaien |

**14. Toepassen**

```bash
cd ~/Documents/local/docker-k8s-cursus
kubectl apply -f k8s/snip-api-pod.yaml
kubectl get pods
```

Wacht tot `Running`. Pas het nog een keer toe:

```bash
kubectl apply -f k8s/snip-api-pod.yaml
```

`pod/snip-api unchanged`. Je beschrijft een **toestand**, geen opdracht. Is de toestand al zo,
dan hoeft er niets te gebeuren. Zo kun je `apply` veilig vaak uitvoeren.

**15. Werkt het?**

```bash
kubectl exec snip-api -- node -e "fetch('http://localhost:3000/api/info').then(r => r.text()).then(console.log)"
kubectl exec snip-api -- node -e "fetch('http://localhost:3000/health/db').then(r => r.text()).then(console.log)"
```

De API draait, met de versie uit je pipeline, en `"container":"snip-api"`: de naam van de pod. Maar
`/health/db` zegt `onbereikbaar`: er is nog geen database in het cluster. Die komt in module 12.

**16. Gewenst tegenover werkelijk**

```bash
kubectl get pod snip-api -o yaml | less
```

Bovenaan staat `spec`: wat jij vroeg. Onderaan staat `status`: wat Kubernetes ervan maakte
(IP-adres, op welke node, wanneer gestart). Precies die twee vergelijkt Kubernetes steeds.
(`q` om te sluiten.)

**17. De ingebouwde handleiding**

```bash
kubectl explain pod.spec.containers
kubectl explain pod.spec.containers.ports
```

Elk veld van elk type staat hierin, met uitleg. Op het CKAD-examen mag je geen internet
gebruiken, maar dit wel.

---

## Breek het

### 💥 1. Een tikfout in het image

```bash
kubectl run tikfout --image=nginx:alpne
kubectl get pods --watch
```

<details>
<summary>Hint</summary>

Na `ErrImagePull` komt `ImagePullBackOff`. Wat zeggen de Events?
</details>

<details>
<summary>Uitleg</summary>

```bash
kubectl describe pod tikfout
```

Onder Events: `failed to pull and unpack image "docker.io/library/nginx:alpne": ... not found`.
Het image bestaat niet. Kubernetes blijft het proberen, met steeds langere pauzes: de
**BackOff**. Typt iemand later de goede naam in, dan herstelt het zichzelf. Het geeft dus nooit
helemaal op.

`ImagePullBackOff` is een van de meest voorkomende foutmeldingen. Mogelijke oorzaken:
- een tikfout in de naam of de tag;
- het image is privé en het cluster mag het niet ophalen;
- het image bestaat niet voor de architectuur van de node.

```bash
kubectl delete pod tikfout
```
</details>

### 💥 2. Een container die steeds crasht

```bash
kubectl run crash --image=alpine -- sh -c "echo doei; exit 1"
kubectl get pods --watch
```

<details>
<summary>Uitleg</summary>

Je ziet `Error`, dan `CrashLoopBackOff`, en de kolom `RESTARTS` loopt op. De container start,
stopt meteen met een fout, en Kubernetes start hem opnieuw, met steeds langere pauzes.

Wat zei hij voor hij stopte?

```bash
kubectl logs crash
kubectl logs crash --previous
```

`--previous` laat de logs van de **vorige**, gecrashte poging zien. Dat is vaak de enige plek waar
de echte fout staat.

Herken je module 01? `podman ps -a` → `podman logs` is nu `kubectl get pods` → `kubectl describe` →
`kubectl logs (--previous)`. Hetzelfde denkpatroon, zoals beloofd.

```bash
kubectl delete pod crash
```
</details>

### 💥 3. Het verkeerde cluster

```bash
kubectl config get-contexts
```

<details>
<summary>Uitleg</summary>

Staat er meer dan `kind-snip`, bijvoorbeeld een oude `docker-desktop` of een cluster van je werk?
Elk `kubectl`-commando gaat naar de context met het sterretje. Deze cursus gebruikt alleen
`kind-snip`.

Wissel bewust met:

```bash
kubectl config use-context kind-snip
```

Veel mensen zetten de huidige context in hun prompt, of gebruiken het hulpje `kubectx`, om nooit
te vergeten waar ze zijn. Bij `oh-my-zsh` (dat jij hebt) kan dat met de plugin `kube-ps1`.
</details>

---

## Op je werk

- **Toegang tot AKS** krijg je met `az aks get-credentials`. Dat voegt een context toe aan je
  `~/.kube/config`. Inloggen gaat dan via Entra ID (met `kubelogin`), en je rechten hangen af van
  je groepen. Vaak mag je in productie alleen kijken.
- **Je doet geen `kubectl apply` op productie.** Daar zorgt Argo CD voor (deel 3). `kubectl` gebruik
  je om te **kijken en debuggen**: `get`, `describe`, `logs`. Hoe goed je die beheerst, bepaalt hoe
  snel je een probleem vindt.
- **Losse pods zie je niet.** Alles draait via Deployments of StatefulSets (module 09 en 12). De
  pods die je ziet, hebben namen als `snip-api-7d4f9c-x2k8p`: gemaakt door een Deployment.
- **Namespaces.** Op een gedeeld cluster zit elk team in eigen namespaces (module 15). Vergeet
  dan niet `-n mijn-namespace`, of je kijkt in `default` en ziet niets.

---

## Checkpoint

<details>
<summary>1. Wat is het grootste verschil tussen hoe Compose en hoe Kubernetes werkt?</summary>

Compose voert één keer een opdracht uit. Kubernetes krijgt een gewenste toestand en blijft die
continu vergelijken met de werkelijkheid en verschillen herstellen (de reconciliation loop).
</details>

<details>
<summary>2. Wat doen de API server, etcd, de scheduler en de kubelet?</summary>

API server: de enige ingang. etcd: de opslag van alles. Scheduler: kiest een node voor een pod.
Kubelet: zorgt op een node dat de pods echt draaien.
</details>

<details>
<summary>3. Wat delen containers in dezelfde pod?</summary>

Hun netwerk (`localhost` en het IP-adres), en ze staan altijd samen op dezelfde node.
</details>

<details>
<summary>4. Je verwijdert een losse pod. Komt hij terug?</summary>

Nee. Een losse pod wordt niet bewaakt. Daarvoor heb je een Deployment nodig.
</details>

<details>
<summary>5. Wat betekent <code>pod/snip-api unchanged</code> na <code>kubectl apply</code>?</summary>

Dat de gewenste toestand al overeenkomt met wat er draait. `apply` beschrijft een toestand, en
als die al klopt, gebeurt er niets.
</details>

<details>
<summary>6. Een pod staat op <code>ImagePullBackOff</code>. Waar kijk je eerst?</summary>

`kubectl describe pod <naam>`, bij de Events. Daar staat waarom het ophalen mislukte.
</details>

<details>
<summary>7. Een pod staat op <code>CrashLoopBackOff</code>. Welke commando's?</summary>

`kubectl describe pod <naam>`, en `kubectl logs <naam> --previous` voor de logs van de gecrashte
poging.
</details>

### Eindopdracht

Ruim de oefenpods op (`hallo`, `tikfout`, `crash`), maar laat `snip-api` staan:

```bash
kubectl delete pod hallo tikfout crash --ignore-not-found
```

Zorg dat:
1. het kind-cluster **`snip`** draait, en `kind-snip` je actieve context is;
2. de pod **`snip-api`** draait, gemaakt met `kubectl apply -f k8s/snip-api-pod.yaml`, met je
   image uit GHCR en het label `app: snip-api`.

```bash
cd ~/Documents/local/docker-k8s-cursus/modules/08-kubernetes-basis
./check.sh
```

Groen? In **module 09** vervang je de losse pod door een **Deployment**: drie kopieën die
zichzelf herstellen, en updates zonder onderbreking.

> **Je Mac herstart, of je zet de podman machine uit?** Dan staat het cluster ook uit. Starten:
> `podman machine start` en daarna `podman start snip-control-plane`. Geef het een halve minuut,
> en controleer met `kubectl get nodes`.

---

## Spiekbrief

| Commando | Wat het doet |
|---|---|
| `kind create cluster --name NAAM` | cluster maken |
| `kind delete cluster --name NAAM` | cluster weggooien |
| `kubectl config get-contexts` | alle clusters; `*` = actief |
| `kubectl config use-context NAAM` | wisselen van cluster |
| `kubectl get nodes` / `get pods` / `get pods -A` | lijst (`-A`: alle namespaces) |
| `kubectl get pods --watch` | live meekijken |
| `kubectl get pod NAAM -o yaml` | alles over een pod, als YAML |
| `kubectl describe pod NAAM` | details + **Events** |
| `kubectl logs NAAM [--previous]` | logs (van de vorige poging) |
| `kubectl exec -it NAAM -- sh` | shell in de pod |
| `kubectl port-forward pod/NAAM 8086:80` | tijdelijke tunnel van je Mac naar de pod |
| `kubectl run NAAM --image=IMG` | snel een pod starten |
| `kubectl run ... --dry-run=client -o yaml` | YAML genereren, zonder iets te maken |
| `kubectl apply -f BESTAND` | gewenste toestand toepassen |
| `kubectl delete pod NAAM` / `-f BESTAND` | verwijderen |
| `kubectl explain TYPE.VELD` | ingebouwde handleiding |
| `podman kube generate POD` / `kube play BESTAND` | Podman-pod ↔ Kubernetes-YAML |

**CKAD-tip:** zet `alias k=kubectl` in je `~/.zshrc`. Op het examen typ je honderden keren
`kubectl`.
