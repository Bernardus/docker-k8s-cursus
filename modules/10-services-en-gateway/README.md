# Module 10 — Services en de Gateway: je pods bereikbaar maken

**Doel:** je drie API-pods krijgen één vast adres in het cluster (een **Service**), en via een
**Gateway** kun je ze van buitenaf bereiken. Onderweg zie je hoe Kubernetes verkeer over je
pods verdeelt.

**Tijd:** ±1½ uur

**Nodig:** module 09 afgerond (Deployment `snip-api` met 3 pods, context `kind-snip`)

`CKAD` Services, DNS in het cluster en Ingress staan op het examen. De Gateway API is de opvolger
van Ingress; die leer je hier hands-on, en Ingress in een korte vergelijking.

> 🖥️ **Podman Desktop:** waar het helpt staat zo'n blokje. Ter controle, niet in plaats van.
> (Menunamen kunnen per versie iets verschillen.)

---

## Uitleg

### Het probleem: adressen die steeds veranderen

```bash
kubectl get pods -o wide
```

Elke pod heeft een eigen IP-adres. Maar bij elke update, crash of verhuizing komt er een nieuwe
pod, met een **nieuw** adres. En het zijn er drie: naar welke moet je verkeer sturen?

Het is hetzelfde probleem als in module 02. Daar loste een netwerk met DNS het op: containers
vonden elkaar op naam. In Kubernetes doet een **Service** dat.

### Een Service: één vast adres voor een groep pods

```
                         Service "snip-api"
   iemand vraagt   ──▶   vast adres + vaste naam   ──┬──▶  pod (10.244.0.7)
   snip-api:80           verdeelt het verkeer        ├──▶  pod (10.244.0.5)
                                                     └──▶  pod (10.244.0.6)
```

Een Service:
- heeft een **naam** die je overal in het cluster kunt gebruiken: `snip-api`;
- heeft een **vast IP-adres** dat nooit verandert, zolang de Service bestaat;
- **verdeelt** het verkeer over alle pods die erbij horen (*load balancing*);
- houdt zelf bij welke pods dat zijn, ook als ze komen en gaan.

Welke pods erbij horen? Net als bij de Deployment: via **etiketten**. De Service zegt "alle pods
met `app: snip-api`". Zo werken Deployment en Service samen, zonder dat ze van elkaar weten:

```
 Deployment snip-api ──maakt──▶ pods met etiket app=snip-api ◀──zoekt── Service snip-api
```

### Drie soorten Services

| Soort | Bereikbaar vanaf | Gebruik je voor |
|---|---|---|
| **ClusterIP** (standaard) | alleen binnen het cluster | bijna alles: API's, databases |
| **NodePort** | een vaste poort op elke node | testen; zie je weinig |
| **LoadBalancer** | internet, via een load balancer van de cloud | op AKS: één publiek IP-adres |

Wij maken een **ClusterIP**: de API hoeft niet rechtstreeks van buiten bereikbaar te zijn.
Herken je module 04? Daar had de API ook geen `ports`, en ging alles via nginx.

### De voordeur van het cluster: de Gateway

Van buitenaf wil je één ingang, die op basis van het adres beslist waar verkeer heen gaat:
`/api/...` naar de API, `/` naar de website. In module 06 en 07 deed nginx (en later Caddy) dat.
In Kubernetes heet die ingang een **Gateway**.

```
 internet / jouw Mac
        │
        ▼
   Gateway "snip"         ← de voordeur (luistert op poort 80)
        │
   HTTPRoute "snip-api"   ← de regel: "alles onder / gaat naar Service snip-api"
        │
        ▼
   Service "snip-api"  ──▶  pods
```

Het zijn drie losse stukken, en dat is bewust:

| Stuk | Wat het is | Op je werk van |
|---|---|---|
| **GatewayClass** | welke software de voordeur is (bij ons: Envoy) | platformteam |
| **Gateway** | de voordeur zelf: poorten, later HTTPS | platformteam |
| **HTTPRoute** | regels: welk adres naar welke Service | **jij**, het app-team |

Het platformteam zet één Gateway neer, en elk team hangt er zijn eigen routes aan. Zo hoeft niemand
aan de voordeur van een ander te zitten.

De Gateway zelf is maar een beschrijving. Er moet ook software draaien die het werk doet: een
**gateway-controller**. Wij gebruiken **Envoy Gateway**. (Dat is hetzelfde idee als Caddy en
nginx, maar dan aangestuurd door Kubernetes-objecten in plaats van een configuratiebestand.)

### En Ingress?

**Ingress** is de oudere manier om hetzelfde te doen: één object dat routes en de voordeur
combineert. Je komt het nog overal tegen, en het staat op het CKAD-examen. Het populairste
programma erachter, *ingress-nginx*, is in maart 2026 gestopt, en nieuwe opzetten kiezen de
Gateway API. Je ziet Ingress in breek-het 3.

---

## Lab

### Deel A — Een Service voor de API

**1. Het manifest**

Maak `k8s/api/service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: snip-api
spec:
  selector:
    app: snip-api        # stuur verkeer naar alle pods met dit etiket
  ports:
    - port: 80           # de poort van de Service zelf
      targetPort: 3000   # de poort waarop de API in de pod luistert
```

Twee poorten: anderen praten met de Service op **80**, en de Service stuurt door naar **3000** in
de pod. Dan hoeft niemand te weten op welke poort de API toevallig luistert.

**2. Toepassen en bekijken**

```bash
cd ~/Documents/local/docker-k8s-cursus
kubectl config current-context
kubectl apply -f k8s/api/service.yaml
kubectl get svc snip-api
```

Type `ClusterIP`, met een vast IP-adres. Welke pods horen erbij?

```bash
kubectl get endpointslices -l kubernetes.io/service-name=snip-api
kubectl get pods -o wide
```

Onder `ENDPOINTS` staan drie IP-adressen: precies die van je drie pods. Die lijst houdt
Kubernetes automatisch bij.

> 🖥️ **Podman Desktop:** onder **Kubernetes → Services** staat `snip-api`, met zijn type en IP-adres.

**3. Gebruiken vanuit het cluster**

Een Service is alleen **binnen** het cluster bereikbaar. Start daarom een tijdelijke pod met
`curl`, en vraag een paar keer wie er antwoordt:

```bash
kubectl run tmp --rm -it --restart=Never --image=curlimages/curl -- sh
```

In die pod:

```sh
for i in 1 2 3 4 5 6 7 8 9; do curl -s snip-api/api/info; echo; done
exit
```

Kijk naar `"container"`: het antwoord komt steeds van een **andere** pod. De Service verdeelt het
verkeer. En je gebruikte gewoon de naam `snip-api`, zonder poort (dus 80) en zonder IP-adres.

(`--rm` ruimt de tijdelijke pod weer op zodra je `exit` typt.)

**4. De volledige naam**

`snip-api` werkt binnen dezelfde namespace. De volledige naam, die vanuit **elke** namespace werkt,
is:

```
snip-api.default.svc.cluster.local
   │       │      └─ vaste staart: "een Service in dit cluster"
   │       └─ de namespace
   └─ de naam van de Service
```

Dat heb je nodig zodra apps in verschillende namespaces staan (module 15).

**5. Zelf even bij een Service**

```bash
kubectl port-forward svc/snip-api 8086:80
```

In een tweede terminal:

```bash
curl localhost:8086/api/info
```

Let op: `port-forward` kiest **één** pod en blijft daarbij. Het is een testtunnel, geen
load balancer. Stop met `Ctrl+C`.

### Deel B — Een voordeur: Envoy Gateway

**6. Envoy Gateway installeren**

```bash
kubectl apply --server-side -f https://github.com/envoyproxy/gateway/releases/download/v1.9.2/install.yaml
kubectl wait --timeout=5m -n envoy-gateway-system deployment/envoy-gateway --for=condition=Available
```

Dit installeert twee dingen:
- de **Gateway API** zelf: nieuwe soorten objecten (`Gateway`, `HTTPRoute`, ...) die Kubernetes
  standaard niet kent;
- de **controller**: een pod in de namespace `envoy-gateway-system`, die op die objecten let en
  er een echte voordeur van maakt.

Vaste versie (`v1.9.2`), net als bij je images: geen verrassingen.

```bash
kubectl get pods -n envoy-gateway-system
```

**7. De Gateway**

Maak `k8s/gateway.yaml`:

```yaml
# Instellingen voor Envoy: maak een gewone interne Service (ClusterIP).
# In de cloud zou je hier een LoadBalancer krijgen; in kind bestaat die niet.
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: EnvoyProxy
metadata:
  name: kind
  namespace: envoy-gateway-system
spec:
  provider:
    type: Kubernetes
    kubernetes:
      envoyService:
        type: ClusterIP
---
# Welke software de voordeur is: Envoy Gateway, met de instellingen hierboven.
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: envoy
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
  parametersRef:
    group: gateway.envoyproxy.io
    kind: EnvoyProxy
    name: kind
    namespace: envoy-gateway-system
---
# De voordeur zelf: luistert op poort 80 (http).
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: snip
spec:
  gatewayClassName: envoy
  listeners:
    - name: http
      protocol: HTTP
      port: 80
```

Drie objecten in één bestand, gescheiden door `---`. Het eerste is specifiek voor kind: zonder
dat vraagt Envoy om een LoadBalancer, en die kan kind niet leveren.

```bash
kubectl apply -f k8s/gateway.yaml
kubectl wait --for=condition=Programmed gateway/snip --timeout=3m
kubectl get gateway snip
```

`PROGRAMMED: True`: de voordeur staat. Envoy Gateway heeft er een pod (de echte Envoy) en een
Service voor gemaakt:

```bash
kubectl get pods,svc -n envoy-gateway-system
```

**8. De route**

Maak `k8s/api/route.yaml`:

```yaml
# Welk verkeer via de voordeur naar welke Service gaat.
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: snip-api
spec:
  parentRefs:
    - name: snip          # hangt aan de Gateway "snip"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: snip-api  # naar de Service "snip-api"
          port: 80
```

Voorlopig gaat **alles** naar de API. In module 11 komt de website erbij, en dan splitsen we:
`/api` naar de API, de rest naar de website.

```bash
kubectl apply -f k8s/api/route.yaml
kubectl get httproute snip-api
```

**9. Door de voordeur**

De Envoy-Service heeft een gegenereerde naam. Zoek hem op en open een tunnel:

```bash
envoy=$(kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=snip -o name)
echo $envoy
kubectl port-forward -n envoy-gateway-system $envoy 8080:80
```

In een tweede terminal:

```bash
for i in 1 2 3 4 5 6; do curl -s localhost:8080/api/info; echo; done
```

Je verzoek gaat nu: Mac → tunnel → **Envoy** (de Gateway) → **Service** → steeds een andere
**pod**. Dat is de hele keten.

> **Waarom nog een tunnel?** In kind kan niets van buiten zonder hulp in het cluster. Op AKS krijgt
> de Gateway een **publiek IP-adres** van Azure, en in module 19 (k3s op je droplet) een echte
> poort 80. De Gateway en de route blijven precies hetzelfde.

`/gh` geeft nog een `500`. Dat klopt: er is nog geen database in het cluster (module 12).

---

## Breek het

### 💥 1. Een Service die naar niemand wijst

```bash
sed -e 's/name: snip-api$/name: snip-api-kapot/' -e 's/app: snip-api /app: snip-apii /' \
  k8s/api/service.yaml | kubectl apply -f -
kubectl run tmp --rm -it --restart=Never --image=curlimages/curl -- curl -sS -m 3 snip-api-kapot/health
```

<details>
<summary>Hint</summary>

```bash
kubectl get endpointslices -l kubernetes.io/service-name=snip-api-kapot
kubectl describe svc snip-api-kapot
```
</details>

<details>
<summary>Uitleg</summary>

Time-out, of geen verbinding. De Service bestaat wel, en heeft een IP-adres, maar onder
`Endpoints` staat **niets**. Het etiket in de selector (`snip-apii`) past op geen enkele pod.

Kubernetes geeft hier **geen foutmelding**. Een Service met nul pods is toegestaan (misschien
komen ze nog). Daarom is dit een van de verraderlijkste fouten. Je eerste controle bij "Service
werkt niet" is altijd: **heeft hij endpoints?**

```bash
kubectl delete svc snip-api-kapot
```
</details>

### 💥 2. Een route naar een Service die niet bestaat

```bash
sed -e 's/name: snip-api$/name: snip-api-kapot/' -e 's/- name: snip-api  #/- name: snip-apj  #/' \
  k8s/api/route.yaml | kubectl apply -f -
kubectl describe httproute snip-api-kapot
```

<details>
<summary>Uitleg</summary>

Onder `Conditions` staat `ResolvedRefs: False`, met reden `BackendNotFound`. De route hangt
wel aan de Gateway (`Accepted: True`), maar verwijst naar een Service `snip-apj` die er niet is.

Anders dan bij een Service vertelt de Gateway API je dit wél, in de status. Kijk bij problemen
met routes dus altijd naar `kubectl describe httproute`.

```bash
kubectl delete httproute snip-api-kapot
```
</details>

### 💥 3. Een Ingress zonder controller

Zo ziet hetzelfde eruit als **Ingress**, de oudere manier:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: snip-api
spec:
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: snip-api
                port:
                  number: 80
EOF
kubectl get ingress snip-api
```

<details>
<summary>Uitleg</summary>

Kubernetes accepteert het, maar `ADDRESS` blijft leeg, en er gebeurt niets. Er draait geen
**ingress-controller** die naar Ingress-objecten kijkt. Envoy Gateway doet alleen de Gateway API.

Een Ingress of Gateway is alleen een **beschrijving**. Zonder controller die hem uitvoert, is
het een briefje dat niemand leest. Op een cluster dat je niet kent, kijk je daarom eerst wat er
draait: `kubectl get gatewayclass` en `kubectl get ingressclass`.

Vergelijk de Ingress met je Gateway + HTTPRoute: dezelfde informatie (pad `/` → Service
`snip-api` poort 80), maar alles in één object. Daardoor kun je de voordeur en de routes niet
over teams verdelen. Dat is een van de redenen voor de Gateway API.

```bash
kubectl delete ingress snip-api
```
</details>

---

## Op je werk

- **Services zijn ClusterIP**, bijna altijd. Wat van buiten bereikbaar moet zijn, gaat via de
  centrale voordeur van het cluster.
- **De Gateway is van het platformteam.** Jij levert alleen een **HTTPRoute** aan, met je eigen
  hostnaam (bijv. `snip.mijnbedrijf.nl`) en paden. HTTPS en certificaten regelt de Gateway
  (module 19 en 21).
- **Op AKS** zie je ook de *application routing*-gateway van Microsoft, of Application Gateway for
  Containers. De HTTPRoute die je schrijft is overal dezelfde: dat is het voordeel van een
  standaard.
- **Debuggen in de goede volgorde**, van binnen naar buiten, net als in module 06:
  pod draait? → Service heeft endpoints? → route `ResolvedRefs: True`? → Gateway `Programmed`?

---

## Checkpoint

<details>
<summary>1. Waarom praat je met een Service, en niet rechtstreeks met een pod?</summary>

Pods komen en gaan, met steeds nieuwe IP-adressen, en er zijn er meerdere. Een Service heeft een
vaste naam en een vast adres, en verdeelt het verkeer over de pods die er op dat moment zijn.
</details>

<details>
<summary>2. Hoe weet een Service welke pods erbij horen?</summary>

Via de selector: alle pods met die etiketten. De lijst met hun adressen staat in de
EndpointSlices.
</details>

<details>
<summary>3. Wat is het verschil tussen <code>port</code> en <code>targetPort</code>?</summary>

`port` is de poort van de Service (waar anderen op praten). `targetPort` is de poort in de pod
(waar de app luistert).
</details>

<details>
<summary>4. Je Service werkt niet, en er is geen foutmelding. Wat controleer je eerst?</summary>

Of hij endpoints heeft (`kubectl get endpointslices` of `kubectl describe svc`). Geen endpoints
betekent meestal: het etiket in de selector past op geen enkele pod.
</details>

<details>
<summary>5. Wat doen GatewayClass, Gateway en HTTPRoute?</summary>

GatewayClass: welke software de voordeur is. Gateway: de voordeur zelf, met poorten. HTTPRoute:
welke verzoeken naar welke Service gaan.
</details>

<details>
<summary>6. Je maakt een Ingress, maar er gebeurt niets. Waarom zou dat kunnen?</summary>

Er draait geen ingress-controller die Ingress-objecten uitvoert. Het object is alleen een
beschrijving.
</details>

### Eindopdracht

Zorg dat:
1. de Service **`snip-api`** (ClusterIP, poort 80 → 3000) bestaat, met 3 endpoints;
2. **Envoy Gateway v1.9.2** draait;
3. de Gateway **`snip`** op `Programmed: True` staat;
4. de HTTPRoute **`snip-api`** aan de Gateway hangt en naar de Service wijst;
5. de bestanden `api/service.yaml`, `api/route.yaml` en `gateway.yaml` in `k8s/` staan;
6. de oefenobjecten uit breek-het weg zijn.

```bash
cd ~/Documents/local/docker-k8s-cursus/modules/10-services-en-gateway
./check.sh
```

Het script stuurt zelf een paar verzoeken door de Gateway, en controleert of er meerdere pods
antwoorden.

Groen? In **module 11** komt de website erbij, met haar `nginx.conf` en pagina in een
**ConfigMap**, en het database-wachtwoord in een **Secret**.

---

## Spiekbrief

| Commando | Wat het doet |
|---|---|
| `kubectl get svc` | Services |
| `kubectl describe svc NAAM` | details, o.a. selector en endpoints |
| `kubectl get endpointslices -l kubernetes.io/service-name=NAAM` | welke pod-adressen achter een Service zitten |
| `kubectl run tmp --rm -it --restart=Never --image=curlimages/curl -- sh` | tijdelijke pod om vanuit het cluster te testen |
| `kubectl port-forward svc/NAAM 8086:80` | tunnel naar een Service (kiest één pod) |
| `kubectl get gatewayclass,gateway,httproute` | de Gateway-objecten |
| `kubectl describe httproute NAAM` | status van een route (`Accepted`, `ResolvedRefs`) |
| `kubectl get ingress` / `ingressclass` | Ingress-objecten / welke controllers er zijn |

| YAML | |
|---|---|
| `Service.spec.selector` | welke pods (etiketten) |
| `Service.spec.ports[].port` / `targetPort` | poort van de Service / poort in de pod |
| `Service.spec.type` | `ClusterIP` (standaard), `NodePort`, `LoadBalancer` |
| `Gateway.spec.listeners` | waarop de voordeur luistert |
| `HTTPRoute.spec.parentRefs` | aan welke Gateway de route hangt |
| `HTTPRoute.spec.rules[].matches` / `backendRefs` | welk verkeer / naar welke Service |

| DNS in het cluster | |
|---|---|
| `NAAM` | Service in dezelfde namespace |
| `NAAM.NAMESPACE.svc.cluster.local` | Service in elke namespace |
