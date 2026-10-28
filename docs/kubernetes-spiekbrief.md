# Kubernetes in plaatjes

Een spiekbrief om de begrippen uit deel 2 te onthouden. Elk plaatje heeft een vergelijking die
het makkelijker maakt.

> **Zien:** GitHub toont deze diagrammen vanzelf. In VS Code installeer je de extensie
> *Markdown Preview Mermaid Support*, en open je de preview met **Cmd+Shift+V**.

**De vergelijking voor alles hieronder: een kantoorgebouw.**

| Kubernetes | Kantoor |
|---|---|
| cluster | het gebouw |
| control plane (het brein) | de directie en de planning |
| node | een verdieping |
| pod | een medewerker |
| namespace | een afdeling (verspreid over verdiepingen) |
| Deployment | de vacature: "we willen altijd 3 van deze" |
| Service | het algemene telefoonnummer van de afdeling |
| Gateway | de receptie, voor bezoekers van buiten |

---

## 1. Wat is een cluster?

Een cluster = **het brein + de nodes**. Je praat altijd met het brein, nooit direct met een node.

```mermaid
flowchart TB
    jij(["jij: kubectl"]) --> brein

    subgraph cluster["CLUSTER"]
        brein["CONTROL PLANE (het brein)<br/>onthoudt wat je wilt,<br/>beslist waar het draait"]
        brein --> n1
        brein --> n2
        brein --> n3
        subgraph n1["node 1"]
            p1["pod"]
            p2["pod"]
        end
        subgraph n2["node 2"]
            p3["pod"]
            p4["pod"]
        end
        subgraph n3["node 3"]
            p5["pod"]
        end
    end
```

| Begrip | In één zin |
|---|---|
| **cluster** | het hele systeem: brein + nodes |
| **node** | één machine (VM) waar pods op draaien |
| **pod** | een verpakking om (meestal één) container |

In **kind** zijn brein en node samen één container op je Mac. Op **AKS** zie je het brein niet:
dat beheert Microsoft.

---

## 2. Nodes zijn verticaal, namespaces zijn horizontaal

Een node is een **machine**. Een namespace is een **map** voor je spullen, dwars over alle
machines heen. Elke pod staat op één kruispunt: één namespace, één node.

```mermaid
flowchart TB
    subgraph ns1["namespace: snip"]
        direction LR
        a1["pod snip-api<br/>(node 1)"]
        a2["pod snip-api<br/>(node 2)"]
        a3["pod snip-web<br/>(node 3)"]
    end
    subgraph ns2["namespace: team-b"]
        direction LR
        b1["pod<br/>(node 1)"]
        b2["pod<br/>(node 3)"]
    end
    subgraph ns3["namespace: kube-system (Kubernetes zelf)"]
        direction LR
        k1["coredns<br/>(node 1)"]
        k2["kube-proxy<br/>(node 2)"]
        k3["kube-proxy<br/>(node 3)"]
    end
```

| | Node | Namespace |
|---|---|---|
| richting | verticaal | horizontaal |
| wat is het | een machine | een map / afdeling |
| wie kiest | de scheduler (automatisch) | jij (`-n`, of in de YAML) |
| typisch per | — | app, team of omgeving (niet per onderdeel!) |

API en website van **dezelfde app** staan in **dezelfde** namespace.

---

## 3. Deployment: "er moeten er altijd 3 zijn"

```mermaid
flowchart LR
    yaml["jouw YAML<br/>replicas: 3"] -->|kubectl apply| dep

    dep["Deployment snip-api<br/>(het plan)"] -->|maakt per versie| rs["ReplicaSet<br/>(bewaakt het aantal)"]
    rs --> p1["pod<br/>app=snip-api"]
    rs --> p2["pod<br/>app=snip-api"]
    rs --> p3["pod<br/>app=snip-api"]
```

**De lus die alles draaiende houdt:**

```mermaid
flowchart LR
    gewenst["GEWENST<br/>(jouw YAML)<br/>3 pods"] --> vergelijk{"klopt het?"}
    werkelijk["WERKELIJK<br/>(wat draait)<br/>2 pods"] --> vergelijk
    vergelijk -->|ja| niets["niets doen"]
    vergelijk -->|nee| herstel["verschil oplossen:<br/>1 pod starten"]
    herstel --> werkelijk
```

| Situatie | Wat Kubernetes doet |
|---|---|
| pod crasht of wordt verwijderd | nieuwe pod starten |
| `replicas: 3` → `5` in het bestand | 2 bijmaken |
| `kubectl scale` naar 5, daarna `apply` | terug naar wat het **bestand** zegt |
| nieuwe image-tag in het bestand | rolling update (zie 6) |

---

## 4. Etiketten: de lijm

Deployment en Service kennen elkaar niet. Ze vinden **dezelfde pods** via hetzelfde etiket.

```mermaid
flowchart LR
    dep["Deployment<br/>selector: app=snip-api"] -->|maakt| pods
    svc["Service<br/>selector: app=snip-api"] -->|zoekt| pods

    subgraph pods["pods met etiket app=snip-api"]
        p1["pod"]
        p2["pod"]
        p3["pod"]
    end
```

**Tikfout in een etiket?**
- in een **Deployment**: foutmelding (`selector does not match template labels`);
- in een **Service**: **geen** foutmelding, maar nul endpoints. Altijd eerst checken:
  `kubectl describe svc NAAM` → `Endpoints`.

---

## 5. Service: één vast nummer voor wisselende pods

Pods wisselen van adres. De Service maakt die **niet** vast, maar heeft een **eigen** vaste naam
en een eigen vast adres.

```mermaid
flowchart LR
    vrager["andere pod<br/>vraagt: snip-api"] -->|1. wat is snip-api?| dns["CoreDNS"]
    dns -->|2. dat is 10.96.151.14| vrager
    vrager -->|3. stuur naar 10.96.151.14| kp["regels van kube-proxy<br/>(op elke node)"]
    kp -->|4. kies er een| p1["pod 10.244.0.5"]
    kp -.-> p2["pod 10.244.0.6"]
    kp -.-> p3["pod 10.244.0.7"]
```

**Wie houdt wat bij?**

```mermaid
flowchart TB
    svc["Service snip-api<br/>(alleen een beschrijving)"]
    ep["EndpointSlice-controller<br/>lijst van pods die passen<br/>én klaar zijn"]
    kp["kube-proxy<br/>zet de lijst om in<br/>doorstuurregels op elke node"]
    dns["CoreDNS<br/>naam → vast adres"]

    svc --> ep --> kp
    svc --> dns
```

**Soorten Services** (elke volgende bevat de vorige):

| Type | Bereikbaar vanaf | Kantoor |
|---|---|---|
| **ClusterIP** | alleen binnen het cluster | intern telefoonnummer |
| **NodePort** | + een poort (30000–32767) op elke node | + een zijdeur op elke verdieping |
| **LoadBalancer** | + een publiek IP van de cloud | + een eigen buitendeur |

---

## 6. Een nieuwe versie: de rolling update

Met `maxSurge: 1` en `maxUnavailable: 0`: er draaien er nooit minder dan 3.

```mermaid
sequenceDiagram
    participant D as Deployment
    participant Oud as ReplicaSet oud (3)
    participant Nieuw as ReplicaSet nieuw (0)
    participant S as Service

    D->>Nieuw: start 1 nieuwe pod
    Nieuw-->>S: nieuwe pod is klaar → krijgt verkeer
    D->>Oud: stop 1 oude pod (eerst van de lijst af)
    D->>Nieuw: start nog 1
    Nieuw-->>S: klaar
    D->>Oud: stop nog 1
    D->>Nieuw: start de laatste
    Nieuw-->>S: klaar
    D->>Oud: stop de laatste (blijft bewaard met 0)
    Note over Oud: kubectl rollout undo<br/>zet deze weer aan
```

**Nieuwe versie start niet?** Dan stopt de update, en blijven de oude pods verkeer bedienen.

---

## 7. Van buiten naar binnen: de Gateway

```mermaid
flowchart LR
    mac(["jouw Mac /<br/>internet"]) --> gw

    subgraph cluster["cluster"]
        gw["Gateway snip<br/>(de receptie)"]
        r1["HTTPRoute snip-api<br/>/api → snip-api"]
        r2["HTTPRoute snip-web<br/>/ → snip-web<br/>(module 11)"]
        s1["Service snip-api"]
        s2["Service snip-web"]
        gw --> r1 --> s1 --> pa["pods api"]
        gw --> r2 --> s2 --> pw["pods web"]
    end
```

| Stuk | Wat | Op je werk van |
|---|---|---|
| **GatewayClass** | welk programma de voordeur is (bijv. Envoy) | platformteam |
| **Gateway** | de voordeur zelf: poorten, HTTPS | platformteam |
| **HTTPRoute** | de regels: welk adres naar welke Service | **jij** |
| **Ingress** | oudere manier: voordeur + regels in één object | (kom je nog tegen) |

Een Gateway of Ingress zonder programma dat hem uitvoert, doet **niets**.

---

## 8. Waar zijn adressen geldig?

```mermaid
flowchart TB
    subgraph pod["binnen één pod"]
        lh["localhost<br/>= de pod zelf<br/>(alle containers erin)"]
    end
    subgraph ns["binnen dezelfde namespace"]
        kort["snip-api<br/>(korte naam van een Service)"]
    end
    subgraph cl["binnen het hele cluster"]
        lang["snip-api.default.svc.cluster.local<br/>(volledige naam)"]
    end
    subgraph buiten["van buiten"]
        gwadres["via de Gateway<br/>(in kind: port-forward)"]
    end
    pod --> ns --> cl --> buiten
```

---

## 9. Wie doet wat?

```mermaid
flowchart LR
    subgraph jij["jij / de pipeline"]
        code["code"] --> img["image<br/>(GHCR)"]
        yaml["YAML<br/>(k8s/)"]
    end
    subgraph k8s["Kubernetes"]
        brein["brein"] --> kubelet["kubelet<br/>(op elke node)"] --> runtime["containerd<br/>start de containers"]
    end
    yaml -->|kubectl apply<br/>later: Argo CD| brein
    img -->|wordt opgehaald door| runtime
```

| Wie | Doet |
|---|---|
| **jij** | YAML schrijven en aanpassen |
| **pipeline** | images bouwen (later ook: nieuwe tag in Git zetten) |
| **Argo CD** (deel 3) | YAML uit Git naar het cluster brengen |
| **brein** | onthouden en beslissen |
| **kubelet** | op een node zorgen dat pods echt draaien |
| **containerd** | containers starten (geen Docker, geen Podman) |

---

## 10. Er werkt iets niet: van binnen naar buiten

```mermaid
flowchart TB
    start(["werkt niet"]) --> p{"kubectl get pods<br/>Running en 1/1?"}
    p -->|ImagePullBackOff| ip["describe pod → Events<br/>tikfout? privé image?"]
    p -->|CrashLoopBackOff| cl["logs --previous<br/>wat zei hij?"]
    p -->|Pending| pe["describe pod → Events<br/>geen ruimte op een node?"]
    p -->|ja| s{"describe svc<br/>heeft Endpoints?"}
    s -->|nee| lab["etiket in de selector<br/>klopt niet"]
    s -->|ja| r{"describe httproute<br/>ResolvedRefs: True?"}
    r -->|nee| rn["route wijst naar<br/>verkeerde Service"]
    r -->|ja| g{"get gateway<br/>Programmed: True?"}
    g -->|nee| gw["voordeur niet klaar"]
    g -->|ja| ctx["klopt je context?<br/>kubectl config current-context"]
```
