# Module 08 — Je eerste Kubernetes-cluster

**Doel:** je weet welk probleem Kubernetes oplost, je maakt een lokaal cluster, en je draait je
eigen `snip-api`-image erin.

**Tijd:** ±1¼ uur

**Nodig:** deel 1 afgerond (`ghcr.io/bernardus/snip-api` staat publiek op GHCR)

> **Achtergrond:** de uitgebreide introductie (Engels) staat in
> [`docs/kubernetes-introduction.md`](../../docs/kubernetes-introduction.md). Niet nodig voor
> deze module.

> 🖥️ **Podman Desktop:** alles doe je in de terminal. Waar het handig is, staat een blokje zoals
> dit: daar kun je hetzelfde ook bekijken in Podman Desktop. Ter controle, niet in plaats van.
> (Menunamen kunnen per versie iets verschillen.)

---

## Uitleg

### Eén idee: je beschrijft wát, niet hóe

Met Podman en Compose geef je **opdrachten**: "start deze container". Dat gebeurt één keer.
Crasht de server, dan doet niemand iets.

Met Kubernetes geef je een **beschrijving**: "deze container moet draaien". Kubernetes blijft
die beschrijving vergelijken met wat er echt draait, en herstelt elk verschil. Ook om 3 uur
's nachts.

```
  jouw YAML (gewenst)  ──vergelijken──▶  wat er draait (werkelijk)
          ▲                                      │
          └──────────── verschil? herstellen ◀───┘
```

Dat is het hele idee. De rest van deel 2 is variaties hierop.

### Een cluster: brein en werkers

```
 jij ── kubectl ──▶  control plane (het brein)
                     onthoudt wat je wilt, en beslist waar het draait
                            │
              ┌─────────────┼─────────────┐
              ▼             ▼             ▼
            node          node          node      (de werkers: draaien je containers)
```

`kubectl` is je enige gereedschap. Het praat altijd met het brein, nooit direct met een node.
De onderdelen van het brein zie je straks in het lab.

### De pod

Kubernetes draait geen losse containers maar **pods**. Een pod is een verpakking om meestal
**één** container heen. Zie het voorlopig als "een container, met een Kubernetes-jasje aan".

(Er kunnen meerdere containers in één pod. Die delen dan `localhost`. Dat heb je nu nog niet
nodig.)

### Een cluster op je Mac: kind

De machines in een cluster heten **nodes**. Er zijn twee soorten:
- **control plane nodes**: het brein. In productie meestal 3, zodat het cluster blijft werken
  als er één uitvalt;
- **worker nodes**: hier draaien je apps.

**kind** ("Kubernetes in Docker", werkt ook met Podman) maakt een cluster met **één node**, die
brein én werker tegelijk is. Die node is een Podman-container:

```
 je Mac
 └─ podman machine (Linux-VM)                  ← Podman
     └─ container "snip-control-plane"         ← Podman: dit is je node
         ├─ API server, etcd, scheduler, ...   ← echte Kubernetes: het brein
         ├─ kubelet + containerd               ← echte Kubernetes: de werker
         └─ pod: snip-api                      ← gestart door Kubernetes, niet door Podman
```

Dit is **echte Kubernetes**. Podman speelt alleen voor "server". Je pods start Kubernetes zelf,
daarom zie je `snip-api` straks wel in `kubectl get pods`, maar niet in `podman ps`.

| | kind | echt cluster | AKS |
|---|---|---|---|
| brein | dezelfde node | meestal 3 eigen nodes | beheerd door Microsoft, onzichtbaar |
| werkers | dezelfde node | zoveel als nodig | jouw nodes |

Alles wat je met `kubectl` en manifests doet, werkt op AKS hetzelfde.

---

## Lab

### Deel A — Een cluster

**1. Installeren**

```bash
brew install kind
brew upgrade kubernetes-cli
echo 'export KIND_EXPERIMENTAL_PROVIDER=podman' >> ~/.zshrc
exec zsh -l
```

De derde regel vertelt kind dat het Podman moet gebruiken in plaats van Docker.

**2. Het cluster maken**

```bash
kind create cluster --name snip
podman ps --filter name=snip-control-plane
```

Duurt een minuut. Daar is je cluster: één container.

> 🖥️ **Podman Desktop:** onder **Containers** staat `snip-control-plane` gewoon tussen je andere
> containers. Onder **Settings → Resources** zie je het ook als Kind-cluster.

**3. Waar ben ik?**

```bash
kubectl config current-context
```

`kind-snip`. `kubectl` kan met meerdere clusters praten, en elk cluster heet een **context**.

> **De belangrijkste gewoonte van deel 2:** kijk vóór elk `apply` of `delete` naar je context.
> Hetzelfde commando op het verkeerde cluster is een klassieke ramp.

> 🖥️ **Podman Desktop:** linksonder in de statusbalk staat de actieve context. Klik erop om te
> wisselen. Let op: dat wisselt ook voor `kubectl` in je terminal, want beide lezen
> `~/.kube/config`.

**4. Het brein bekijken**

```bash
kubectl get nodes
kubectl get pods -n kube-system
```

Eén node, `Ready`. `-n kube-system` betekent: kijk in de **namespace** `kube-system`. Een
namespace is een map binnen het cluster om dingen gescheiden te houden. Kubernetes zet zijn
eigen onderdelen in `kube-system`; jouw pods komen in `default`, en die zie je als je `-n` weglaat.

En het brein draait zelf ook als pods:

| Pod | Wat het doet |
|---|---|
| `kube-apiserver-...` | de voordeur; `kubectl` praat alleen hiermee |
| `etcd-...` | de database: wat jij wilt, en wat er draait |
| `kube-scheduler-...` | kiest op welke node een pod komt |
| `kube-controller-manager-...` | de "vergelijken en herstellen"-lus |

De andere pods (DNS, netwerk, opslag) komen in latere modules terug.

### Deel B — Je eerste pod

**5. Starten**

```bash
kubectl run hallo --image=nginx:alpine
kubectl get pods --watch
```

`ContainerCreating` → `Running`. Stop met `Ctrl+C`.

**6. De drie commando's die je altijd gebruikt**

```bash
kubectl describe pod hallo     # de hele pod: details, en onderaan: Events
kubectl logs hallo             # wat de container in de pod print
kubectl exec -it hallo -- sh   # een shell in die container (exit om eruit te gaan)
```

`logs` en `exec` gaan over een **container**, maar je noemt de **pod**. Met één container in de
pod is dat geen probleem: `kubectl` pakt die ene. Zitten er meer in, dan kies je er een met
`-c NAAM` (bijvoorbeeld `kubectl logs hallo -c hallo`). Zonder `-c` neemt `kubectl` de eerste en
meldt het `Defaulted container ...`.

In de **Events** van `describe` zie je wat er gebeurde: `Scheduled` (scheduler koos een node),
`Pulled` (image opgehaald), `Started`. Bij elk probleem kijk je hier eerst.

Vergelijk met module 01: `podman ps` / `logs` / `exec` → `kubectl get` / `logs` / `exec`, plus
`describe`.

> 🖥️ **Podman Desktop:** ga naar **Kubernetes → Pods** en klik op `hallo`. De tabbladen zijn
> dezelfde drie commando's: **Summary** (≈ `describe`, met Events), **Logs** en **Terminal**
> (≈ `exec`).

**7. Een losse pod komt niet terug**

```bash
kubectl delete pod hallo
kubectl get pods
```

Weg. Een losse pod wordt niet bewaakt; dat doet een **Deployment** (module 09). Daarom maak je
in de praktijk nooit losse pods. Hier doen we het om de bouwsteen te leren kennen.

### Deel C — Je eigen image, met een manifest

**8. Het manifest**

Maak `k8s/snip-api-pod.yaml` in de hoofdmap van de cursus:

```yaml
apiVersion: v1          # versie van de API
kind: Pod               # wat het is
metadata:
  name: snip-api
  labels:
    app: snip-api       # een etiket; daar zoeken andere onderdelen straks op
spec:                   # wat er moet draaien
  containers:
    - name: api
      image: ghcr.io/bernardus/snip-api:latest
      ports:
        - containerPort: 3000
```

Elk Kubernetes-manifest heeft deze vier delen: `apiVersion`, `kind`, `metadata`, `spec`.

**9. Toepassen, twee keer**

```bash
cd ~/Documents/local/docker-k8s-cursus
kubectl apply -f k8s/snip-api-pod.yaml
kubectl get pods
kubectl apply -f k8s/snip-api-pod.yaml
```

De tweede keer: `pod/snip-api unchanged`. Je beschreef een toestand, en die klopt al. Dus
gebeurt er niets. Daarom is `apply` veilig om vaak uit te voeren: het is **idempotent**.

Vergelijk met `kubectl create -f k8s/snip-api-pod.yaml`: dat is een opdracht ("maak dit"), en
die faalt de tweede keer met `AlreadyExists`.

> 🖥️ **Podman Desktop:** open `snip-api` onder **Kubernetes → Pods** en kijk bij het tabblad
> **Kube** (of **YAML**). Dat is je manifest, aangevuld door Kubernetes. Onderaan staat `status`:
> wat er werkelijk draait.

**10. Werkt het?**

```bash
kubectl port-forward pod/snip-api 3000:3000
```

Open in een tweede terminal:

```bash
curl localhost:3000/api/info
```

Je API, uit je eigen pipeline, draaiend in Kubernetes. `/health/db` zegt nog `onbereikbaar`: de
database komt in module 12. Stop de tunnel met `Ctrl+C`.

> 🖥️ **Podman Desktop:** in de **Summary** van de pod kun je bij de poort ook een port forward
> aanzetten. Handig, maar onthoud het commando: op je werk heb je alleen de terminal.

---

## Breek het

### 💥 1. Een tikfout in het image

```bash
kubectl run tikfout --image=nginx:alpne
kubectl get pods --watch
```

<details>
<summary>Uitleg</summary>

`ErrImagePull`, daarna `ImagePullBackOff`. Kijk in de Events:

```bash
kubectl describe pod tikfout
```

`... nginx:alpne: not found`. Kubernetes blijft het proberen, met steeds langere pauzes (de
**BackOff**). Meestal een tikfout, of een privé-image.

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

`CrashLoopBackOff`, en `RESTARTS` loopt op. Wat zei hij?

```bash
kubectl logs crash --previous
```

`--previous` toont de logs van de vorige, gecrashte poging. Vaak de enige plek met de echte fout.

> 🖥️ **Podman Desktop:** onder **Kubernetes → Pods** zie je de status en het aantal restarts
> live oplopen. Voor de logs van de vorige poging heb je de terminal nodig.

```bash
kubectl delete pod crash
```
</details>

---

## Op je werk

- Toegang tot AKS krijg je met `az aks get-credentials`. Dat voegt een **context** toe.
- Je doet geen `kubectl apply` op productie; dat doet Argo CD (deel 3). Je gebruikt `kubectl`
  om te **kijken**: `get`, `describe`, `logs`.
- Losse pods zie je daar niet, alleen pods met namen als `snip-api-7d4f9c-x2k8p`, gemaakt door
  een Deployment.

---

## Checkpoint

<details>
<summary>1. Wat is het grote verschil tussen Compose en Kubernetes?</summary>

Compose voert één keer een opdracht uit. Kubernetes krijgt een gewenste toestand en blijft die
vergelijken met de werkelijkheid en herstellen.
</details>

<details>
<summary>2. Je verwijdert een losse pod. Komt hij terug?</summary>

Nee. Daarvoor heb je een Deployment nodig.
</details>

<details>
<summary>3. Wat betekent <code>unchanged</code> na <code>kubectl apply</code>?</summary>

De gewenste toestand klopt al met wat er draait, dus er hoeft niets te gebeuren.
</details>

<details>
<summary>4. Een pod werkt niet. Welke commando's, in welke volgorde?</summary>

`kubectl get pods` → `kubectl describe pod NAAM` (Events) → `kubectl logs NAAM --previous`.
</details>

### Eindopdracht

Zorg dat:
1. het kind-cluster **`snip`** draait, en `kind-snip` je actieve context is;
2. de pod **`snip-api`** draait, gemaakt met `kubectl apply -f k8s/snip-api-pod.yaml`.

```bash
cd ~/Documents/local/docker-k8s-cursus/modules/08-kubernetes-basis
./check.sh
```

Groen? In **module 09** vervang je de losse pod door een **Deployment**.

> **Mac herstart?** `podman machine start`, dan `podman start snip-control-plane`, en na een
> halve minuut `kubectl get nodes`.

---

## Spiekbrief

| Commando | Wat het doet |
|---|---|
| `kind create cluster --name NAAM` | cluster maken |
| `kubectl config current-context` | met welk cluster praat ik? |
| `kubectl get pods` / `get nodes` | lijst |
| `kubectl describe pod NAAM` | details + **Events** |
| `kubectl logs NAAM [--previous]` | logs (van de vorige poging) |
| `kubectl exec -it NAAM -- sh` | shell in de pod |
| `... -c CONTAINER` | bij `logs`/`exec`: kies een container, als de pod er meer heeft |
| `kubectl port-forward pod/NAAM 3000:3000` | tunnel van je Mac naar de pod |
| `kubectl apply -f BESTAND` | gewenste toestand toepassen |
| `kubectl delete pod NAAM` | verwijderen |

**Verder in je eigen tempo (CKAD):** `kubectl run ... --dry-run=client -o yaml` om YAML te
genereren, `kubectl explain pod.spec.containers` als ingebouwde handleiding, en
`kubectl get pod NAAM -o yaml` om `spec` (gewenst) naast `status` (werkelijk) te zien.
