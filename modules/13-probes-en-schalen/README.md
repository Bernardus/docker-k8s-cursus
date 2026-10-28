# Module 13 — Probes, resources en autoscaling

**Doel:** Kubernetes weet wanneer een pod gezond is en wanneer hij klaar is voor verkeer. Elke
pod krijgt een grens voor geheugen en CPU. En bij drukte komen er vanzelf API-pods bij.

**Tijd:** ±1,5 uur

**Nodig:** module 12 afgerond (snip draait helemaal in het cluster)

> 🖥️ **Podman Desktop:** blokjes zoals dit zijn ter controle, niet in plaats van.
> (Menunamen kunnen per versie iets verschillen.)

---

## Uitleg

### Draait is niet hetzelfde als gezond

Tot nu toe kijkt Kubernetes maar naar één ding: draait het proces nog? Zo ja, dan krijgt de pod
verkeer. Maar een proces kan draaien en toch niets kunnen: de database is weg, de app hangt, of
hij is nog aan het opstarten.

Daarvoor heb je **probes**: Kubernetes stelt de container regelmatig een vraag.

| Probe | De vraag | Antwoord "nee" betekent |
|---|---|---|
| **readiness** | "Ben je klaar voor verkeer?" | pod krijgt tijdelijk **geen verkeer** van de Service |
| **liveness** | "Leef je nog?" | Kubernetes **herstart** de container |
| **startup** | "Ben je al opgestart?" | nog even wachten met de andere twee |

De vraag stellen kan op drie manieren:

| Soort | Hoe | Voorbeeld |
|---|---|---|
| `httpGet` | een webadres opvragen; 200–399 is "ja" | de API: `/health` |
| `tcpSocket` | lukt het om verbinding te maken? | nginx op poort 80 |
| `exec` | een commando in de container; exit code 0 is "ja" | Postgres: `pg_isready` |

De API heeft daar al twee adressen voor (kijk maar in `app/api/src/index.ts`):
- `/health` antwoordt altijd "ok" zolang het proces werkt → **liveness**;
- `/health/db` antwoordt alleen "ok" als de database bereikbaar is → **readiness**.

### Requests en limits

Zonder afspraken mag elke pod zoveel CPU en geheugen pakken als hij wil. Eén pod met een
geheugenlek kan zo een hele node platleggen.

| | Betekenis | Wat Kubernetes ermee doet |
|---|---|---|
| **requests** | "dit heb ik minstens nodig" | zoekt een node waar dat nog vrij is, en reserveert het |
| **limits** | "hier ga ik nooit overheen" | CPU: de pod wordt **afgeremd**. Geheugen: de pod wordt **gestopt** (`OOMKilled`) |

De eenheden:
- **CPU** in millicores: `1000m` is één hele processorkern, `50m` is 5% daarvan;
- **geheugen** in `Mi` (mebibyte, ongeveer een megabyte) of `Gi`.

### Automatisch schalen

Een **HorizontalPodAutoscaler** (HPA) kijkt elke 15 seconden hoe druk de pods het hebben, en past
het aantal aan. "Druk" is hier: hoeveel CPU gebruiken ze, **als percentage van hun request**. Zonder
requests kan een HPA dus niet rekenen.

De cijfers komen van de **metrics-server**: een klein programma dat het gebruik van elke pod bijhoudt.
In kind moet je dat zelf installeren.

### Waar komen de woorden vandaan?

| Woord | Herkomst |
|---|---|
| **probe** | Latijn *probare*: testen, onderzoeken. In het Engels ook de sonde van een arts, of een ruimtesonde: iets wat je ergens in steekt om te kijken hoe het ervoor staat |
| **liveness / readiness** | gewoon Engels: *alive* (levend) en *ready* (klaar) + *-ness* (-heid) |
| **millicore** | Latijn *mille* (duizend) + Engels *core* (kern): een duizendste processorkern |
| **Mi, Gi** | *mebi-* en *gibi-*: "mega binary". 1Mi = 1024 × 1024 bytes, net iets meer dan 1 MB |
| **throttle** (afremmen) | Engels voor "keel dichtknijpen"; ook de gasklep van een motor |
| **OOMKilled** | *Out Of Memory*: de "OOM killer" van Linux stopt een proces dat te veel geheugen pakt. Exit code 137 = 128 + 9 (signaal 9, `SIGKILL`) |
| **horizontaal schalen** | meer machines náást elkaar. **Verticaal**: één grotere machine (alsof je hem hoger stapelt) |
| **metrics** | Grieks *metron*: maat |

---

## Lab

Je past drie bestanden aan: `k8s/api/deployment.yaml`, `k8s/web/deployment.yaml` en
`k8s/db/statefulset.yaml`. Plus één nieuw bestand: `k8s/api/hpa.yaml`.

### Deel A — Gezond of niet?

**1. Eerst een fout in de API**

Kijk naar je API-pods:

```bash
kubectl get pods -l app=snip-api
```

Grote kans dat er bij **RESTARTS** een `1` staat. Dat gebeurde in module 12, toen je de
database-pod weggooide. Bekijk de logs van vóór de herstart (vul de naam in van een pod met een
`1`):

```bash
kubectl logs snip-api-xxxxx --previous | grep -A3 "Unhandled 'error'"
```

`terminating connection due to administrator command`: de database stopte, de verbinding brak af,
en de API crashte daarop. Kubernetes startte hem opnieuw,
dus je merkte er weinig van. Maar het is een fout in de app.

Die fout is al opgelost in `app/api/src/index.ts` (zoek op `db.on('error'`). Je hoeft alleen een
nieuwe versie te laten bouwen, net als in module 05:

```bash
git add app/api/src/index.ts
git commit -m "API: overleeft een database-herstart"
git push
gh run watch
```

> De pipeline probeert daarna ook naar je droplet te deployen (module 07). Heb je die al
> weggegooid, dan faalt die stap. Geen probleem: het gaat om het image, en dat staat op GHCR.

De nieuwe tag is `sha-` plus de eerste 7 tekens van je commit:

```bash
echo sha-$(git rev-parse --short=7 HEAD)
```

Zet die tag in `k8s/api/deployment.yaml`, bij `image:` en in de `change-cause`. Nog niet toepassen:
dat doe je in de volgende stap, samen met de probes.

**2. Probes voor de API**

Zet in `k8s/api/deployment.yaml` onder het `env:`-blok (even ver ingesprongen als `env:`):

```yaml
          readinessProbe:              # klaar voor verkeer? (kan hij bij de database?)
            httpGet:
              path: /health/db
              port: 3000
            periodSeconds: 5
          livenessProbe:               # leeft het proces nog? (anders: herstarten)
            httpGet:
              path: /health
              port: 3000
            periodSeconds: 10
            failureThreshold: 3
```

- `periodSeconds`: hoe vaak de vraag gesteld wordt;
- `failureThreshold`: na hoeveel keer "nee" achter elkaar Kubernetes ingrijpt (standaard 3).

```bash
kubectl apply -f k8s/api/deployment.yaml
kubectl rollout status deploy/snip-api
kubectl describe pod -l app=snip-api | grep -E "Image:|Liveness|Readiness"
```

Je ziet de nieuwe tag, en de twee probes met hun instellingen.

**3. Probes voor de database en de website**

In `k8s/db/statefulset.yaml`, onder het `env:`-blok van `postgres`:

```yaml
          readinessProbe:              # neemt Postgres verbindingen aan?
            exec:
              command: ["pg_isready", "-h", "127.0.0.1", "-U", "postgres"]
            periodSeconds: 5
```

`pg_isready` is een klein programma dat in het Postgres-image zit. Met `-h 127.0.0.1` vraagt het
via het netwerk, zoals de API dat ook doet.

In `k8s/web/deployment.yaml`, onder `ports:` van `nginx`:

```yaml
          readinessProbe:              # geeft nginx de pagina?
            httpGet:
              path: /
              port: 80
          livenessProbe:               # luistert nginx nog?
            tcpSocket:
              port: 80
```

Open een **tweede terminal** en kijk mee:

```bash
kubectl get pods --watch
```

In je eerste terminal:

```bash
kubectl apply -f k8s/db/ -f k8s/web/
```

Kijk naar de tweede terminal. De database-pod start opnieuw, en een paar seconden lang staan je
API-pods op `0/1`: ze kunnen de database niet bereiken, dus ze zijn niet klaar. Zodra Postgres
`1/1` is, worden de API-pods dat ook. En **RESTARTS blijft gelijk**: de fout uit stap 1 is weg.

**4. De database weg**

Laat de tweede terminal meekijken. Zet de database even helemaal uit:

```bash
kubectl scale statefulset snip-db --replicas=0
```

Alle API-pods gaan naar `0/1`. Ze draaien nog wel, maar krijgen geen verkeer meer. Met je tunnel
uit module 10 (of open hem opnieuw):

```bash
curl -i localhost:8080/api/info
```

Een `503`: de Gateway heeft geen gezonde API-pods meer. De website zelf (`/`) werkt gewoon.

Zet de database terug:

```bash
kubectl scale statefulset snip-db --replicas=1
```

Binnen een paar seconden is alles weer `1/1`. Niemand is herstart.

> **Waarom liveness op `/health` en niet op `/health/db`?** Stel dat liveness ook naar de database
> kijkt. Dan herstart Kubernetes alle API-pods zodra de database even weg is. Dat lost niets op
> (het probleem zit in de database), en maakt alles alleen trager. Liveness vraagt dus alleen:
> werkt dít proces nog?

### Deel B — Resources

**5. De metrics-server**

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.9.0/components.yaml
```

In kind heeft de node geen officieel certificaat. Laat de metrics-server dat accepteren:

```bash
kubectl -n kube-system patch deployment metrics-server --type=json \
  -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
kubectl -n kube-system rollout status deployment metrics-server
```

Na een halve minuut:

```bash
kubectl top nodes
kubectl top pods
```

Zo zie je wat elke pod echt gebruikt. Een API-pod gebruikt bijvoorbeeld 1m CPU en 40Mi geheugen.

**6. Requests en limits**

Zet onder de probes van elke container een `resources:`-blok.

`k8s/api/deployment.yaml`:

```yaml
          resources:
            requests:                  # dit reserveert het cluster voor de pod
              cpu: 50m
              memory: 64Mi
            limits:                    # hier gaat hij nooit overheen
              cpu: 500m
              memory: 128Mi
```

`k8s/web/deployment.yaml`:

```yaml
          resources:
            requests:
              cpu: 10m
              memory: 16Mi
            limits:
              memory: 64Mi
```

`k8s/db/statefulset.yaml`:

```yaml
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              memory: 512Mi
```

De website en de database hebben geen CPU-limit. Bij drukte mogen ze vrije CPU gebruiken.
Een geheugenlimit hebben ze wel, want geheugen kun je niet afremmen. Op je werk zie je allebei:
zie "Op je werk".

```bash
kubectl apply -f k8s/api/deployment.yaml -f k8s/web/ -f k8s/db/
kubectl describe node | grep -A6 "Allocated resources"
```

Daar zie je hoeveel er van de node gereserveerd is: de requests van alle pods bij elkaar.

> 🖥️ **Podman Desktop:** onder **Kubernetes → Pods** zie je per pod het gebruik.

### Deel C — Automatisch schalen

**7. De HorizontalPodAutoscaler**

Maak `k8s/api/hpa.yaml`:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: snip-api
spec:
  scaleTargetRef:                # wat schalen we?
    apiVersion: apps/v1
    kind: Deployment
    name: snip-api
  minReplicas: 2                 # nooit minder dan 2
  maxReplicas: 6                 # nooit meer dan 6
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 50   # gemiddeld 50% van de cpu-request
```

De HPA bepaalt nu hoeveel pods er zijn. Haal daarom de regel `replicas: 3` weg uit
`k8s/api/deployment.yaml`. Anders zet elke `kubectl apply` het aantal weer op 3, en vechten
jij en de HPA om het aantal.

```bash
kubectl apply -f k8s/api/
kubectl get hpa
```

Een minuut later staat bij **TARGETS** zoiets als `cpu: 2%/50%`: 2% gebruik, doel 50%.

> Na het weghalen van `replicas` gaat de Deployment heel even naar 1 pod. De HPA zet hem binnen
> een paar seconden op 2, het minimum.

**8. Drukte maken**

In je tweede terminal (stop de `--watch` van eerder met `Ctrl+C`):

```bash
kubectl get hpa snip-api --watch
```

In je eerste terminal start je een pod die de API zonder pauze bestookt met verzoeken:

```bash
kubectl run belasting --image=busybox:1.37 --restart=Never -- \
  /bin/sh -c "while true; do wget -q -O /dev/null http://snip-api/api/info; done"
```

Binnen 1 à 2 minuten gaat het gebruik boven de 50%, en gaat **REPLICAS** omhoog, tot 5 of 6.
Kijk ook naar:

```bash
kubectl top pods -l app=snip-api
```

Stop de drukte:

```bash
kubectl delete pod belasting
```

Het gebruik zakt meteen. Het aantal pods zakt pas na **5 minuten**. Dat is expres: zo schiet het
aantal niet heen en weer bij elke korte piek. Wacht het af, en je hebt er weer 2.

---

## Breek het

Elke keer verander je iets "live", zonder je bestand aan te passen. Daarna zet je alles terug met
`kubectl apply -f k8s/api/deployment.yaml`.

### 💥 1. Een liveness probe op de verkeerde poort

```bash
sed '/livenessProbe/,/periodSeconds/s/port: 3000/port: 3001/' k8s/api/deployment.yaml | kubectl apply -f -
kubectl get pods -l app=snip-api --watch
```

Wacht een minuut. Wat zie je bij RESTARTS?

<details>
<summary>Uitleg</summary>

Elke pod wordt om de ±30 seconden herstart (3 keer "nee", met 10 seconden ertussen).

```bash
kubectl get events --field-selector reason=Unhealthy | tail -3
```

`Liveness probe failed: ... connection refused`: er luistert niets op poort 3001.

Let op: de rollout ging gewoon door. De **readiness** probe was in orde, dus Kubernetes vond de
nieuwe pods goed. Een verkeerde liveness probe merk je pas later, en dan bij álle pods. Test je
probes dus altijd.

```bash
kubectl apply -f k8s/api/deployment.yaml
```
</details>

### 💥 2. Te weinig geheugen

```bash
sed -e 's/memory: 128Mi/memory: 16Mi/' -e 's/memory: 64Mi/memory: 16Mi/' \
  k8s/api/deployment.yaml | kubectl apply -f -
kubectl get pods -l app=snip-api --watch
```

<details>
<summary>Uitleg</summary>

De nieuwe pod gaat naar `OOMKilled` en dan `CrashLoopBackOff`.

```bash
kubectl describe pod -l app=snip-api | grep -A3 "Last State"
```

`Reason: OOMKilled`, `Exit Code: 137`: Node.js heeft meer dan 16Mi nodig, en Kubernetes stopte hem.

Maar snip werkt gewoon door. Door `maxUnavailable: 0` (module 09) blijven de oude pods draaien tot
de nieuwe gezond is. Dat gebeurt nooit, dus de rollout blijft hangen, maar je gebruikers merken
niets.

(Waarom ook de request naar 16Mi? Een request mag niet groter zijn dan de limit. Anders weigert
Kubernetes het bestand.)

```bash
kubectl apply -f k8s/api/deployment.yaml
```
</details>

### 💥 3. Te veel gevraagd

```bash
sed -e 's/cpu: 50m/cpu: "20"/' -e 's/cpu: 500m/cpu: "20"/' \
  k8s/api/deployment.yaml | kubectl apply -f -
kubectl get pods -l app=snip-api
```

<details>
<summary>Uitleg</summary>

Eén nieuwe pod staat op `Pending`, en blijft daar.

```bash
kubectl get events --field-selector reason=FailedScheduling | tail -1
```

`Insufficient cpu`: de pod vraagt 20 hele processorkernen, en geen enkele node heeft die vrij.
Kubernetes plaatst een pod alleen als zijn **request** past. Ook hier blijven de oude pods draaien.

```bash
kubectl apply -f k8s/api/deployment.yaml
```
</details>

---

## Op je werk

- **Zonder requests en limits kom je er niet in.** Platformteams dwingen dat vaak af: met een
  *LimitRange* of *ResourceQuota* per namespace (module 15), of met een policy-tool als Kyverno.
  Je deploy wordt dan geweigerd.
- **CPU-limits: er is discussie.** Veel teams zetten wel een request en een geheugenlimit, maar
  geen CPU-limit, om onnodig afremmen te voorkomen. Volg wat jullie platformteam afspreekt.
- **Op AKS** staat de metrics-server er standaard op. Naast de HPA kom je **KEDA** tegen: die
  schaalt ook op andere dingen, zoals het aantal berichten in een wachtrij.
- **Pending door te weinig ruimte?** Op AKS zet de *cluster autoscaler* er dan een node bij. Dat
  is wat je in Breek het 3 zag, maar dan opgelost.
- **Liveness nooit op een afhankelijkheid** (database, andere API). Over readiness op de database
  verschillen de meningen; bij sommige teams kijkt readiness alleen naar de app zelf.
- **Trage starters** (Java/Spring Boot) krijgen een **startupProbe**. Zo wacht Kubernetes rustig
  op het opstarten, en grijpt de liveness probe daarna wél snel in.
- **HPA en Argo CD:** staat `replicas` in Git, dan zet Argo CD het aantal steeds terug. Daarom
  haal je het weg, net als in stap 7. Daar kom je in module 17 op terug.

---

## Checkpoint

<details>
<summary>1. Wat gebeurt er als een readiness probe faalt? En een liveness probe?</summary>

Readiness: de pod krijgt tijdelijk geen verkeer, maar blijft draaien. Liveness: Kubernetes herstart
de container.
</details>

<details>
<summary>2. Waarom kijkt de liveness probe van de API niet naar de database?</summary>

Dan herstart Kubernetes alle API-pods zodra de database weg is. Dat lost niets op: het probleem zit
in de database, niet in de API.
</details>

<details>
<summary>3. Een pod gaat over zijn geheugenlimit. Wat gebeurt er? En bij zijn CPU-limit?</summary>

Geheugen: de container wordt gestopt (`OOMKilled`). CPU: de container wordt afgeremd, maar draait
door.
</details>

<details>
<summary>4. Waarom staat er geen <code>replicas</code> meer in de Deployment van de API?</summary>

De HPA bepaalt het aantal. Met `replicas` in het bestand zet elke `kubectl apply` (of Argo CD) het
aantal terug, en vecht je met de HPA.
</details>

<details>
<summary>5. "50%" in de HPA: 50% van wat?</summary>

Van de CPU-**request** (50m). Gebruiken de pods gemiddeld meer dan 25m, dan komen er pods bij.
</details>

### Eindopdracht

Zorg dat:
1. de API draait met je nieuwe image (stap 1);
2. de API een readiness probe heeft op `/health/db` en een liveness probe op `/health`; de
   database en de website hebben een readiness probe;
3. alle drie requests (CPU en geheugen) en een geheugenlimit hebben;
4. `kubectl top` werkt;
5. de HPA `snip-api` bestaat, en `k8s/api/deployment.yaml` geen `replicas` meer heeft;
6. de HPA in het afgelopen uur heeft opgeschaald (stap 8);
7. alles weer gezond is, en de pod `belasting` weg is.

```bash
cd ~/Documents/local/docker-k8s-cursus/modules/13-probes-en-schalen
./check.sh
```

Groen? Je app is nu zelfherstellend én schaalt mee. Maar je hebt inmiddels 13 YAML-bestanden, en
voor een tweede omgeving (test, productie) zou je ze allemaal moeten kopiëren. In **module 14**
lost Helm (en Kustomize) dat op.

---

## Spiekbrief

| Commando | Wat het doet |
|---|---|
| `kubectl describe pod NAAM` | probes, resources, `Last State` (bijv. `OOMKilled`) |
| `kubectl get events --field-selector reason=Unhealthy` | gefaalde probes |
| `kubectl top nodes` / `kubectl top pods` | echt gebruik (metrics-server nodig) |
| `kubectl describe node \| grep -A6 "Allocated"` | wat er gereserveerd is |
| `kubectl get hpa --watch` | de autoscaler aan het werk |
| `kubectl scale statefulset NAAM --replicas=0` | tijdelijk uitzetten |

| YAML (per container) | |
|---|---|
| `readinessProbe` | klaar voor verkeer? Nee → geen verkeer |
| `livenessProbe` | leeft hij nog? Nee → herstart |
| `startupProbe` | nog aan het opstarten? Dan wachten de andere twee |
| `httpGet` / `tcpSocket` / `exec` | hoe de vraag gesteld wordt |
| `resources.requests` | minimaal nodig, wordt gereserveerd |
| `resources.limits` | maximum: CPU afgeremd, geheugen `OOMKilled` |

| YAML | |
|---|---|
| `kind: HorizontalPodAutoscaler` | schaalt een Deployment op CPU-gebruik |
