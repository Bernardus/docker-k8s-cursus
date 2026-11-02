# Module 14 — Kustomize en Helm

**Doel:** één base voor snip, met twee omgevingen (test en prod) erbij zonder bestanden te kopiëren.
De ConfigMaps maak je voortaan rechtstreeks uit de bestanden in `app/`. En je installeert software
van anderen met Helm.

**Tijd:** ±2 uur

**Nodig:** module 13 afgerond

> 🖥️ **Podman Desktop:** blokjes zoals dit zijn ter controle, niet in plaats van.
> (Menunamen kunnen per versie iets verschillen.)

---

## Uitleg

### Eerst de problemen

Na module 13 heb je 13 YAML-bestanden. Voor één omgeving werkt dat prima. De problemen komen
als het groter wordt.

**1. Meerdere omgevingen.** Je wilt test, acceptatie en productie. Bijna gelijk, op een paar
dingen na:

| | test | prod |
|---|---|---|
| namespace | snip-test | snip |
| pods | 1 | 3–10 |
| image | nieuwste | goedgekeurde versie |

Zonder gereedschap kopieer je alles drie keer. Elke wijziging (een nieuwe probe, een env var) doe
je dan drie keer. Vergeet je er één, dan wijkt prod stilletjes af van test. En in 3 × 13 bestanden
zie je niet meer wát nu eigenlijk het verschil is.

**2. Kopieën van bestanden.** `configmap-site.yaml` is een kopie van `index.html`. Pas je het
origineel aan, dan blijft de kopie oud. En ook als je de ConfigMap bijwerkt, merken de pods het niet
zonder `rollout restart`.

**3. Software van anderen.** Envoy Gateway installeerde je met één groot `install.yaml`: honderden
objecten. Wil je één ding anders, dan moet je in die YAML gaan zoeken en hem aanpassen. Bij elke
nieuwe versie opnieuw. Welke objecten horen erbij als je hem weg wilt gooien? En wat stond er ook
alweer, als een update misgaat?

**4. Veel teams, dezelfde soort app.** Op je werk hebben tientallen teams een API. Schrijft elk
team zijn eigen YAML, dan vergeet de helft de probes, en doet iedereen het net anders. Wil het
platformteam iets veranderen, dan moet dat in tientallen repo's.

| Probleem | Oplossing |
|---|---|
| 1. Omgevingen | **Kustomize**: één base, per omgeving alleen de verschillen. (Helm kan het ook, met een values-bestand per omgeving) |
| 2. Kopieën | **Kustomize**: ConfigMaps rechtstreeks uit je bestanden |
| 3. Software van anderen | **Helm**: een pakket met een versie, jij kiest alleen de instellingen |
| 4. Veel teams | **Helm**: het platformteam maakt één chart, elk team vult alleen values in |

Allebei maken ze uiteindelijk gewone YAML, die naar het cluster gaat zoals je gewend bent.

### Kustomize: een base plus de verschillen

**Voor** (einde module 13):

```
app/
├── db/links.sql
└── web/
    ├── nginx-k8s.conf
    └── site/index.html
k8s/
├── gateway.yaml                 EnvoyProxy + GatewayClass + Gateway door elkaar
├── api/
│   ├── deployment.yaml
│   ├── hpa.yaml
│   ├── route.yaml
│   └── service.yaml
├── db/
│   ├── configmap-init.yaml      kopie van app/db/links.sql
│   ├── service.yaml
│   └── statefulset.yaml
└── web/
    ├── configmap-nginx.yaml     kopie van app/web/nginx-k8s.conf
    ├── configmap-site.yaml      kopie van app/web/site/index.html
    ├── deployment.yaml
    ├── route.yaml
    └── service.yaml
```

**Na** (einde van dit lab):

```
app/
├── kustomization.yaml           NIEUW: maakt de 3 ConfigMaps uit de echte bestanden
├── db/links.sql
└── web/
    ├── nginx-k8s.conf
    └── site/index.html
k8s/
├── platform/                    1× per cluster (op je werk: platformteam)
│   ├── gatewayclass.yaml        EnvoyProxy + GatewayClass, geknipt uit gateway.yaml
│   └── headlamp-values.yaml     onze instellingen voor de Headlamp-chart (Helm)
├── base/                        alles van snip, in elke omgeving gelijk
│   ├── kustomization.yaml       NIEUW: de lijst van alles hieronder + ../../app
│   ├── gateway.yaml             alleen nog de Gateway snip
│   ├── api/                     deployment, hpa, route, service
│   ├── db/                      service, statefulset   (configmap-init weg)
│   └── web/                     deployment, route, service   (2 configmaps weg)
└── overlays/                    per omgeving alleen de verschillen
    ├── test/
    │   └── kustomization.yaml   NIEUW: "de base, maar in snip-test, met minder pods"
    └── prod/
        └── kustomization.yaml   NIEUW: "de base, in default, met een vaste image-tag"
```

Kort: de mappen `api/`, `web/` en `db/` schuiven één niveau omlaag naar `base/`. De drie
kopieën verdwijnen. Er komen vier `kustomization.yaml`'s bij. En `test/` en `prod/` bevatten elk maar één bestand.

| Map | Wat | Commando |
|-----|-----|----------|
| `k8s/platform/` | één keer per cluster | `kubectl apply -f` / `helm install` |
| `k8s/base/` | wat elke omgeving deelt | nooit los: alleen via een overlay |
| `k8s/overlays/test/` | snip in namespace `snip-test` | `kubectl apply -k k8s/overlays/test` |
| `k8s/overlays/prod/` | snip in namespace `default` | `kubectl apply -k k8s/overlays/prod` |

> In deel A rol je `base/` nog één keer los uit, om te zien wat Kustomize doet. Vanaf stap 8
> gaat alles via een overlay.

De testomgeving bevat alleen de **verschillen**. Een wijziging in de base komt vanzelf in elke
omgeving terecht. Kustomize zit in `kubectl` ingebouwd: `kubectl apply -k`.

Kustomize kan ook **ConfigMaps maken** uit bestanden. Die krijgen een stukje code achter hun naam
(een *hash*), zoals `snip-web-site-t6d4b89d99`. Verandert de inhoud, dan verandert de naam. De
Deployment verwijst dan naar een nieuwe naam, en Kubernetes rolt de pods vanzelf opnieuw uit.

### Helm: npm voor Kubernetes

Zonder npm zou je de code van Hono van GitHub kopiëren en in je project plakken. Welke versie had
je ook alweer? Bijwerken is opnieuw plakken. Met npm doe je `npm install hono`: een pakket met een
versie, dat je instelt via de opties die Hono aanbiedt, zonder in hun code te zitten.

Helm is precies dat, maar dan voor YAML:

| npm | Helm |
|---|---|
| package | **chart** |
| `npm install hono@4.6` | `helm install headlamp headlamp/headlamp --version 0.46.0` |
| de opties die je meegeeft | een **values**-bestand |
| npm registry | chart-repository (`helm repo add`) |

Een chart is een pakket YAML met gaten erin, zoals `replicas: {{ .Values.replicaCount }}`. De
maker bepaalt welke gaten er zijn; jij vult ze in. Zo blijft jouw aanpassing in jouw bestand
staan, en niet in hun YAML. Een nieuwe versie van de chart? Zelfde values-bestand, nieuwe
`--version`.

Envoy Gateway, de metrics-server, Cilium, External Secrets, Argo CD: bijna alle software voor
Kubernetes wordt zo geleverd.

### Waarom snip geen Helm nodig heeft (en Headlamp wel)

- **snip** is van jou. Je mag je eigen YAML gewoon aanpassen. Kustomize is genoeg.
- **Headlamp** is van iemand anders. Je wilt hun YAML niet aanpassen, alleen een paar knoppen
  omzetten. Daar zijn values voor.

Stel dat je snip aan tien andere teams wilt geven, elk met een eigen aantal pods en image-tag. Dan
maak je er een chart van: zij vullen alleen values in, jij levert nieuwe versies. Op dat moment
wordt Helm ook voor je eigen app nuttig. Dat is precies wat een platformteam doet (zie
"Op je werk").

| | Kustomize | Helm |
|---|---|---|
| Hoe | base + verschillen | sjablonen + invulwaarden |
| Wat kun je aanpassen | elk veld, met een patch | alleen wat de chart als value aanbiedt |
| Wie bepaalt wat kan | jij | de maker van de chart |
| Vooral voor | je eigen app | software van anderen, of een chart van het platformteam |
| Installeren | zit in `kubectl` | apart programma, `helm` |
| Bijhouden | niets, het is gewoon YAML | een **release** met versiegeschiedenis |

### Waar komen de woorden vandaan?

| Woord | Herkomst |
|---|---|
| **Kustomize** | Engels *customize* (aanpassen), met een K van Kubernetes |
| **Helm** | het roer van een schip. Kubernetes is Grieks voor "stuurman", en Helm is waarmee hij stuurt |
| **chart** | zeekaart. Het hele Kubernetes-gereedschap heeft een scheepvaartthema |
| **release** | Engels: vrijgeven, uitbrengen. Elke installatie van een chart is een release |
| **base** | Engels: basis, fundament. Wat elke omgeving deelt |
| **env** | afkorting van *environment*: omgeving (Frans *environ*: rondom). Op je werk: pr/tst/acc/prd |
| **overlay** | Engels: een laag eroverheen. De testomgeving ligt als laag over de base |
| **patch** | Engels: een lap of oplapstuk, zoals op een broek. Je naait alleen het verschil erop |
| **hash** | Engels *to hash*: fijnhakken (vergelijk *hachee*). Een inhoud wordt "gehakt" tot een korte code |
| **manifest** | Latijn *manifestus*: duidelijk zichtbaar. Ook de ladinglijst van een schip; een YAML-bestand is de "ladinglijst" voor het cluster |
| **Headlamp** | hoofdlamp: licht in je cluster |

---

## Lab

Je tunnel naar de voordeur (poort 8080) mag openblijven.

### Deel A — Eén base

**1. Een nieuwe indeling**

Hou het overzicht **Voor/Na** uit de uitleg erbij: daar werk je in deel A en B naartoe.

```bash
cd ~/Documents/local/docker-k8s-cursus
mkdir -p k8s/base k8s/overlays/test k8s/overlays/prod k8s/platform
mv k8s/api k8s/web k8s/db k8s/gateway.yaml k8s/base/
```

`k8s/base/gateway.yaml` bevat drie dingen: de `EnvoyProxy`, de `GatewayClass` en de `Gateway`.
De eerste twee gelden voor het hele cluster: welk programma de voordeur is. Dat regel je één keer,
niet per omgeving. Op je werk doet het platformteam dat.

Knip daarom de eerste twee blokken (`EnvoyProxy` en `GatewayClass`, met hun `---`) uit
`k8s/base/gateway.yaml`, en zet ze in een nieuw bestand `k8s/platform/gatewayclass.yaml`. In
`k8s/base/gateway.yaml` blijft alleen de `Gateway` met de naam `snip` over.

**2. ConfigMaps rechtstreeks uit `app/`**

Gooi de drie kopieën weg:

```bash
rm k8s/base/web/configmap-site.yaml k8s/base/web/configmap-nginx.yaml k8s/base/db/configmap-init.yaml
```

Maak `app/kustomization.yaml`:

```yaml
# De app levert zijn eigen instellingen: van deze bestanden maakt Kustomize ConfigMaps.
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
configMapGenerator:
  - name: snip-web-site
    files:
      - web/site/index.html
  - name: snip-web-nginx
    files:
      - default.conf=web/nginx-k8s.conf   # sleutel default.conf, inhoud uit nginx-k8s.conf
  - name: snip-db-init
    files:
      - db/links.sql
```

Waarom in `app/` en niet in `k8s/`? Kustomize leest alleen bestanden in zijn eigen map of
daaronder, uit veiligheid. Zie Breek het 1.

**3. De base**

Maak `k8s/base/kustomization.yaml`:

```yaml
# De base: alles wat snip nodig heeft, in elke omgeving.
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - gateway.yaml
  - api/deployment.yaml
  - api/service.yaml
  - api/route.yaml
  - api/hpa.yaml
  - web/deployment.yaml
  - web/service.yaml
  - web/route.yaml
  - db/statefulset.yaml
  - db/service.yaml
  - ../../app                # de ConfigMaps uit app/kustomization.yaml
```

Bekijk wat Kustomize ervan maakt, zonder iets te veranderen:

```bash
kubectl kustomize k8s/base | less
```

Eén lange lap YAML: al je bestanden achter elkaar, plus de drie ConfigMaps. Zoek (`/configMap`)
hoe de Deployment van de website nu naar `snip-web-site-...` verwijst. (`q` om te stoppen.)

En wat zou er in het cluster veranderen?

```bash
kubectl diff -k k8s/base
```

Rood (`-`) is wat er nu staat, groen (`+`) wat het wordt: nieuwe ConfigMap-namen. Zo'n overzicht
zie je op je werk in een pull request, vóór er iets uitgerold wordt.

Toepassen:

```bash
kubectl apply -f k8s/platform/
kubectl apply -k k8s/base
```

> Bij de StatefulSet, de Gateway en de routes staat steeds `configured`, ook als er niets
> verandert. Dat is een eigenaardigheid van `kubectl`. `kubectl diff -k k8s/base` laat zien dat er
> echt niets verschilt.

De oude ConfigMaps (zonder hash) worden niet meer gebruikt. Ruim ze op:

```bash
kubectl delete configmap snip-web-site snip-web-nginx snip-db-init
```

**4. De proef: een wijziging in `app/`**

Verander de ondertitel van de website, net als in module 11. Maar nu in het echte bestand:

```bash
sed -i '' 's|Uit een ConfigMap!|Via Kustomize!|' app/web/site/index.html
kubectl apply -k k8s/base
kubectl get configmap
```

Er is een nieuwe `snip-web-site-...` met een andere hash. De website-pods zijn vanzelf vervangen:
ververs <http://localhost:8080> en je ziet de nieuwe tekst. Geen `rollout restart` meer nodig.

De oude ConfigMap staat er nog. `kubectl apply` gooit nooit iets weg wat niet meer in je bestanden
staat. Gooi hem weg als je wilt; in module 17 ruimt Argo CD dat voor je op.

> 🖥️ **Podman Desktop:** onder **Kubernetes → ConfigMaps & Secrets** zie je de namen met hash.

### Deel B — Een tweede omgeving

**5. Omgeving test**

Maak `k8s/overlays/test/kustomization.yaml`:

```yaml
# Omgeving test: de base, met alleen de verschillen hieronder.
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: snip-test             # alles in een eigen namespace
resources:
  - ../../base
labels:
  - pairs:
      env: test                  # een etiket op alles, handig om te zoeken
images:
  - name: ghcr.io/bernardus/snip-api
    newTag: latest               # test draait altijd de nieuwste versie
patches:                         # schrijf alleen op wat anders is
  - patch: |-
      apiVersion: autoscaling/v2
      kind: HorizontalPodAutoscaler
      metadata:
        name: snip-api
      spec:
        minReplicas: 1
        maxReplicas: 2
  - patch: |-
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: snip-web
      spec:
        replicas: 1
```

Een **patch** ziet eruit als een klein stukje van het origineel: soort, naam, en alleen de
velden die anders moeten. Kustomize zoekt het origineel op naam op en past het aan.

Bekijk het resultaat:

```bash
kubectl kustomize k8s/overlays/test | grep -E "namespace:|image:|Replicas:|replicas:"
```

**6. Uitrollen**

Een namespace en het wachtwoord maak je zelf: die horen niet in Git (module 11).

```bash
kubectl create namespace snip-test
kubectl create secret generic snip-db -n snip-test --from-literal=password=$(openssl rand -hex 16)
kubectl apply -k k8s/overlays/test
kubectl get pods -n snip-test --watch
```

Na een halve minuut: één API-pod, één website-pod, en een eigen database `snip-db-0` met een eigen
schijf. `Ctrl+C`.

```bash
kubectl get all -A -l env=test
```

Alles met het etiket `env=test`, in één overzicht.

**7. De voordeur van test**

De testomgeving heeft ook een eigen Gateway, en daarmee een eigen Envoy. Open een tunnel op een
andere poort:

```bash
envoy=$(kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-namespace=snip-test -o name)
kubectl port-forward -n envoy-gateway-system $envoy 8081:80
```

Open <http://localhost:8081>. Alleen de drie voorbeeldlinks: je eigen link `opslag` uit module 12
staat niet in deze database. Twee omgevingen, helemaal los van elkaar, uit dezelfde base.

**8. Omgeving prod**

Je eerste snip in `default` is eigenlijk je productie. Geef die ook een eigen map, zodat `base/`
echt alleen het gedeelde stuk is. Maak `k8s/overlays/prod/kustomization.yaml`:

```yaml
# Omgeving prod: de base zoals hij is, met een vaste versie.
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: default
resources:
  - ../../base
labels:
  - pairs:
      env: prod
images:
  - name: ghcr.io/bernardus/snip-api
    newTag: sha-9743b8d          # prod draait een vaste, geteste versie, nooit latest
```

Test draait `latest`, prod een vaste tag. Een nieuwe versie naar prod is dus één regel hier
aanpassen, en in Git zie je precies wanneer dat gebeurde. Op je werk doet de pipeline dat in
`values-prd.yaml`.

```bash
kubectl diff -k k8s/overlays/prod
kubectl apply -k k8s/overlays/prod
kubectl get all -A -l env=prod
```

De diff laat alleen het nieuwe etiket zien: verder is prod precies wat al draaide. Vanaf nu rol
je `default` uit met `k8s/overlays/prod`, niet meer met `k8s/base`.

### Deel C — Helm

**9. Helm installeren**

```bash
brew install helm
helm version
```

**10. Headlamp installeren**

Headlamp is een webinterface voor je cluster. Een mooi voorbeeld van software die je met Helm
installeert.

Zoek de chart op:

```bash
helm repo add headlamp https://kubernetes-sigs.github.io/headlamp/
helm repo update
helm search repo headlamp
```

Wat kun je instellen?

```bash
helm show values headlamp/headlamp | less
```

Honderden regels, met uitleg. Zoek (`/clusterRoleBinding`): standaard krijgt Headlamp de rol
`cluster-admin`, dus alle rechten. Liever niet. Maak `k8s/platform/headlamp-values.yaml`:

```yaml
# Onze instellingen voor de Headlamp-chart. Alles wat hier niet staat, blijft de standaard.
clusterRoleBinding:
  clusterRoleName: view      # alleen kijken, niets veranderen
```

Installeer:

```bash
helm install headlamp headlamp/headlamp --version 0.46.0 \
  --namespace headlamp --create-namespace \
  -f k8s/platform/headlamp-values.yaml
helm list -A
```

`headlamp` staat erbij als **release**, revisie 1. Open hem (in een nieuwe terminal):

```bash
kubectl create token headlamp -n headlamp
kubectl port-forward -n headlamp svc/headlamp 8090:80
```

Open <http://localhost:8090>, plak de token, en kijk rond: je namespaces `default` en `snip-test`,
je pods, de HPA. Probeer iets weg te gooien: dat mag niet. Secrets zie je ook niet. Precies wat de
rol `view` belooft.

Wat heeft Helm eigenlijk gemaakt?

```bash
helm template headlamp headlamp/headlamp --version 0.46.0 -f k8s/platform/headlamp-values.yaml | grep "^kind:"
```

Gewone YAML: een Deployment, een Service, een ServiceAccount, een ClusterRoleBinding. Helm vult
alleen de gaten in.

**11. Bijwerken en terugdraaien**

Voeg aan `k8s/platform/headlamp-values.yaml` een regel toe, **helemaal links** (niet ingesprongen):

```yaml
clusterRoleBinding:
  clusterRoleName: view
replicaCount: 2              # hoort niet bij clusterRoleBinding, dus geen spaties ervoor
```

Pas je stap 11 opnieuw toe? Gebruik dan `helm upgrade`, niet `helm install`: de release bestaat al.

```bash
helm upgrade headlamp headlamp/headlamp --version 0.46.0 -n headlamp -f k8s/platform/headlamp-values.yaml
kubectl get pods -n headlamp
helm history headlamp -n headlamp
```

Twee pods, en revisie 2. Draai terug naar revisie 1:

```bash
helm rollback headlamp 1 -n headlamp
kubectl get pods -n headlamp
```

Weer één pod. Net als `kubectl rollout undo` in module 09, maar dan voor alles in de chart tegelijk.
Zet hem terug op twee (zoals je values-bestand zegt):

```bash
helm upgrade headlamp headlamp/headlamp --version 0.46.0 -n headlamp -f k8s/platform/headlamp-values.yaml
```

---

## Breek het

### 💥 1. Een bestand buiten de map

```bash
mkdir k8s/overlays/kapot
cat > k8s/overlays/kapot/kustomization.yaml <<'EOF'
resources:
  - ../../base
configMapGenerator:
  - name: extra
    files:
      - ../../../app/db/links.sql
EOF
kubectl kustomize k8s/overlays/kapot
```

<details>
<summary>Uitleg</summary>

`security; file '.../app/db/links.sql' is not in or below '.../k8s/overlays/kapot'`.

Kustomize leest alleen bestanden in zijn eigen map of daaronder. Zo kan een kustomization die je
van internet haalt niet stiekem bestanden van elders op je computer meenemen. Daarom staat de
generator in `app/kustomization.yaml`: daar staan de bestanden ónder. Een andere **map** met een
kustomization (zoals `../../app` of `../../base`) mag je wel gebruiken.

```bash
rm -r k8s/overlays/kapot
```
</details>

### 💥 2. Een tikfout in een patch

```bash
cp -r k8s/overlays/test k8s/overlays/kapot
sed -i '' 's/        name: snip-web$/        name: snip-webb/' k8s/overlays/kapot/kustomization.yaml
kubectl kustomize k8s/overlays/kapot
```

<details>
<summary>Uitleg</summary>

`no matches for Id Deployment.v1.apps/snip-webb`: de patch zoekt een Deployment `snip-webb`, en
die bestaat niet in de base.

Fijn dat het zo streng is. Een patch die stilletjes niets doet, zou je pas merken als test zich
anders gedraagt dan je denkt.

```bash
rm -r k8s/overlays/kapot
```
</details>

### 💥 3. Een vergeten `--set`

Met `--set` geef je een waarde mee op de opdrachtregel, zonder values-bestand:

```bash
helm upgrade headlamp headlamp/headlamp --version 0.46.0 -n headlamp \
  -f k8s/platform/headlamp-values.yaml --set replicaCount=3
kubectl get deploy -n headlamp
```

Drie pods. Een week later werkt een collega de chart bij, op de gewone manier:

```bash
helm upgrade headlamp headlamp/headlamp --version 0.46.0 -n headlamp -f k8s/platform/headlamp-values.yaml
kubectl get deploy -n headlamp
```

<details>
<summary>Uitleg</summary>

Weer twee. Helm onthoudt een `--set` niet voor de volgende keer: bij elke `upgrade` begint hij bij
de standaardwaarden plus wat jij **nu** meegeeft. Je collega wist van niets.

Daarom staan alle instellingen in een values-bestand, in Git. Dan weet iedereen wat er draait, en
doet de volgende `upgrade` hetzelfde.
</details>

---

## Op je werk

### Geen YAML in je repo?

Grote kans dat je in je app-repo op je werk geen Deployment of Service vindt. Dat klopt. Het
platformteam heeft één chart voor alle apps, en jouw team levert alleen values, per omgeving:

```
platformteam:   de chart     → templates/deployment.yaml, service.yaml, hpa.yaml ...
jouw team:      values.yaml      ← wat overal geldt             (vergelijk k8s/base)
                values-tst.yaml  ← alleen de verschillen        (vergelijk k8s/overlays/test)
                values-acc.yaml
                values-prd.yaml
Argo CD:        chart + values  → de echte YAML → cluster
```

Het is hetzelfde idee als je Kustomize-base met overlays: een gemeenschappelijke base, en per
omgeving alleen wat anders is. Een later values-bestand overschrijft het eerdere:

```bash
helm template <chart> -f values.yaml -f values-prd.yaml
```

Het verschil: je kunt alleen de knoppen omzetten die het platformteam aanbiedt. Dat is ook de
bedoeling. Zo doet elk team het op dezelfde manier, met probes en resources.

De Deployments, probes en HPA's uit modules 09–13 bestaan dus wel. Ze zitten in de templates van
het platformteam. Wil je de echte YAML zien, kijk dan in Argo CD bij je app naar het tabblad
**Manifest**, of draai `helm template` zoals hierboven.

Staan er ook omgevingen als `pr`? Dat is meestal een tijdelijke omgeving per pull request, om een
wijziging te testen vóór de merge.

### Verder

- **Argo CD doet `helm install` niet.** Het maakt van een chart of kustomization zelf YAML
  (`helm template` / `kustomize build`) en past die toe. `helm list` is dan leeg: de release-
  geschiedenis zit in Argo CD en in Git. Terugdraaien doe je met Git, niet met `helm rollback`.
  Module 17.
- **De values staan soms niet in je app-repo**, maar in een aparte GitOps-repo. Je app-repo heeft
  dan alleen code, een Dockerfile en een workflow.
- **De nieuwe image-tag** komt in module 18 automatisch in Git: de pipeline past `newTag` in
  de kustomization aan (`kustomize edit set image`), of `image.tag` in een values-bestand.
- **Software van anderen** (cert-manager, External Secrets, Cilium, Envoy Gateway) installeer je
  bijna altijd met hun Helm chart, met een vaste `--version` en een values-bestand in Git.
- **Review vóór uitrol:** `kubectl diff -k` en `helm template` laten zien wat er echt verandert.
  Veel teams tonen dat automatisch in een pull request.

---

## Checkpoint

<details>
<summary>1. Wat is het verschil tussen Kustomize en Helm?</summary>

Kustomize: een base plus de verschillen per omgeving, zonder sjablonen. Helm: sjablonen met gaten,
die je invult met values. Kustomize vooral voor je eigen app, Helm vooral voor software van
anderen.
</details>

<details>
<summary>2. Waarom krijgen gegenereerde ConfigMaps een hash achter hun naam?</summary>

Verandert de inhoud, dan verandert de naam. De Deployment verwijst naar die nieuwe naam, en daardoor
rolt Kubernetes de pods vanzelf opnieuw uit met de nieuwe inhoud.
</details>

<details>
<summary>3. Wat staat er in <code>k8s/overlays/test/kustomization.yaml</code>?</summary>

Alleen de verschillen met de base: de namespace, een label, de image-tag en twee patches (minder
pods).
</details>

<details>
<summary>4. Waarom staat de <code>GatewayClass</code> in <code>k8s/platform/</code> en niet in de base?</summary>

Die geldt voor het hele cluster, en hoort dus één keer te bestaan, niet per omgeving. Op je werk
beheert het platformteam dat.
</details>

<details>
<summary>5. Waarom zet je Helm-instellingen in een values-bestand en niet met <code>--set</code>?</summary>

Helm onthoudt een `--set` niet. De volgende `upgrade` zonder die `--set` zet de waarde terug. Een
values-bestand in Git is voor iedereen hetzelfde.
</details>

<details>
<summary>6. In je app-repo op je werk staan geen Deployments. Waar zijn ze dan?</summary>

In de templates van de chart van het platformteam. Jouw team levert alleen values per omgeving
(`values-tst.yaml`, `values-prd.yaml`), en Argo CD maakt daar samen met de chart de echte YAML van.
Die zie je in Argo CD onder **Manifest**.
</details>

### Eindopdracht

Zorg dat:
1. je bestanden in de nieuwe indeling staan: `k8s/base/`, `k8s/overlays/test/`,
   `k8s/overlays/prod/`, `k8s/platform/` en
   `app/kustomization.yaml`; de drie ConfigMap-kopieën zijn weg;
2. prod draait in `default` via `kubectl apply -k k8s/overlays/prod`, en `kubectl diff -k k8s/overlays/prod` laat
   niets meer zien;
3. de omgeving test draait in `snip-test`, met de verschillen uit stap 5 en een eigen Gateway;
4. Headlamp met Helm is geïnstalleerd, met de rol `view` en 2 pods.

```bash
cd ~/Documents/local/docker-k8s-cursus/modules/14-kustomize-en-helm
./check.sh
```

Groen? Je hebt nu twee omgevingen (test en prod) in één cluster. Maar iedereen met toegang tot het cluster kan in
beide alles. In **module 15** geef je elke namespace eigen rechten en grenzen, en bepaal je welke
pods met elkaar mogen praten.

> De controlescripts van modules 08–13 zoeken nog naar de oude paden (`k8s/api/...`). Die hoeven
> niet meer groen te worden.

---

## Spiekbrief

| Commando | Wat het doet |
|---|---|
| `kubectl kustomize MAP` | laat de YAML zien die Kustomize maakt |
| `kubectl diff -k MAP` | wat zou er in het cluster veranderen? |
| `kubectl apply -k MAP` | toepassen |
| `kubectl get all -A -l env=test` | alles met een bepaald etiket |
| `helm repo add NAAM URL` / `helm repo update` | een chart-bron toevoegen / bijwerken |
| `helm search repo NAAM` | charts zoeken |
| `helm show values CHART` | wat kun je instellen? |
| `helm install RELEASE CHART -f values.yaml` | installeren |
| `helm upgrade RELEASE CHART -f values.yaml` | bijwerken |
| `helm list -A` / `helm history RELEASE` | releases / revisies |
| `helm rollback RELEASE REVISIE` | terugdraaien |
| `helm template RELEASE CHART -f values.yaml` | de YAML laten zien, zonder te installeren |

| kustomization.yaml | |
|---|---|
| `resources:` | bestanden en mappen die erbij horen |
| `configMapGenerator:` | ConfigMaps uit bestanden, met hash |
| `namespace:` | alles in deze namespace |
| `labels:` | een etiket op alles |
| `images:` | een andere image-tag |
| `patches:` | alleen de verschillen |
