# Module 17 — Argo CD

**Doel:** je typt geen `kubectl apply` meer. Je zet een wijziging in Git, en **Argo CD** rolt hem
uit. Test gaat vanzelf, prod pas als jij op Sync drukt. Past iemand iets met de hand aan, dan zet
Argo CD het terug. En terugdraaien doe je met Git.

**Tijd:** ±2 uur

**Nodig:** module 15 afgerond (snip draait in `default` en `snip-test`)

> 🖥️ **Podman Desktop:** blokjes zoals dit zijn ter controle, niet in plaats van.
> (Menunamen kunnen per versie iets verschillen.)

---

## Uitleg

### Wie drukt er op de knop?

Tot nu toe ging het zo:

```
jij → git push            (Git klopt)
jij → kubectl apply -k    (het cluster klopt, als je het niet vergeet)
```

Twee stappen, en de tweede doe je met de hand. Vergeet je hem, of doe je hem op de verkeerde
branch, dan lopen Git en het cluster uit elkaar. In module 16 zag je hoe lastig het dan is om te
zien wat er anders is.

Met **GitOps** is Git de enige knop:

```
jij → git push
Argo CD → kijkt elke minuut in Git → ziet een verschil → past het cluster aan
```

Argo CD draait **in** het cluster. Het haalt de YAML zelf op (*pull*). Niemand van buiten hoeft
rechten op het cluster te hebben: geen laptop, en ook geen GitHub Actions. Dat is veiliger dan een
pipeline die `kubectl apply` doet (*push*), zoals je in module 07 met SSH deed.

### Het controller-patroon, weer

Je kent het nu: een object beschrijft wat je wilt, een controller zorgt dat het zo is.

| Object | Controller | Zorgt dat |
|---|---|---|
| Deployment | ingebouwd | er genoeg pods zijn |
| HorizontalPodAutoscaler | ingebouwd + metrics-server | het aantal pods past bij de drukte |
| NetworkPolicy | de CNI (kindnet, Cilium) | alleen toegestaan verkeer doorkomt |
| **Application** | **Argo CD** | **het cluster gelijk is aan een map in Git** |

Een **Application** zegt drie dingen:

- **source**: welke repo, welke branch, welke map (bijvoorbeeld `k8s/overlays/test`);
- **destination**: welk cluster en welke namespace;
- **syncPolicy**: mag Argo CD zelf uitrollen, of wacht het op jou?

### Synced en Healthy

Argo CD geeft elke Application twee statussen:

| Status | Vraag | Waarden |
|---|---|---|
| **Sync** | Is het cluster gelijk aan Git? | `Synced` / `OutOfSync` |
| **Health** | Werkt het? | `Healthy` / `Progressing` / `Degraded` / `Missing` |

Ze staan los van elkaar. `Synced` + `Degraded` betekent: precies wat in Git staat, maar dat werkt
niet (een tikfout in Git). `OutOfSync` + `Healthy` betekent: het werkt, maar het is niet wat in
Git staat (iemand heeft met de hand iets aangepast).

### Drie knoppen in de syncPolicy

| Instelling | Wat Argo CD doet |
|---|---|
| *(geen `automated`)* | alleen kijken en het verschil laten zien. Jij drukt op **Sync** |
| `automated` | zelf uitrollen als Git verandert |
| `prune: true` | weg uit Git? Dan ook weg uit het cluster |
| `selfHeal: true` | met de hand aangepast? Dan meteen terugzetten |

Zonder `prune` blijft een object staan dat je uit Git haalt. Zonder `selfHeal` blijft een
handmatige wijziging staan, tot de volgende commit.

Let op: `prune` gaat alleen over objecten die Argo CD **zelf** heeft uitgerold. Een object dat
iemand met `kubectl` heeft toegevoegd, kent Argo CD niet, en ruimt het ook niet op.

### Waar komen de woorden vandaan?

| Woord | Herkomst |
|---|---|
| **Argo** | het schip van Jason en de *Argonauten* uit de Griekse mythe. Past bij de scheepvaart van Kubernetes (Grieks: stuurman) en Helm (roer). Het logo is een octopus |
| **GitOps** | *Git* + *operations* (beheer): je beheert het cluster via Git. Bedacht in 2017 door het bedrijf Weaveworks |
| **CD** | *Continuous Delivery*: steeds, in kleine stapjes, uitrollen. Latijn *continuus*: aan elkaar vast |
| **sync** | Grieks *syn* (samen) + *chronos* (tijd): gelijk laten lopen |
| **reconcile** | Latijn *reconciliare*: weer verzoenen. De controller verzoent het cluster met Git, steeds opnieuw |
| **drift** | Engels/Nederlands *drijven*: langzaam afdrijven van waar je hoort |
| **prune** | Frans *prooignier*: snoeien. Weghalen wat er niet meer hoort |
| **heal** | Oudengels *hǣlan*: heel maken (vergelijk *heel*, *heilig*) |
| **manifest** | Latijn *manifestus*: met de hand te grijpen, duidelijk. Een YAML-bestand dat zegt wat er moet zijn |
| **revision** | Latijn *revidere*: opnieuw bekijken. Een versie in Git (een commit of een tag) |
| **rollback** | Engels *to roll back*: terugrollen, naar een vorige versie |

---

## Lab

```bash
cd ~/Documents/local/docker-k8s-cursus
kubectl config current-context        # kind-snip
```

Je tunnels naar prod (8080) en test (8081) mogen openblijven.

### Deel A — Klaarzetten

**1. Alles in Git**

Argo CD leest je YAML van **GitHub**, niet van je laptop. Wat niet gepusht is, bestaat voor Argo CD
niet. Zet dus eerst alles erin:

```bash
git status
git add -A
git commit -m "Kustomize, teams en grenzen"
git push
```

Kijk op GitHub of `k8s/base/` en `k8s/overlays/` er staan. Je repo is openbaar, dus Argo CD heeft
geen wachtwoord nodig.

**2. Argo CD installeren**

Argo CD is gewoon software in je cluster. Je installeert het met Helm, net als Headlamp in module
14. Eerst de instellingen:

```bash
cat > k8s/platform/argocd-values.yaml <<'YAML'
# Argo CD in kind: alleen wat we nodig hebben.
configs:
  params:
    server.insecure: true          # geen eigen HTTPS: we komen binnen via port-forward
  cm:
    timeout.reconciliation: 60s    # elke minuut in Git kijken (standaard: 2 minuten)
dex:
  enabled: false                   # geen inloggen via GitHub of Entra ID, alleen admin
notifications:
  enabled: false                   # geen berichten naar Slack of Teams
YAML
```

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd --version 10.11.6 \
  -n argocd --create-namespace -f k8s/platform/argocd-values.yaml
kubectl get pods -n argocd --watch
```

Wacht tot alles `Running` is (Ctrl-C). Je ziet onder andere:

| Pod | Wat het doet |
|---|---|
| `argocd-repo-server` | haalt je repo op en maakt er YAML van (draait `kustomize build` of `helm template`) |
| `argocd-application-controller` | vergelijkt die YAML met het cluster, en past het cluster aan |
| `argocd-server` | de website en de API |
| `argocd-redis` | een cache, zodat niet alles steeds opnieuw hoeft |

**3. De website**

In een **nieuwe terminal** (laat hem open):

```bash
kubectl port-forward -n argocd svc/argocd-server 8090:80
```

Het wachtwoord van `admin` maakt Argo CD zelf, in een Secret:

```bash
kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
```

Open <http://localhost:8090> en log in als `admin`. Er staat nog niets: je hebt nog geen
Application.

### Deel B — Je eerste Application

**4. Test aan Argo CD geven**

Een Application is ook gewoon YAML. Hij hoort bij het cluster, dus komt hij in `k8s/platform/`:

```bash
mkdir -p k8s/platform/argocd
cat > k8s/platform/argocd/snip-test.yaml <<'YAML'
# Omgeving test: Argo CD houdt snip-test gelijk aan k8s/overlays/test in Git.
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: snip-test
  namespace: argocd                # Applications staan altijd bij Argo CD zelf
spec:
  project: default
  source:                          # wat: deze map, in deze repo, op deze branch
    repoURL: https://github.com/Bernardus/docker-k8s-cursus.git
    targetRevision: main
    path: k8s/overlays/test
  destination:                     # waar: dit cluster, deze namespace
    server: https://kubernetes.default.svc
    namespace: snip-test
YAML
kubectl apply -f k8s/platform/argocd/snip-test.yaml
```

(Staat je repo onder een andere GitHub-naam? Pas `repoURL` dan aan.)

`https://kubernetes.default.svc` is het adres van de API-server, gezien van binnen het cluster:
"dit cluster". Argo CD kan ook andere clusters beheren (module 25).

Kijk in de UI. De Application staat op **OutOfSync**, met een geel icoon bij elk object. Maar alles
draait toch al?

<details>
<summary>Waarom OutOfSync?</summary>

Argo CD heeft deze objecten niet zelf uitgerold. Het wil op elk object een etiket zetten
(`argocd.argoproj.io/tracking-id`), zodat het weet: "deze is van mij". Klik op de Application,
dan op de Deployment `snip-web`, dan op **Diff**: het enige verschil is dat etiket.
</details>

**5. Sync**

Klik op **Sync**, dan **Synchronize**. Na een paar seconden: **Synced** en **Healthy**.

```bash
kubectl get pods -n snip-test
kubectl get deploy -n snip-test snip-web -o jsonpath='{.metadata.annotations.argocd\.argoproj\.io/tracking-id}'; echo
```

Kijk naar `AGE`: geen enkele pod is herstart. Argo CD heeft alleen het etiket gezet. De pods
veranderen niet, want hun template is gelijk gebleven.

Klik in de UI rond. Je ziet de boom: Deployment → ReplicaSet → pods, Service → EndpointSlice. De
Secret `snip-db` staat er **niet** bij: die staat niet in Git (module 11), dus Argo CD kent hem
niet. In module 21 komt hij uit Azure Key Vault.

> 🖥️ **Headlamp:** kijk bij de Deployment `snip-web` naar de annotations. Daar staat nu de
> `tracking-id`.

### Deel C — Laat Argo CD het werk doen

**6. Automatisch**

Zet onderaan `k8s/platform/argocd/snip-test.yaml`:

```yaml
  syncPolicy:
    automated:                     # zelf uitrollen als Git verandert
      prune: true                  #   weg uit Git = weg uit het cluster
      selfHeal: true               #   met de hand aangepast = terugzetten
```

```bash
kubectl apply -f k8s/platform/argocd/snip-test.yaml
```

In de UI staat nu **Auto sync is enabled**.

> 💡 De Application zelf zet je nog met `kubectl apply` neer. Dat is het kip-en-ei-probleem: wie
> rolt Argo CD's eigen YAML uit? In module 23 laat je Argo CD ook dat doen ("app of apps").

**7. Self-heal: met de hand aanpassen**

Een collega schaalt de website "even" op:

```bash
kubectl scale deploy -n snip-test snip-web --replicas=4
kubectl get deploy -n snip-test snip-web --watch
```

Binnen een paar seconden staat hij weer op 1. In Git staat 1, dus is het 1. Stop met Ctrl-C.

**8. Uitrollen via Git**

Nu de goede manier. Zet in `k8s/overlays/test/kustomization.yaml`, in de patch voor `snip-web`,
`replicas: 1` op `replicas: 2`. Dan:

```bash
git add k8s/overlays/test/kustomization.yaml
git commit -m "test: twee webpods"
git push
kubectl get pods -n snip-test --watch
```

Binnen twee minuten komt er een tweede web-pod. (Geen zin om te wachten? Klik in de UI op
**Refresh**.) In de UI zie je bij **Last Sync** jouw commit, met je bericht erbij.

Vanaf nu doe je in snip-test geen `kubectl apply -k` meer. Git is de knop.

### Deel D — Prod: met de hand, en terugdraaien

**9. Prod aan Argo CD geven**

Voor prod wil je wel zien wat er verandert, maar zelf beslissen wanneer:

```bash
cat > k8s/platform/argocd/snip-prod.yaml <<'YAML'
# Omgeving prod: Argo CD ziet het verschil met Git, maar jij drukt op Sync.
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: snip-prod
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/Bernardus/docker-k8s-cursus.git
    targetRevision: main
    path: k8s/overlays/prod
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  # geen syncPolicy: prod rolt alleen uit als iemand op Sync drukt
YAML
kubectl apply -f k8s/platform/argocd/snip-prod.yaml
```

Klik in de UI op **snip-prod**, dan **Sync** → **Synchronize**. Nu is ook prod **Synced**.

Zet de bestanden van Argo CD zelf ook in Git:

```bash
git add k8s/platform
git commit -m "Argo CD met test en prod"
git push
```

**10. Een nieuwe versie naar prod**

Stel: er is een nieuwe versie van de API, `sha-4000a15`. (Eigenlijk is het een oudere, maar dat
merk je zo aan het versienummer.) Zet in `k8s/overlays/prod/kustomization.yaml` de `newTag` op
`sha-4000a15`, en:

```bash
git add k8s/overlays/prod/kustomization.yaml
git commit -m "prod: sha-4000a15"
git push
```

Klik op **Refresh** bij snip-prod. Hij wordt **OutOfSync**, maar er gebeurt verder niets. Klik op
**App Diff**: je ziet precies de regel met het image. Dat is je laatste controle.

Klik op **Sync** → **Synchronize**, en kijk:

```bash
curl -s localhost:8080/api/info; echo
```

`"versie":"sha-4000a15"`.

**11. Snel terug: Rollback**

De nieuwe versie blijkt slecht. Snel terug: klik bij snip-prod op **History and Rollback**. Je ziet
elke sync, met de commit erbij. Klik bij de vorige op de drie puntjes → **Rollback** → **OK**.

```bash
curl -s localhost:8080/api/info; echo
```

Weer `sha-9743b8d`. Maar kijk naar de status: **OutOfSync**. Waarom?

<details>
<summary>Uitleg</summary>

In Git staat nog steeds `sha-4000a15`. Rollback zet het cluster terug, maar Git niet. Het is een
noodknop, geen oplossing.

Daarom kan Rollback ook alleen zonder `automated`. Probeer het bij snip-test: de knop zegt
`rollback cannot be initiated when auto-sync is enabled`. Logisch: met auto-sync zou Argo CD je
rollback meteen weer terugdraaien naar wat in Git staat.
</details>

**12. Goed terug: via Git**

De echte oplossing: Git terugzetten. `git revert` maakt een nieuwe commit die de vorige ongedaan
maakt:

```bash
git revert --no-edit HEAD
git push
```

Klik op **Refresh**: snip-prod is weer **Synced**, zonder dat je op Sync hoeft te drukken. Het
cluster was al gelijk aan wat Git nu zegt.

In Git zie je nu precies wat er gebeurd is: een release, en een revert. Dat is je logboek.

---

## Breek het

### 💥 1. Een tikfout in Git

Zet in `k8s/overlays/test/kustomization.yaml` bij `resources` `../../basis` in plaats van
`../../base`. Commit en push. Klik op **Refresh** bij snip-test.

Wat gebeurt er met de Application? En met je pods?

<details>
<summary>Uitleg</summary>

De sync-status wordt **Unknown**, met een rode melding: `kustomize build ... failed`. Argo CD
kan van je map geen YAML maken. Je pods blijven gewoon draaien: Argo CD past niets aan als het niet
weet wat er moet.

Herstel via Git:

```bash
git revert --no-edit HEAD
git push
```

Daarom test je in CI of `kubectl kustomize` werkt, vóór het naar main gaat (module 18).
</details>

### 💥 2. Iets weghalen uit Git

Haal in `k8s/base/kustomization.yaml` de regel `- web/route.yaml` weg. Commit, push, en klik op
**Refresh** bij beide Applications. Open <http://localhost:8081> en <http://localhost:8080>.

<details>
<summary>Uitleg</summary>

**Test** (`prune: true`): de HTTPRoute `snip-web` is weggegooid. De website geeft een 404: de
voordeur weet niet meer waar `/` heen moet. De API (`/api`) werkt nog wel.

**Prod** (geen `automated`): **OutOfSync**, en de route staat er nog. In de UI staat hij met een
prullenbakje: "deze moet weg". Pas als je op Sync drukt (en **Prune** aanvinkt), gaat hij weg.

Dat is het verschil: test krijgt meteen je fout, prod niet. Herstel:

```bash
git revert --no-edit HEAD
git push
```
</details>

### 💥 3. Even snel iets aanpassen

Het is druk, en je collega wil de API in test **nu** op een andere versie:

```bash
kubectl set image -n snip-test deploy/snip-api api=ghcr.io/bernardus/snip-api:sha-4000a15
kubectl get pods -n snip-test --watch
```

Wat gebeurt er? Hoe had het wél gekund?

<details>
<summary>Uitleg</summary>

Er start een nieuwe pod, en meteen daarna wordt hij weer vervangen door de oude versie. Self-heal
zet het terug naar Git. Je collega denkt dat het niet werkt.

Wil je echt even iets met de hand doen (bijvoorbeeld bij een storing), dan heb je twee opties:

- **in Git** aanpassen: dan rolt Argo CD het uit (de goede manier);
- **auto-sync tijdelijk uitzetten**: in de UI bij **Details** → **Disable Auto-Sync**. Dan blijft
  je wijziging staan. Vergeet niet hem weer aan te zetten (en Git bij te werken).

Op je werk kom je dit tegen bij de "1m-truc" (zie hieronder).
</details>

---

## Op je werk

- **Jullie Application** ziet er anders uit dan de jouwe. Er zijn twee bronnen (*multi-source*):
  de chart van het platformteam, en jullie values uit de app-repo:

  ```yaml
  spec:
    sources:
      - repoURL: https://github.com/<org>/<jullie-app>.git
        targetRevision: 5.48.5                      # een git-tag van jullie app
        ref: values                                 # "noem deze bron $values"
      - repoURL: <acr>.azurecr.io/charts            # de chart, uit de registry (OCI)
        chart: frontend
        targetRevision: 1.18.4                      # een vaste versie van de chart
        helm:
          valueFiles:
            - $values/helm/values.yml               # voor alle omgevingen
            - $values/helm/<jullie-app>-tst/values.yml   # alleen voor tst
    destination:
      namespace: <jullie-app>-tst
    syncPolicy:
      automated:
        prune: true
      syncOptions:
        - CreateNamespace=false                     # de namespace maakt het platformteam
  ```

  Het is hetzelfde idee als jouw `base` + `overlays/test`: één chart, met per omgeving een
  values-bestand erbij. En de Application maak je meestal niet zelf: die maakt het platformteam,
  vaak met een **ApplicationSet** (module 23).
- **Nieuwe versie uitrollen** betekent bij jullie: `targetRevision` (de git-tag) of de image-tag in
  de values ophogen. Dat doet de pipeline, met een commit of pull request. Module 18.
- **De Manifest-tab** in de UI laat de YAML zien die Argo CD van de chart + values maakt. Daar zie
  je wat er écht uitgerold wordt, ook al staat er bij jullie geen YAML in de repo.
- **AppProject:** jullie Applications zitten in een project dat zegt welke repo's, namespaces en
  soorten objecten mogen. Daarom kun je via Argo CD geen ClusterRole aanmaken, ook al staat hij in
  je chart.
- **Rechten in Argo CD** staan los van RBAC in Kubernetes. Misschien mag je in de UI op Sync
  drukken voor tst, maar niet voor prd.
- **De 1m-truc na een storing.** Secrets komen bij jullie uit Azure Key Vault, via de **External
  Secrets Operator** (ESO, module 21). ESO haalt een secret elke `refreshInterval` opnieuw op,
  bijvoorbeeld elk uur. Na een grote storing (*disaster recovery*) kan het dan een uur duren voor
  alle Secrets er weer zijn. Tot die tijd blijven pods hangen op `CreateContainerConfigError`
  (module 16).

  De truc: zet `refreshInterval` tijdelijk op `1m`. Maar:
  - pas je het met de hand aan in het cluster, dan zet **self-heal** het terug op `1h` (Breek het
    3). Doe het dus in de **values in Git**, of zet auto-sync even uit;
  - zet het daarna weer terug: elke minuut alle secrets ophalen kost veel aanvragen bij Key Vault,
    en die heeft een limiet;
  - een Secret die als `env` in een pod zit, wordt pas gebruikt na een herstart:
    `kubectl rollout restart deploy/<naam>`.

  Eén Secret meteen ophalen kan ook zonder de truc:

  ```bash
  kubectl annotate externalsecret <naam> -n <namespace> force-sync=$(date +%s) --overwrite
  ```

- **HPA en replicas:** staat er `replicas` in je Deployment én schaalt een HPA, dan vechten Argo
  CD en de HPA. Daarom staat bij snip-api geen `replicas` (module 13). Charts laten `replicas` weg
  als de HPA aanstaat.

---

## Checkpoint

<details>
<summary>1. Wat is het verschil tussen <em>push</em> (een pipeline doet <code>kubectl apply</code>) en <em>pull</em> (Argo CD)?</summary>

Bij push heeft iets buiten het cluster (de pipeline) rechten op het cluster nodig. Bij pull draait
Argo CD in het cluster en haalt het zelf de YAML uit Git. Niemand van buiten hoeft erbij, en Argo
CD blijft daarna ook kijken of het nog klopt.
</details>

<details>
<summary>2. Wat is het verschil tussen <em>Synced</em> en <em>Healthy</em>?</summary>

Synced: het cluster is gelijk aan Git. Healthy: het werkt (pods klaar, rollout af). Je kunt Synced
zijn met iets kapots in Git, en Healthy terwijl het niet in Git staat.
</details>

<details>
<summary>3. Wat doen <code>prune</code> en <code>selfHeal</code>?</summary>

`prune`: een object dat uit Git verdwijnt, gooit Argo CD ook uit het cluster. `selfHeal`: een
object dat met de hand is aangepast, zet Argo CD terug naar Git.
</details>

<details>
<summary>4. Iemand maakt met <code>kubectl</code> een extra NetworkPolicy. Ruimt Argo CD die op?</summary>

Nee. Argo CD beheert alleen objecten die het zelf heeft uitgerold (met het tracking-etiket). Een
object dat nooit in Git stond, ziet het niet.
</details>

<details>
<summary>5. Waarom is Rollback in Argo CD geen echte oplossing?</summary>

Het zet het cluster terug, maar Git niet. De Application wordt OutOfSync, en met auto-sync zou
Argo CD het meteen weer terugdraaien. De echte oplossing is `git revert`.
</details>

<details>
<summary>6. Je pusht een commit, maar Argo CD doet niets. Wat kan er aan de hand zijn?</summary>

Argo CD kijkt maar elke paar minuten (druk op Refresh). Of de Application kijkt naar een andere
branch of map (`targetRevision`, `path`). Of `kustomize build` faalt (status Unknown met een
melding). Of er staat geen `automated`, en het wacht op jou.
</details>

<details>
<summary>7. Waarom zou je test automatisch laten uitrollen en prod niet?</summary>

Test mag stuk gaan: daar wil je fouten snel zien. Bij prod wil je eerst de diff bekijken, en zelf
kiezen wanneer het gebeurt. Veel teams laten prod later ook automatisch gaan, maar dan via een pull
request met goedkeuring (module 24).
</details>

### Eindopdracht

Zorg dat:
1. Argo CD draait, geïnstalleerd met Helm en `k8s/platform/argocd-values.yaml`;
2. `snip-test` automatisch uitrolt, met `prune` en `selfHeal`;
3. `snip-prod` wacht tot iemand op Sync drukt;
4. beide **Synced** en **Healthy** zijn, en alles in Git staat en gepusht is.

```bash
cd modules/17-argo-cd
./check.sh
```

Het script schaalt snip-web in test even op, en kijkt of Argo CD het terugzet.

Groen? Dan rolt Argo CD nu uit wat er in Git staat. Maar de nieuwe image-tag zet je nog met de
hand in Git. In **module 18** doet de pipeline dat: GitHub Actions bouwt een image, en zet de
nieuwe tag in Git. Argo CD doet de rest.

---

## Spiekbrief

| Commando | Wat het doet |
|---|---|
| `helm install argocd argo/argo-cd --version 10.11.6 -n argocd --create-namespace -f ...` | Argo CD installeren |
| `kubectl port-forward -n argocd svc/argocd-server 8090:80` | de UI op <http://localhost:8090> |
| `kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath='{.data.password}' \| base64 -d` | wachtwoord van admin |
| `kubectl get applications -n argocd` | alle Applications, met sync en health |
| `kubectl describe application -n argocd NAAM` | details, fouten en geschiedenis |
| `git revert --no-edit HEAD` | de laatste commit ongedaan maken, met een nieuwe commit |

| In de UI | |
|---|---|
| **Refresh** | nu in Git kijken (niet wachten) |
| **Sync** | uitrollen wat in Git staat |
| **App Diff** | wat is er anders dan Git? |
| **History and Rollback** | eerdere syncs, en noodknop terug (alleen zonder auto-sync) |
| **Details** → **Disable Auto-Sync** | auto-sync tijdelijk uit |

| YAML (`Application`) | |
|---|---|
| `source.repoURL` / `targetRevision` / `path` | welke repo, welke branch of tag, welke map |
| `destination.server` / `namespace` | welk cluster, welke namespace |
| `syncPolicy.automated` | zelf uitrollen |
| `automated.prune` | weg uit Git = weg uit het cluster |
| `automated.selfHeal` | met de hand aangepast = terugzetten |
| `syncOptions: [CreateNamespace=true]` | namespace maken als hij er niet is |
