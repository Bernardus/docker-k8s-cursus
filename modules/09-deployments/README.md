# Module 09 — Deployments: kopieën die zichzelf herstellen

**Doel:** je vervangt de losse pod door een **Deployment**. Kubernetes houdt dan altijd 3
kopieën van je API in de lucht, rolt nieuwe versies uit zonder onderbreking, en kan in één
commando terug naar de vorige versie.

**Tijd:** ±1½ uur

**Nodig:** module 08 afgerond (cluster `snip` draait, context `kind-snip`)

`CKAD` Deployments, schalen, rolling updates en rollbacks zijn kernstof voor het examen.

> 🖥️ **Podman Desktop:** waar het helpt staat zo'n blokje. Alles kan ook in de terminal, en op je
> werk heb je alleen die. (Menunamen kunnen per versie iets verschillen.)

---

## Uitleg

### Het probleem van module 08

Je losse pod `snip-api` had twee zwakke plekken:
- **verwijderd of gecrasht = weg**, niemand start hem opnieuw;
- **een nieuwe versie** betekent: pod weg, nieuwe pod maken. Daartussen draait er niets.

### Een Deployment: een recept plus een aantal

Een **Deployment** zegt: "van deze pod wil ik er altijd zoveel". Het bestaat uit twee dingen:

1. een **recept** voor de pod (de *template*): welk image, welke poort. Precies wat je in
   module 08 schreef;
2. een **aantal** (`replicas: 3`).

Kubernetes blijft vergelijken: zijn er 3 pods volgens dit recept? Eén te weinig: erbij maken.
Eén te veel: weghalen. Het idee uit module 08, nu echt aan het werk.

### Hoe weet een Deployment welke pods van hem zijn?

Via **labels**: etiketten op een pod, zoals `app: snip-api`. De Deployment zegt: "alle pods met
het etiket `app: snip-api` zijn van mij". Dat stuk heet de **selector**.

```
 Deployment snip-api
   selector:  app=snip-api   ← "deze etiketten zijn van mij"
   template:  labels: app=snip-api   ← "zo plak ik ze op nieuwe pods"
   replicas:  3
```

Selector en template-labels moeten dus overeenkomen. Doen ze dat niet, dan weigert Kubernetes
het (breek-het 1).

### Een tussenlaag: de ReplicaSet

Een Deployment maakt de pods niet zelf. Het maakt per **versie** een **ReplicaSet**: een kleine
helper die alleen het aantal pods bewaakt. Bij een nieuwe versie maakt de Deployment een nieuwe
ReplicaSet, en schuift de pods er geleidelijk naartoe:

```
 Deployment snip-api
   ├─ ReplicaSet (versie A)  →  pod, pod, pod
   └─ ReplicaSet (versie B)  →  (nog leeg)
```

Daarom hebben pods nu namen als `snip-api-798b5785d6-cl7xb`:
`deployment`-`replicaset`-`pod`. Je hoeft ReplicaSets bijna nooit zelf aan te raken, maar je ziet
ze wel, en ze maken terugdraaien mogelijk: de oude blijft bewaard.

### Een nieuwe versie zonder onderbreking: de rolling update

```
  oud: ● ● ●       nieuw:            begin
  oud: ● ● ●       nieuw: ○          nieuwe pod start
  oud: ● ●         nieuw: ●          nieuwe is klaar → één oude weg
  oud: ●           nieuw: ● ●
  oud:             nieuw: ● ● ●      klaar
```

Er draaien steeds minstens 3 pods. Twee instellingen bepalen het tempo:

| Instelling | Betekent | Wij kiezen |
|---|---|---|
| `maxSurge` | hoeveel pods er **extra** mogen zijn tijdens de update | `1`: tijdelijk 4 |
| `maxUnavailable` | hoeveel er **minder** mogen zijn | `0`: nooit minder dan 3 |

Met `maxUnavailable: 0` wordt een oude pod pas weggehaald als er een nieuwe klaarstaat. Start de
nieuwe versie niet, dan blijven de oude gewoon draaien. Dat zie je straks in deel C.

### Altijd een vaste versie, nooit `latest`

In module 08 gebruikte je `snip-api:latest`. In een Deployment is dat een valkuil:
- je kunt niet zien **welke** versie draait;
- push je een nieuwe `latest`, dan verandert je YAML niet, dus ziet Kubernetes **niets om te
  updaten**;
- terugdraaien naar "de vorige `latest`" kan niet.

Daarom gebruiken we de vaste tags uit je pipeline: `sha-7233d53`, `sha-4000a15`, enzovoort. Een
nieuwe versie is dan gewoon: een ander tagje in je YAML.

---

## Lab

### Deel A — Van pod naar Deployment

**1. De losse pod opruimen**

```bash
cd ~/Documents/local/docker-k8s-cursus
kubectl config current-context
kubectl delete -f k8s/snip-api-pod.yaml
rm k8s/snip-api-pod.yaml
```

Eerst kijken waar je bent: `kind-snip`. Dan de pod weg, en het bestand ook: de Deployment komt
ervoor in de plaats.

**2. Welke versies heb je?**

```bash
gh run list --workflow snip-api.yml --branch main --status success --limit 5 \
  --json headSha,displayTitle --jq '.[] | "sha-\(.headSha[0:7])  \(.displayTitle)"'
```

Elke regel is een image in GHCR. We beginnen met de **oudste** (`sha-7233d53`, "CI voor
snip-api"), zodat we straks naar een nieuwere kunnen updaten.

**3. Het manifest**

Maak een map per app, te beginnen met de API, en daarin `deployment.yaml`:

```bash
mkdir -p k8s/api
```

`k8s/api/deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: snip-api
  labels:
    app: snip-api
  annotations:
    kubernetes.io/change-cause: "eerste versie (sha-7233d53)"   # verschijnt in de geschiedenis
spec:
  replicas: 3                     # zoveel kopieën
  selector:
    matchLabels:
      app: snip-api               # deze pods zijn van mij...
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1                 # tijdelijk één extra
      maxUnavailable: 0           # nooit minder dan 3
  template:                       # ...en zo maak ik ze:
    metadata:
      labels:
        app: snip-api             # (moet passen bij de selector)
    spec:
      containers:
        - name: api
          image: ghcr.io/bernardus/snip-api:sha-7233d53
          ports:
            - containerPort: 3000
```

Herken je het? Alles onder `template:` is je pod-manifest uit module 08. Daaromheen staan het
aantal, de selector en de update-instellingen.

> **Zelf genereren** (handig voor het CKAD-examen):
> `kubectl create deployment snip-api --image=ghcr.io/bernardus/snip-api:sha-7233d53 --replicas=3 --port=3000 --dry-run=client -o yaml`
> geeft het geraamte; de rest vul je aan.

**4. Toepassen**

```bash
kubectl apply -f k8s/api/deployment.yaml
kubectl rollout status deploy/snip-api
kubectl get deploy,rs,pods
```

`rollout status` wacht tot alles klaar is. Daarna zie je de drie lagen: één Deployment, één
ReplicaSet, drie pods, met die lange namen.

> 🖥️ **Podman Desktop:** onder **Kubernetes → Deployments** staat `snip-api` met 3/3. Onder
> **Pods** zie je de drie pods.

### Deel B — Zelfherstel en schalen

**5. Een pod weggooien**

Open een **tweede terminal** en laat daar meekijken:

```bash
kubectl get pods --watch
```

In je eerste terminal, verwijder één pod (pak een naam uit de lijst):

```bash
kubectl delete pod snip-api-xxxxxxxxxx-xxxxx
```

In de tweede terminal: de pod gaat naar `Terminating`, en meteen verschijnt er een nieuwe met een
andere naam. De Deployment zag 2 waar er 3 moesten zijn, en vulde aan. Dit is het verschil met
module 08.

Nog sterker: gooi ze **allemaal** weg.

```bash
kubectl delete pods -l app=snip-api
```

`-l app=snip-api` betekent: alle pods met dat etiket. Na een paar seconden staan er weer 3.

**6. Opschalen, en het bestand wint**

```bash
kubectl scale deploy/snip-api --replicas=5
kubectl get pods
```

Vijf. Pas nu het bestand opnieuw toe:

```bash
kubectl apply -f k8s/api/deployment.yaml
kubectl get pods
```

Terug naar drie. Het **bestand** is de gewenste toestand. `kubectl scale` was een tijdelijke
wijziging in het cluster, en die werd overschreven zodra het bestand weer werd toegepast.

> **Onthoud dit voor deel 3.** Met Argo CD wordt je bestand in Git automatisch steeds opnieuw
> toegepast. Iets met de hand in het cluster veranderen (zoals `scale`) houdt dan geen stand.
> Wil je 5? Zet `replicas: 5` in het bestand.

### Deel C — Een nieuwe versie uitrollen

**7. Meekijken klaarzetten**

In je tweede terminal (stop de vorige met `Ctrl+C`):

```bash
kubectl get rs --watch
```

**8. Updaten**

Pas in `k8s/api/deployment.yaml` twee regels aan:

```yaml
    kubernetes.io/change-cause: "nieuwe ondertitel (sha-4000a15)"
```

```yaml
          image: ghcr.io/bernardus/snip-api:sha-4000a15
```

Toepassen:

```bash
kubectl apply -f k8s/api/deployment.yaml
kubectl rollout status deploy/snip-api
```

In je tweede terminal zie je een **nieuwe** ReplicaSet die oploopt naar 3, terwijl de oude
afloopt naar 0. Pod voor pod, zoals in het plaatje uit de uitleg.

**9. Wat draait er nu?**

```bash
kubectl get pods -o 'custom-columns=POD:.metadata.name,IMAGE:.spec.containers[0].image'
kubectl get rs
```

Alle pods op `sha-4000a15`. De oude ReplicaSet bestaat nog, met 0 pods: die bewaart de vorige
versie.

**10. De geschiedenis**

```bash
kubectl rollout history deploy/snip-api
```

Twee regels, met jouw `change-cause` erbij. Daarom zette je die annotatie in het bestand.

### Deel D — Een kapotte versie, en terug

**11. Een versie die niet bestaat**

Zet in het bestand een image dat niet bestaat:

```yaml
    kubernetes.io/change-cause: "kapotte versie (sha-0000000)"
```

```yaml
          image: ghcr.io/bernardus/snip-api:sha-0000000
```

```bash
kubectl apply -f k8s/api/deployment.yaml
kubectl get pods
```

Eén nieuwe pod hangt op `ImagePullBackOff` (module 08). En de drie **oude pods draaien gewoon
door**. Dankzij `maxUnavailable: 0` werd er niets weggehaald voordat de nieuwe klaar was.
Gebruikers merken niets.

```bash
kubectl rollout status deploy/snip-api --timeout=20s
```

`timed out`: de update komt niet verder, en blijft wachten.

**12. Terugdraaien**

```bash
kubectl rollout undo deploy/snip-api
kubectl rollout status deploy/snip-api
kubectl get pods
```

De kapotte pod verdwijnt, en alles staat weer op `sha-4000a15`. In één commando.

Je krijgt wel een waarschuwing: `Rolling back will not update the ... last-applied-configuration`.
Die is terecht: **je bestand zegt nog steeds `sha-0000000`**. De volgende `apply` zou de kapotte
versie dus gewoon weer proberen. Zet het bestand terug op de goede versie:

```yaml
    kubernetes.io/change-cause: "nieuwe ondertitel (sha-4000a15)"
```

```yaml
          image: ghcr.io/bernardus/snip-api:sha-4000a15
```

```bash
kubectl apply -f k8s/api/deployment.yaml
```

`unchanged`: cluster en bestand zijn het weer eens.

> **De les:** `rollout undo` is een noodrem. De echte oplossing is je **bestand** terugzetten. In
> deel 3 is dat letterlijk `git revert`, en Argo CD doet de rest.

### Deel E (extra) — Meerdere nodes

Tot nu toe stond alles op één node. Wil je zien hoe Kubernetes pods **verspreidt**, en wat er
gebeurt als een node weg moet? Maak dan een tweede, tijdelijk cluster met drie nodes. Dit deel
is optioneel.

**13. Ruimte maken en het cluster maken**

Drie nodes kosten samen ruim 1 GB geheugen. Zet je eigen cluster even uit:

```bash
podman stop snip-control-plane
kind create cluster --name drie --config modules/09-deployments/uitwerking/kind-drie-nodes.yaml
kubectl get nodes
```

Drie nodes: één brein, twee werkers. kind heeft je context op `kind-drie` gezet.

**14. Verspreiden**

```bash
sed 's/replicas: 3/replicas: 4/' k8s/api/deployment.yaml | kubectl apply -f -
kubectl rollout status deploy/snip-api
kubectl get pods -o wide
```

Kijk bij `NODE`: de pods zijn verdeeld over `drie-worker` en `drie-worker2`. (Niet op het brein:
daar mogen in een normaal cluster geen gewone pods op.)

**15. Een node in onderhoud**

```bash
kubectl drain drie-worker --ignore-daemonsets
kubectl get pods -o wide
kubectl get nodes
```

`drain` betekent: "deze node gaat in onderhoud, haal alles eraf". De pods op `drie-worker` worden
netjes gestopt en op `drie-worker2` opnieuw gestart. De node staat op `SchedulingDisabled`: er komt
niets nieuws meer op. Zo doen beheerders updates van nodes, en zo doet AKS het ook bij een upgrade.

> **En als een node onverwacht uitvalt?** Dan wacht Kubernetes standaard 5 minuten, want het kan
> ook een kort netwerkprobleem zijn. Daarna worden de pods op een andere node opnieuw gestart.

**16. Opruimen en terug**

```bash
kind delete cluster --name drie
podman start snip-control-plane
kubectl config use-context kind-snip
kubectl get nodes
```

Wacht tot je node weer `Ready` is.

---

## Breek het

### 💥 1. Etiketten die niet passen

Maak een kopie van je Deployment met een tikfout in het etiket van de template:

```bash
sed -e 's/name: snip-api$/name: snip-api-kopie/' \
    -e '/template:/,$ s/app: snip-api/app: snip-apii/' \
    k8s/api/deployment.yaml | kubectl apply -f -
```

<details>
<summary>Uitleg</summary>

`` `selector` does not match template `labels` ``. De Deployment zou pods maken met het etiket
`snip-apii`, maar zoekt naar pods met `snip-api`. Hij zou zijn eigen pods nooit terugvinden, en er
eindeloos nieuwe bijmaken. Kubernetes weigert het daarom meteen.

Etiketten zijn de lijm van Kubernetes. In module 10 koppel je een Service aan je pods, ook via een
etiket. Een tikfout geeft daar **geen** foutmelding, maar een Service die stilletjes naar nul
pods wijst.
</details>

### 💥 2. Een nieuwe `latest` die niet aankomt

Stel, je Deployment gebruikt `snip-api:latest`, en je pipeline pusht een nieuwe `latest`. Je doet
`kubectl apply`.

<details>
<summary>Uitleg</summary>

`unchanged`. In je YAML staat nog steeds `latest`, dus voor Kubernetes is er niets veranderd. De
pods blijven de oude versie draaien. Pas als er een pod opnieuw start, haalt die misschien de nieuwe
op, en dan draaien er twee versies door elkaar.

`kubectl rollout restart deploy/snip-api` vervangt alle pods, maar je weet nog steeds niet zeker
wat er draait. Vaste tags (`sha-...`) voorkomen dit allemaal. Daarom zet de pipeline in deel 3
elke nieuwe versie met haar eigen tag in Git.
</details>

### 💥 3. Een update die met de hand gebeurt

```bash
kubectl set image deploy/snip-api api=ghcr.io/bernardus/snip-api:sha-ff7b4bf
kubectl rollout status deploy/snip-api
kubectl apply -f k8s/api/deployment.yaml
```

<details>
<summary>Uitleg</summary>

`kubectl set image` past het image direct in het cluster aan, en de rollout gaat gewoon. Maar
de `apply` daarna zet het meteen terug naar wat in het bestand staat. Net als `scale` in stap 6:
handwerk in het cluster houdt geen stand tegen het bestand.

Op het CKAD-examen is `set image` handig, want het gaat snel. In het echt verandert je het bestand.
</details>

---

## Op je werk

- **Je ziet hier bijna alleen Deployments** (en StatefulSets voor dingen met data, module 12).
  `kubectl get deploy -n jouw-namespace` is een van de eerste commando's die je typt.
- **Minimaal 2 replicas** is in productie meestal de regel, vaak afgedwongen door een policy
  (module 24). Met 1 replica is elke update of crash even downtime.
- **Je werkt het bestand bij, niet het cluster.** Bij jullie zet de pipeline de nieuwe image-tag
  in Git (vaak in Helm-values), en Argo CD voert de rolling update uit. `kubectl rollout undo`
  gebruik je hooguit in een noodgeval, en daarna zet je Git terug.
- **Node-onderhoud** (`drain`) doet het platformteam, of AKS zelf bij een upgrade. Met
  `maxUnavailable: 0`, meerdere replicas en een **PodDisruptionBudget** (module 13) merken je
  gebruikers daar niets van.

---

## Checkpoint

<details>
<summary>1. Wat is het verschil tussen een losse pod en een Deployment?</summary>

Een losse pod wordt niet bewaakt. Een Deployment zorgt dat er altijd het gevraagde aantal pods
volgens het recept draait, en regelt updates en rollbacks.
</details>

<details>
<summary>2. Hoe weet een Deployment welke pods van hem zijn?</summary>

Via de selector: alle pods met de etiketten uit `selector.matchLabels`. De template plakt diezelfde
etiketten op nieuwe pods.
</details>

<details>
<summary>3. Wat doet een ReplicaSet, en waarom blijft de oude bewaard?</summary>

Een ReplicaSet bewaakt het aantal pods van één versie. De oude blijft (met 0 pods) bewaard, zodat
`rollout undo` meteen terug kan.
</details>

<details>
<summary>4. Wat betekent <code>maxUnavailable: 0</code> en <code>maxSurge: 1</code>?</summary>

Tijdens een update zijn er nooit minder pods dan gevraagd, en hooguit één extra. Een oude pod
verdwijnt pas als er een nieuwe klaarstaat.
</details>

<details>
<summary>5. Een nieuwe versie start niet. Wat merken je gebruikers?</summary>

Niets: met `maxUnavailable: 0` blijven de oude pods draaien. De update blijft hangen tot je hem
herstelt of terugdraait.
</details>

<details>
<summary>6. Je deed <code>kubectl scale --replicas=5</code>, en daarna <code>kubectl apply -f</code>. Hoeveel pods?</summary>

Zoveel als in het bestand staat (3). Het bestand is de gewenste toestand.
</details>

<details>
<summary>7. Waarom geen <code>latest</code> in een Deployment?</summary>

Je weet niet welke versie draait, een nieuwe `latest` geeft geen wijziging in je YAML (dus geen
update), en je kunt niet terug naar een vorige versie.
</details>

### Eindopdracht

Zorg dat:
1. `k8s/api/deployment.yaml` bestaat, en de losse pod uit module 08 weg is;
2. de Deployment `snip-api` draait met **3 replicas**, allemaal ready, op een vaste
   **`sha-`-tag** (niet `latest`);
3. de update-instellingen `maxSurge: 1` en `maxUnavailable: 0` zijn;
4. de geschiedenis (`rollout history`) minstens 2 versies heeft, met een `change-cause`;
5. cluster en bestand het eens zijn (`kubectl diff` geeft niets).

```bash
cd ~/Documents/local/docker-k8s-cursus/modules/09-deployments
./check.sh
```

Groen? Je drie pods hebben elk een eigen IP-adres, en die veranderen bij elke update. Hoe bereik
je ze dan? Dat lost een **Service** op, in **module 10**.

---

## Spiekbrief

| Commando | Wat het doet |
|---|---|
| `kubectl apply -f BESTAND` | gewenste toestand toepassen |
| `kubectl diff -f BESTAND` | wat zou `apply` veranderen? |
| `kubectl get deploy,rs,pods` | de drie lagen in één keer |
| `kubectl get pods -l app=snip-api` | alleen pods met dat etiket |
| `kubectl get pods -o wide` | ook IP-adres en node |
| `kubectl rollout status deploy/NAAM` | wachten tot een update klaar is |
| `kubectl rollout history deploy/NAAM` | eerdere versies |
| `kubectl rollout undo deploy/NAAM` | terug naar de vorige versie (noodrem) |
| `kubectl rollout restart deploy/NAAM` | alle pods vervangen, zonder iets te veranderen |
| `kubectl scale deploy/NAAM --replicas=N` | tijdelijk ander aantal (het bestand wint) |
| `kubectl set image deploy/NAAM CONTAINER=IMAGE` | snel ander image (het bestand wint) |
| `kubectl create deployment ... --dry-run=client -o yaml` | geraamte genereren |
| `kubectl drain NODE --ignore-daemonsets` | node leegmaken voor onderhoud |
| `kubectl uncordon NODE` | node weer in gebruik nemen |
| `kind create cluster --name NAAM --config BESTAND` | cluster met meerdere nodes |

| Deployment-YAML | |
|---|---|
| `replicas` | hoeveel pods |
| `selector.matchLabels` | welke pods van mij zijn |
| `template` | het pod-recept (met dezelfde labels) |
| `strategy.rollingUpdate.maxSurge` / `maxUnavailable` | tempo van een update |
| `metadata.annotations.kubernetes.io/change-cause` | tekst in de geschiedenis |
