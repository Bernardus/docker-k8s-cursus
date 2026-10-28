# Module 10 — Je pods bereikbaar maken

**Doel:** je drie API-pods krijgen één vaste naam in het cluster (een **Service**), en via een
voordeur (een **Gateway**) bereik je ze vanaf je Mac.

**Tijd:** ±1 uur

**Nodig:** module 09 afgerond (Deployment `snip-api` met 3 pods, context `kind-snip`)

> 🖥️ **Podman Desktop:** alles doe je in de terminal. Waar het handig is, staat een blokje zoals
> dit: daar kun je hetzelfde ook bekijken in Podman Desktop. Ter controle, niet in plaats van.
> (Menunamen kunnen per versie iets verschillen.)

---

## Uitleg

### Het probleem: pods wisselen van adres

Elke pod krijgt een eigen IP-adres. Maar bij elke update of crash komt er een nieuwe pod, met
een **nieuw** adres. En het zijn er drie. Met welk adres moet je praten?

### De oplossing: een Service

Een **Service** krijgt een **eigen** vaste naam en een vast adres, en stuurt verkeer door naar de
pods die er op dat moment zijn. De pods blijven gewoon wisselen; jij merkt er niets van.

```
   iemand vraagt "snip-api"  ──▶  Service snip-api  ──┬──▶  pod
                                  (vast adres)        ├──▶  pod     (wisselen, maakt niet uit)
                                                      └──▶  pod
```

Welke pods erbij horen? Net als bij de Deployment: via het **etiket** `app: snip-api`.

Dit ken je al uit module 02: daar vonden containers elkaar op naam via een netwerk. Een Service is
hetzelfde idee, maar dan voor een hele groep pods tegelijk, en het verkeer wordt over die groep
verdeeld.

Onze Service is van het type **ClusterIP**: alleen bereikbaar **binnen** het cluster. Dat is
genoeg, want van buiten komt alles via de voordeur.

### De voordeur: een Gateway

Om er vanaf buiten bij te kunnen, zet je een **Gateway** neer: één ingang voor het hele cluster.
Wat er via die ingang naar welke Service gaat, schrijf je in een **HTTPRoute**.

```
 jouw Mac  ──▶  Gateway (de voordeur)  ──▶  HTTPRoute (de regel)  ──▶  Service  ──▶  pods
```

Dat is hetzelfde werk dat nginx en Caddy deden in module 06 en 07. Het verschil is dat je het nu
met Kubernetes-objecten beschrijft, en dat **Envoy Gateway** (een programma in je cluster) het
uitvoert.

Op je werk zet het platformteam de Gateway neer, en lever jij alleen een HTTPRoute aan.

---

## Lab

### Deel A — Een Service

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

**2. Toepassen en bekijken**

```bash
cd ~/Documents/local/docker-k8s-cursus
kubectl config current-context
kubectl apply -f k8s/api/service.yaml
kubectl describe svc snip-api
```

Kijk naar twee regels:
- **IP**: het vaste adres van de Service;
- **Endpoints**: drie adressen, die van je pods. Die lijst houdt Kubernetes zelf bij.

> 🖥️ **Podman Desktop:** onder **Kubernetes → Services** staat `snip-api`.

**3. Verkeer verdelen, zelf gezien**

Een Service werkt alleen **binnen** het cluster. Start daarom een tijdelijke pod om vanuit het
cluster te testen:

```bash
kubectl run tmp --rm -it --restart=Never --image=curlimages/curl -- sh
```

In die pod:

```sh
for i in 1 2 3 4 5 6 7 8 9; do curl -s snip-api/api/info; echo; done
exit
```

Kijk naar `"container"`: steeds een andere pod. Je gebruikte alleen de naam `snip-api`, geen
IP-adres en geen poort.

### Deel B — Een voordeur

**4. Envoy Gateway installeren**

```bash
kubectl apply --server-side -f https://github.com/envoyproxy/gateway/releases/download/v1.9.2/install.yaml
kubectl wait --timeout=5m -n envoy-gateway-system deployment/envoy-gateway --for=condition=Available
```

Dit installeert het programma dat straks de voordeur bedient, in een eigen namespace
`envoy-gateway-system`.

**5. De Gateway**

Maak `k8s/gateway.yaml`:

```yaml
# Specifiek voor kind: maak een gewone interne Service voor de voordeur.
# (In de cloud krijg je hier automatisch een publiek IP-adres; in kind niet.)
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
# Welk programma de voordeur is: Envoy Gateway.
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
# De voordeur zelf: luistert op poort 80.
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

Drie stukken in één bestand, gescheiden door `---`. Alleen het laatste (`Gateway`) is echt "de
voordeur"; de andere twee zijn instellingen.

```bash
kubectl apply -f k8s/gateway.yaml
kubectl wait --for=condition=Programmed gateway/snip --timeout=3m
```

**6. De regel: alles naar de API**

Maak `k8s/api/route.yaml`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: snip-api
spec:
  parentRefs:
    - name: snip          # aan welke voordeur
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /      # welk verkeer: alles
      backendRefs:
        - name: snip-api  # naar welke Service
          port: 80
```

```bash
kubectl apply -f k8s/api/route.yaml
```

In module 11 komt de website erbij; dan gaat alleen `/api` nog naar de API.

**7. Door de voordeur**

In kind kan niets van buiten zonder tunnel in het cluster. Open er een naar de voordeur:

```bash
envoy=$(kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=snip -o name)
kubectl port-forward -n envoy-gateway-system $envoy 8080:80
```

In een tweede terminal:

```bash
for i in 1 2 3 4 5 6; do curl -s localhost:8080/api/info; echo; done
```

Mac → voordeur → Service → steeds een andere pod. (`/gh` geeft nog een fout: de database komt in
module 12.)

> 🖥️ **Podman Desktop:** onder **Kubernetes → Pods** staat nu ook de Envoy-pod (in de namespace
> `envoy-gateway-system`): dat is je voordeur.

---

## Breek het

### 💥 1. Een Service die naar niemand wijst

```bash
sed -e 's/name: snip-api$/name: snip-api-kapot/' -e 's/app: snip-api /app: snip-apii /' \
  k8s/api/service.yaml | kubectl apply -f -
kubectl describe svc snip-api-kapot
```

<details>
<summary>Uitleg</summary>

`Endpoints:` is leeg. Het etiket `snip-apii` past op geen enkele pod. Kubernetes geeft **geen
foutmelding**: de Service bestaat, maar stuurt naar niemand.

Dus: werkt een Service niet, kijk dan eerst of hij **endpoints** heeft.

```bash
kubectl delete svc snip-api-kapot
```
</details>

### 💥 2. Een voordeur zonder programma

Er is ook een oudere manier om een voordeur te beschrijven: **Ingress**. Maak er een:

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

Kubernetes accepteert het, maar er gebeurt niets: `ADDRESS` blijft leeg. Er draait geen
programma dat naar Ingress-objecten kijkt; Envoy Gateway doet alleen Gateways.

Een Ingress of Gateway is alleen een **beschrijving**. Zonder programma dat hem uitvoert, gebeurt
er niets.

Je komt Ingress nog veel tegen, en het staat op het CKAD-examen. Maar het bekendste programma
erachter (*ingress-nginx*) is in 2026 gestopt, en nieuwe opzetten gebruiken de Gateway.

```bash
kubectl delete ingress snip-api
```
</details>

---

## Op je werk

- Services zijn bijna altijd **ClusterIP**. Van buiten komt alles via één centrale voordeur.
- Die voordeur (de Gateway) is van het **platformteam**. Jij levert een **HTTPRoute** aan, met je
  eigen hostnaam en paden.
- Werkt iets niet? Kijk van binnen naar buiten: draait de pod? → heeft de Service endpoints? →
  klopt de route (`kubectl describe httproute`)?

---

## Checkpoint

<details>
<summary>1. Maakt een Service de IP-adressen van je pods vast?</summary>

Nee. De pods blijven van adres wisselen. De Service heeft een eigen vaste naam en een eigen vast
adres, en stuurt door naar de pods van dat moment.
</details>

<details>
<summary>2. Hoe weet een Service welke pods erbij horen?</summary>

Via het etiket in de `selector`.
</details>

<details>
<summary>3. Een Service werkt niet, en er is geen foutmelding. Wat controleer je eerst?</summary>

Of hij endpoints heeft: `kubectl describe svc NAAM`.
</details>

<details>
<summary>4. Wat is het verschil tussen een Gateway en een HTTPRoute?</summary>

De Gateway is de voordeur. De HTTPRoute is de regel die zegt welk verkeer naar welke Service gaat.
</details>

### Eindopdracht

Zorg dat:
1. de Service **`snip-api`** bestaat, met 3 endpoints;
2. Envoy Gateway draait, de Gateway **`snip`** klaar is, en de HTTPRoute **`snip-api`** eraan hangt;
3. `k8s/` de drie nieuwe bestanden bevat, en de oefenobjecten weg zijn.

```bash
cd ~/Documents/local/docker-k8s-cursus/modules/10-services-en-gateway
./check.sh
```

Groen? In **module 11** komt de website erbij, met haar instellingen in een **ConfigMap** en het
database-wachtwoord in een **Secret**.

---

## Spiekbrief

| Commando | Wat het doet |
|---|---|
| `kubectl get svc` | Services |
| `kubectl describe svc NAAM` | o.a. IP en **Endpoints** |
| `kubectl run tmp --rm -it --restart=Never --image=curlimages/curl -- sh` | tijdelijke pod om in het cluster te testen |
| `kubectl get gateway,httproute` | voordeur en regels |
| `kubectl describe httproute NAAM` | klopt de route? |

**Verder in je eigen tempo:** de uitgebreide versie van deze module ([`README.md`](README.md))
gaat dieper in op de soorten Services (ClusterIP, NodePort, LoadBalancer), de volledige DNS-naam
`snip-api.default.svc.cluster.local`, `port-forward` naar een Service, en een route naar een
Service die niet bestaat.
