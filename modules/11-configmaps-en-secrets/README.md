# Module 11 — ConfigMaps en Secrets: de website erbij

**Doel:** de website (nginx) komt in het cluster, met haar pagina en instellingen in een
**ConfigMap**. Het database-wachtwoord komt in een **Secret**, klaar voor module 12.

**Tijd:** ±1¼ uur

**Nodig:** module 10 afgerond (Service, Gateway en route voor `snip-api`)

> 🖥️ **Podman Desktop:** blokjes zoals dit zijn ter controle, niet in plaats van.
> (Menunamen kunnen per versie iets verschillen.)

---

## Uitleg

### Instellingen horen niet in het image

In deel 1 gaf je instellingen op twee manieren mee:
- **bestanden** via een bind mount: `nginx.conf` en de webpagina;
- **waarden** via `.env`: het database-wachtwoord.

Kubernetes heeft daar twee objecten voor:

| Object | Voor | Vergelijk met |
|---|---|---|
| **ConfigMap** | gewone instellingen en bestanden | je bind mounts, en gewone regels in `.env` |
| **Secret** | geheime waarden | het wachtwoord in `.env` |

Je kunt ze op twee manieren aan een pod geven:
- **als bestand** in een map (wij doen dat met `nginx.conf` en de pagina);
- **als environment variable** (wij doen dat met het wachtwoord).

### Wat er straks staat

```
 Gateway snip
   ├─ /api ──▶ Service snip-api ──▶ pods api   (DATABASE_URL met wachtwoord uit Secret snip-db)
   └─ /    ──▶ Service snip-web ──▶ pods nginx (pagina en nginx.conf uit ConfigMaps)
                                      └─ korte links (/gh) ──▶ snip-api
```

### Een Secret is niet versleuteld

Een Secret wordt alleen in **base64** opgeslagen: dat is omzetten, geen versleutelen. Iedereen die
Secrets mag lezen, kan het wachtwoord zien. Daarom:
- zet je een Secret **nooit** als bestand in Git;
- maak je hem nu met een commando, rechtstreeks in het cluster;
- komt hij op je werk uit een kluis (Azure Key Vault, module 21).

---

## Lab

### Deel A — De website

**1. De pagina en nginx.conf in een ConfigMap**

De bestanden staan al klaar: de pagina in `app/web/site/index.html`, en een `nginx.conf` voor
Kubernetes in `app/web/nginx-k8s.conf`. Laat `kubectl` er YAML van maken:

```bash
cd ~/Documents/local/docker-k8s-cursus
kubectl config current-context
mkdir -p k8s/web

kubectl create configmap snip-web-site --from-file=app/web/site/index.html \
  --dry-run=client -o yaml > k8s/web/configmap-site.yaml
kubectl create configmap snip-web-nginx --from-file=default.conf=app/web/nginx-k8s.conf \
  --dry-run=client -o yaml > k8s/web/configmap-nginx.yaml
```

Kijk in een van de bestanden: onder `data:` staat de hele inhoud van het bestand.

`default.conf=` geeft het bestand een andere naam in de ConfigMap. nginx leest namelijk
`default.conf`.

**2. De website: Deployment en Service**

Maak `k8s/web/deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: snip-web
  labels:
    app: snip-web
spec:
  replicas: 2
  selector:
    matchLabels:
      app: snip-web
  template:
    metadata:
      labels:
        app: snip-web
    spec:
      containers:
        - name: nginx
          image: nginx:1.29-alpine
          ports:
            - containerPort: 80
          volumeMounts:
            - name: site                       # de webpagina...
              mountPath: /usr/share/nginx/html #   ...komt hier te staan
            - name: nginx-config               # de nginx-instellingen...
              mountPath: /etc/nginx/conf.d     #   ...komen hier te staan
      volumes:
        - name: site
          configMap:
            name: snip-web-site                # uit deze ConfigMap
        - name: nginx-config
          configMap:
            name: snip-web-nginx               # uit deze ConfigMap
```

En `k8s/web/service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: snip-web
spec:
  selector:
    app: snip-web
  ports:
    - port: 80
      targetPort: 80
```

Twee nieuwe stukken:
- `volumes`: "maak een volume van deze ConfigMap";
- `volumeMounts`: "zet dat volume op deze plek in de container".

Dat is dezelfde bind mount als in module 04, alleen komt de inhoud nu uit het cluster in plaats
van van je Mac.

```bash
kubectl apply -f k8s/web/
kubectl rollout status deploy/snip-web
```

**3. De routes: `/api` naar de API, de rest naar de website**

Pas in `k8s/api/route.yaml` het pad aan van `/` naar `/api`:

```yaml
            value: /api
```

En maak `k8s/web/route.yaml`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: snip-web
spec:
  parentRefs:
    - name: snip
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: snip-web
          port: 80
```

```bash
kubectl apply -f k8s/api/route.yaml -f k8s/web/route.yaml
```

De Gateway kiest altijd de **langste** passende regel. `/api/info` past op `/api` én op `/`, en
gaat dus naar de API.

**4. Kijken**

```bash
envoy=$(kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=snip -o name)
kubectl port-forward -n envoy-gateway-system $envoy 8080:80
```

Open <http://localhost:8080>. Daar is snip, nu in Kubernetes. Er staat wel "De api is niet
bereikbaar": de pagina vraagt de lijst met links op, en daarvoor is de database nodig. Die komt in
module 12.

> 🖥️ **Podman Desktop:** onder **Kubernetes → ConfigMaps & Secrets** zie je je twee ConfigMaps.

**5. De pagina aanpassen, zonder herstart**

Laat de tunnel lopen. In een tweede terminal:

```bash
cd ~/Documents/local/docker-k8s-cursus
sed -i '' 's|<p class="sub">|<p class="sub">Uit een ConfigMap! |' app/web/site/index.html
kubectl create configmap snip-web-site --from-file=app/web/site/index.html \
  --dry-run=client -o yaml > k8s/web/configmap-site.yaml
kubectl apply -f k8s/web/configmap-site.yaml
```

Ververs je browser een paar keer. Binnen ongeveer een minuut staat de nieuwe tekst er, zonder dat
er een pod is herstart. Kubernetes werkt het bestand in de pod zelf bij, en nginx leest de pagina
bij elk bezoek.

Zet de pagina daarna terug (die wordt ook gebruikt op je droplet):

```bash
git restore app/web/site/index.html
kubectl create configmap snip-web-site --from-file=app/web/site/index.html \
  --dry-run=client -o yaml > k8s/web/configmap-site.yaml
kubectl apply -f k8s/web/configmap-site.yaml
```

### Deel B — Het wachtwoord in een Secret

**6. De Secret maken**

```bash
kubectl create secret generic snip-db --from-literal=password="$(openssl rand -hex 24)"
```

Een willekeurig wachtwoord, rechtstreeks in het cluster. Er komt **geen** bestand van in `k8s/`.

**7. De API het wachtwoord geven**

Voeg in `k8s/api/deployment.yaml` onder `ports:` van de container dit toe (op dezelfde
hoogte als `ports:`):

```yaml
          env:
            - name: DB_PASSWORD                # uit de Secret...
              valueFrom:
                secretKeyRef:
                  name: snip-db
                  key: password
            - name: DATABASE_URL               # ...en hier ingevuld met $(DB_PASSWORD)
              value: postgres://postgres:$(DB_PASSWORD)@snip-db:5432/snip
```

`$(DB_PASSWORD)` vult Kubernetes zelf in met de waarde van de variabele erboven. Zo staat het
wachtwoord niet in het bestand, maar de rest van het adres wel.

```bash
kubectl apply -f k8s/api/deployment.yaml
kubectl rollout status deploy/snip-api
```

Er volgt een rolling update, want het pod-recept is veranderd.

**8. Waar is het wachtwoord gebleven?**

In de pod:

```bash
kubectl exec deploy/snip-api -- printenv DATABASE_URL
```

In het cluster:

```bash
kubectl get secret snip-db -o jsonpath='{.data.password}'
kubectl get secret snip-db -o jsonpath='{.data.password}' | base64 -d
```

Het eerste is base64, het tweede is het wachtwoord zelf. Eén commando, en het is leesbaar. Een
Secret beschermt dus alleen via de **rechten** op het cluster.

---

## Breek het

### 💥 1. Een Secret die niet bestaat

```bash
sed -e 's/name: snip-db$/name: snip-dbb/' \
    -e 's/name: snip-api$/name: snip-api-kapot/' \
    -e 's/app: snip-api$/app: snip-api-kapot/' \
    k8s/api/deployment.yaml | kubectl apply -f -
kubectl get pods -l app=snip-api-kapot
```

<details>
<summary>Uitleg</summary>

`CreateContainerConfigError`. De pod verwijst naar een Secret `snip-dbb` die er niet is. Kijk
in de Events:

```bash
kubectl describe pods -l app=snip-api-kapot | grep -A1 Warning
```

`secret "snip-dbb" not found`. Hetzelfde krijg je bij een ConfigMap die ontbreekt, of een sleutel
die niet in de Secret staat.

```bash
kubectl delete deploy snip-api-kapot
```
</details>

### 💥 2. nginx.conf aangepast, niets gebeurt

Laat de tunnel uit stap 4 lopen. Verander in de nginx-instellingen de doorverwijzing van korte
links naar een 404:

```bash
sed 's|try_files $uri $uri/ @api;|try_files $uri $uri/ =404;|' app/web/nginx-k8s.conf \
  | kubectl create configmap snip-web-nginx --from-file=default.conf=/dev/stdin \
    --dry-run=client -o yaml | kubectl apply -f -
```

Wacht een minuut, en kijk dan naar `curl -s -o /dev/null -w '%{http_code}\n' localhost:8080/gh`.

<details>
<summary>Uitleg</summary>

Nog steeds `500` (de API zonder database), geen `404`. Maar het bestand in de pod is wél
bijgewerkt:

```bash
kubectl exec deploy/snip-web -- cat /etc/nginx/conf.d/default.conf
```

nginx leest zijn instellingen alleen **bij het opstarten**. De webpagina leest hij bij elk
bezoek, en die werd daarom wel meteen bijgewerkt. Herstart de pods:

```bash
kubectl rollout restart deploy/snip-web
```

Nu `404`. Zet het terug:

```bash
kubectl apply -f k8s/web/configmap-nginx.yaml
kubectl rollout restart deploy/snip-web
```

Hetzelfde geldt voor **environment variables**: die worden alleen bij het starten van een pod
gelezen. Verander je een Secret die als env var wordt gebruikt, dan moeten de pods opnieuw
starten.
</details>

---

## Op je werk

- **ConfigMaps** komen meestal uit Helm-values (module 14). Daar zit vaak een truc in die de
  pods automatisch herstart als de configuratie verandert.
- **Secrets** komen uit **Azure Key Vault**, via de External Secrets Operator of de Secrets Store
  CSI Driver (module 21). Er staat nooit een wachtwoord in Git.
- **Rechten:** wie Secrets in een namespace mag lezen, kan alle wachtwoorden zien. Daarom mag je
  dat op je werk vaak niet, ook al mag je pods en logs wel bekijken.

---

## Checkpoint

<details>
<summary>1. Wanneer gebruik je een ConfigMap en wanneer een Secret?</summary>

ConfigMap voor gewone instellingen en bestanden. Secret voor geheime waarden, zoals wachtwoorden.
</details>

<details>
<summary>2. Is een Secret versleuteld?</summary>

Nee, alleen in base64. Iedereen met leesrechten op Secrets kan de waarde zien.
</details>

<details>
<summary>3. Je past een ConfigMap aan. Wanneer zie je het in de pod?</summary>

Als bestand: na ongeveer een minuut staat het nieuwe bestand in de pod. Of de app het ook
gebruikt, hangt af van wanneer de app het leest. Als env var: pas na een herstart van de pod.
</details>

<details>
<summary>4. Een pod staat op <code>CreateContainerConfigError</code>. Wat is er meestal aan de hand?</summary>

Een ConfigMap of Secret (of een sleutel daarin) waar de pod naar verwijst, bestaat niet.
</details>

### Eindopdracht

Zorg dat:
1. de website (`snip-web`) met 2 pods draait, met pagina en instellingen uit de ConfigMaps
   `snip-web-site` en `snip-web-nginx`;
2. `/` naar de website gaat en `/api` naar de API;
3. de Secret `snip-db` bestaat, en de API zijn `DATABASE_URL` daaruit opbouwt;
4. er **geen** Secret als bestand in `k8s/` staat, en de oefenobjecten weg zijn.

```bash
cd ~/Documents/local/docker-k8s-cursus/modules/11-configmaps-en-secrets
./check.sh
```

Groen? In **module 12** komt de database in het cluster, met opslag die een herstart overleeft.
Dan werkt snip in Kubernetes helemaal.

---

## Spiekbrief

| Commando | Wat het doet |
|---|---|
| `kubectl create configmap NAAM --from-file=BESTAND --dry-run=client -o yaml > k8s/X.yaml` | ConfigMap-YAML maken van een bestand |
| `... --from-file=NIEUWENAAM=BESTAND` | idem, met een andere naam in de ConfigMap |
| `kubectl create secret generic NAAM --from-literal=SLEUTEL=WAARDE` | Secret maken (niet in Git!) |
| `kubectl get configmap,secret` | overzicht |
| `kubectl get secret NAAM -o jsonpath='{.data.SLEUTEL}' \| base64 -d` | een Secret uitlezen |
| `kubectl exec deploy/NAAM -- printenv VAR` | env var in een pod bekijken |
| `kubectl rollout restart deploy/NAAM` | pods opnieuw starten (na een config-wijziging) |

| YAML | |
|---|---|
| `volumes: - configMap: name: X` | volume van een ConfigMap |
| `volumeMounts: - mountPath: /pad` | waar het in de container komt |
| `env: - valueFrom: secretKeyRef:` | env var uit een Secret |
| `value: ...$(ANDERE_VAR)...` | een eerdere env var invullen |
