# Module 12 — Opslag: de database in het cluster

**Doel:** Postgres draait in je cluster, met een eigen schijf die blijft bestaan als de pod
verdwijnt. Daarna werkt snip in Kubernetes helemaal: links maken, en erop klikken.

**Tijd:** ±1 uur

**Nodig:** module 11 afgerond (Secret `snip-db`, de API gebruikt het wachtwoord)

> 🖥️ **Podman Desktop:** blokjes zoals dit zijn ter controle, niet in plaats van.
> (Menunamen kunnen per versie iets verschillen.)

---

## Uitleg

### Het probleem: pods zijn wegwerp

Alles wat een pod in zijn eigen bestandssysteem schrijft, is weg als de pod verdwijnt. Precies
zoals bij `podman rm` in module 02. Voor een database is dat onacceptabel.

In module 02 loste een **volume** dat op. In Kubernetes heet dat een **PersistentVolumeClaim**.

### Een schijf aanvragen

| Object | Wat | Vergelijk met module 02 |
|---|---|---|
| **PersistentVolumeClaim** (PVC) | "ik wil 1 GB opslag" | `podman volume create` |
| **PersistentVolume** (PV) | de echte schijf die je krijgt | het volume zelf |
| **StorageClass** | hoe die schijf gemaakt wordt | (deed Podman zelf) |

Jij vraagt (PVC), het cluster levert (PV). Waar de schijf vandaan komt, maakt voor jou niet uit:
in kind is het een map op de node, op AKS een Azure-schijf.

### Een StatefulSet in plaats van een Deployment

Voor de database gebruik je geen Deployment, maar een **StatefulSet**. Het verschil:

| | Deployment (api, web) | StatefulSet (database) |
|---|---|---|
| pod-namen | willekeurig: `snip-api-74b9fc85c-kp58v` | vast: `snip-db-0` |
| opslag | gedeeld of geen | **eigen schijf per pod**, die bij die pod blijft |
| nieuwe pod na een crash | een willekeurige nieuwe | **dezelfde naam, dezelfde schijf** |

Een database moet na een herstart zijn eigen data terugvinden. Een StatefulSet zorgt daarvoor.

### Een "headless" Service

De API zoekt `snip-db:5432`. Daarvoor maak je weer een Service, maar dan **headless**
(`clusterIP: None`). Die heeft geen eigen adres, en de naam wijst rechtstreeks naar de pod.
Een StatefulSet heeft zo'n Service nodig. Voor de API werkt het precies hetzelfde.

---

## Lab

### Deel A — De database

**1. Waar komt de opslag vandaan?**

```bash
cd ~/Documents/local/docker-k8s-cursus
kubectl config current-context
kubectl get storageclass
```

`standard (default)`: kind heeft één StorageClass, die schijven maakt als map op de node.

**2. De beginvulling in een ConfigMap**

Net als in module 04 laden we `links.sql` bij de allereerste start:

```bash
mkdir -p k8s/db
kubectl create configmap snip-db-init --from-file=app/db/links.sql \
  --dry-run=client -o yaml > k8s/db/configmap-init.yaml
```

> **Let op:** `configmap-init.yaml` is een *kopie* van `links.sql`. Pas je `links.sql` aan, dan moet je dit commando opnieuw draaien (in module 14 automatiseert Kustomize dat).
> En ook dan ziet een bestaande database het niet: Postgres voert het script alleen uit bij een lege schijf. Een wijziging aan een draaiende database doe je met de hand (`kubectl exec -it snip-db-0 -- psql -U postgres snip`) of met een migratietool.

**3. De StatefulSet**

Maak `k8s/db/statefulset.yaml`:

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: snip-db
  labels:
    app: snip-db
spec:
  serviceName: snip-db          # de Service hieronder geeft de pod een vaste naam
  replicas: 1
  selector:
    matchLabels:
      app: snip-db
  template:
    metadata:
      labels:
        app: snip-db
    spec:
      containers:
        - name: postgres
          image: postgres:18-alpine
          ports:
            - containerPort: 5432
          env:
            - name: POSTGRES_DB
              value: snip
            - name: POSTGRES_PASSWORD           # hetzelfde wachtwoord als de API gebruikt
              valueFrom:
                secretKeyRef:
                  name: snip-db
                  key: password
          volumeMounts:
            - name: data                        # de opslag (zie volumeClaimTemplates)
              mountPath: /var/lib/postgresql
            - name: init                        # links.sql, alleen bij de eerste start
              mountPath: /docker-entrypoint-initdb.d
      volumes:
        - name: init
          configMap:
            name: snip-db-init
  volumeClaimTemplates:                         # vraag per pod een eigen schijf aan
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 1Gi
```

Het lijkt op je Deployments, met één nieuw stuk onderaan: `volumeClaimTemplates`. Dat is een
recept voor een PVC: "geef elke pod een eigen schijf van 1 GB".

Herken je module 02? Hetzelfde image, hetzelfde pad `/var/lib/postgresql`, hetzelfde
wachtwoord via een env var. Alleen komt het wachtwoord nu uit de Secret.

**4. De Service**

Maak `k8s/db/service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: snip-db
spec:
  clusterIP: None               # "headless": de naam wijst rechtstreeks naar de pod
  selector:
    app: snip-db
  ports:
    - port: 5432
```

**5. Toepassen**

```bash
kubectl apply -f k8s/db/
kubectl rollout status statefulset/snip-db
kubectl get pods,pvc,pv
```

Kijk naar:
- de pod **`snip-db-0`**: een vaste naam;
- de PVC **`data-snip-db-0`**, met status `Bound`: gekoppeld aan een schijf;
- de PV erachter, die het cluster zelf maakte.

> 🖥️ **Podman Desktop:** onder **Kubernetes → Persistent Volume Claims** staat `data-snip-db-0`.

**6. Kan de API erbij?**

Postgres heeft een paar seconden nodig om op te starten. Wacht tot de logs `ready to accept
connections` laten zien:

```bash
kubectl logs snip-db-0 -f
```

`Ctrl+C`, en dan:

```bash
kubectl exec deploy/snip-api -- node -e "fetch('http://localhost:3000/health/db').then(r => r.text()).then(console.log)"
```

`{"database":"ok"}`. De API had niet eens herstart hoeven worden: hij probeert het bij elk verzoek
opnieuw.

**7. snip, helemaal in Kubernetes**

Open je tunnel naar de voordeur (zoals in module 10):

```bash
envoy=$(kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=snip -o name)
kubectl port-forward -n envoy-gateway-system $envoy 8080:80
```

Open <http://localhost:8080>: de lijst met links staat er. Maak een nieuwe link, bijvoorbeeld code
`opslag` naar `https://kubernetes.io/docs/concepts/storage/`, en klik erop.

Alles werkt: Gateway → website → API → database.

### Deel B — Overleeft de data het?

**8. De database-pod weggooien**

```bash
kubectl delete pod snip-db-0
kubectl get pods --watch
```

Er komt een nieuwe pod met **dezelfde naam**, `snip-db-0`. `Ctrl+C` als hij `Running` is, en
wacht tot Postgres klaar is (`kubectl logs snip-db-0`). Ververs je browser: je link `opslag` staat
er nog. De nieuwe pod kreeg dezelfde schijf.

**9. De hele StatefulSet weggooien**

```bash
kubectl delete statefulset snip-db
kubectl get pvc
```

De StatefulSet is weg, maar de PVC **niet**. Kubernetes gooit opslag nooit vanzelf weg: dat moet
je bewust doen. Zet hem terug:

```bash
kubectl apply -f k8s/db/
kubectl rollout status statefulset/snip-db
```

Na het opstarten staat je link er weer.

**10. Rondkijken in de database**

```bash
kubectl exec -it snip-db-0 -- psql -U postgres -d snip -c "SELECT code, url FROM links;"
```

Hetzelfde commando als in module 02, met `kubectl` in plaats van `podman`.

---

## Breek het

### 💥 1. Het oude pad

Weet je het nog uit module 02? Probeer het in Kubernetes:

```bash
sed -e 's/^  name: snip-db$/  name: snip-db-oud/' \
    -e 's/app: snip-db$/app: snip-db-oud/' \
    -e 's|mountPath: /var/lib/postgresql$|mountPath: /var/lib/postgresql/data|' \
    k8s/db/statefulset.yaml | kubectl apply -f -
kubectl get pods --watch
```

<details>
<summary>Uitleg</summary>

`Error`, dan `CrashLoopBackOff`.

```bash
kubectl logs snip-db-oud-0 --previous
```

Dezelfde melding als in module 02: vanaf Postgres 18 hoort de opslag op `/var/lib/postgresql`.
Kubernetes verandert niets aan wat er in de container gebeurt; dezelfde fouten komen gewoon terug.

Ruim op, inclusief de schijf die erbij werd gemaakt:

```bash
kubectl delete statefulset snip-db-oud
kubectl delete pvc data-snip-db-oud-0
```
</details>

### 💥 2. De schijf weggooien

<details>
<summary>Wat zou er gebeuren als je de StatefulSet en daarna de PVC <code>data-snip-db-0</code> weggooit?</summary>

Dan is je data weg. Kijk naar `kubectl get storageclass`: `RECLAIMPOLICY Delete`. Gooi je de
PVC weg, dan gooit het cluster ook de schijf erachter weg.

Het is dezelfde les als `podman compose down -v` in module 04: opslag weggooien moet een bewuste
keuze zijn. Doe het hier dus niet; je hebt de data nog nodig.
</details>

---

## Op je werk

- **Databases draaien meestal níet in het cluster.** Bijna altijd gebruik je een managed dienst,
  zoals **Azure Database for PostgreSQL**: back-ups, updates en beschikbaarheid regelt Azure. De
  app krijgt alleen het adres en het wachtwoord (uit Key Vault).
- **StatefulSets** zie je vooral voor Redis, Kafka of Elasticsearch, of via een *operator*: een
  programma dat een database in Kubernetes voor je beheert (bijv. CloudNativePG).
- **Op AKS** heet de standaard-StorageClass `managed-csi`: elke PVC wordt een Azure Disk.
- **Back-ups** maak je altijd apart. Een PVC is één schijf, en geen back-up.

---

## Checkpoint

<details>
<summary>1. Wat is het verschil tussen een PVC en een PV?</summary>

De PVC is de aanvraag ("ik wil 1 GB"). De PV is de echte schijf die het cluster daarvoor maakt.
</details>

<details>
<summary>2. Waarom een StatefulSet en geen Deployment voor de database?</summary>

Een StatefulSet geeft elke pod een vaste naam en een eigen schijf, die bij een herstart bij die pod
blijft. Een Deployment maakt willekeurige, verwisselbare pods.
</details>

<details>
<summary>3. Je gooit de StatefulSet weg. Is je data weg?</summary>

Nee. De PVC blijft staan. Pas als je de PVC zelf weggooit, verdwijnt de schijf.
</details>

<details>
<summary>4. Wat is een headless Service?</summary>

Een Service zonder eigen adres (`clusterIP: None`). De naam wijst rechtstreeks naar de pod(s).
StatefulSets gebruiken die.
</details>

### Eindopdracht

Zorg dat:
1. de StatefulSet `snip-db` draait, met een PVC `data-snip-db-0` die `Bound` is;
2. de headless Service `snip-db` bestaat, en de API erbij kan (`/health/db` is `ok`);
3. de bestanden in `k8s/db/` staan;
4. je een eigen link hebt gemaakt, én de database-pod daarna hebt weggegooid (stap 8). Het script
   ziet aan de tijden of je data ouder is dan de pod;
5. de oefenobjecten weg zijn.

```bash
cd ~/Documents/local/docker-k8s-cursus/modules/12-opslag
./check.sh
```

Groen? Alles draait. Maar Kubernetes weet nog niet wanneer een pod écht klaar is: daarom gaf de
API in stap 6 eerst nog een fout. In **module 13** leer je Kubernetes dat te controleren, en stel
je grenzen in voor geheugen en CPU.

---

## Spiekbrief

| Commando | Wat het doet |
|---|---|
| `kubectl get storageclass` | hoe schijven gemaakt worden |
| `kubectl get pvc,pv` | aanvragen en echte schijven |
| `kubectl get statefulset` | StatefulSets |
| `kubectl rollout status statefulset/NAAM` | wachten tot hij klaar is |
| `kubectl exec -it snip-db-0 -- psql -U postgres -d snip` | in de database |
| `kubectl delete pvc NAAM` | ⚠️ schijf weggooien: **data weg** |

| YAML | |
|---|---|
| `kind: StatefulSet` + `serviceName` | pods met vaste namen |
| `volumeClaimTemplates` | per pod een eigen schijf aanvragen |
| `Service` met `clusterIP: None` | headless: naam wijst rechtstreeks naar de pod |
