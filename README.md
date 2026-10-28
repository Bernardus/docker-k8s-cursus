# Docker & Kubernetes — van nul tot productie

Een hands-on cursus waarin je één TypeScript-app met **Podman** containeriseert, op Kubernetes zet,
met **GitHub Actions en Argo CD** deployt naar een goedkope server en naar **Azure (AKS)**,
en tot slot leert hoe dit in een **enterprise** werkt: met centrale workflows en een platformteam
dat de Kubernetes-infrastructuur beheert.

## De rode draad: `snip`

Je bouwt en deployt de hele cursus door dezelfde app: **snip**, een URL-shortener.

```
                ┌──────────────┐
  browser ────► │  web         │  Vite + React (TS), geserveerd door nginx
                └──────┬───────┘
                       │ /api
                ┌──────▼───────┐
                │  api         │  Node 24 + Hono (TS)
                └───┬──────┬───┘
                    │      │
            ┌───────▼─┐  ┌─▼───────┐
            │ postgres│  │ redis   │  links opslaan · redirects cachen + kliks tellen
            └─────────┘  └─────────┘
```

Klein genoeg om te overzien, groot genoeg om alles tegen te komen wat in het echt ook
speelt: meerdere services, een database met data die niet kwijt mag, configuratie,
secrets, caching, healthchecks en schalen.

## Roadmap

| Deel | # | Module | Status |
|---|---|---|---|
| **1 · Containers & Compose** (Podman lokaal, Docker op de server) | 00 | [Setup & denkmodel](modules/00-setup/) | ✅ klaar |
| | 01 | [Eerste containers](modules/01-eerste-containers/) | ✅ klaar |
| | 02 | [Netwerken & data](modules/02-netwerken-en-data/): containers op naam laten praten, volumes, bind mounts | ✅ klaar |
| | 03 | [Je eerste eigen image](modules/03-eigen-image/): Dockerfile, layers, multi-stage (de `api`) | ✅ klaar |
| | 04 | [Compose](modules/04-compose/) (`podman compose`): de hele app met één commando | ✅ klaar |
| | 05 | [Productierijp image + eerste CI](modules/05-productierijp-en-ci/): GitHub Actions bouwt, scant en pusht naar GHCR | ✅ klaar |
| | 06 | [Je eigen server](modules/06-eigen-server/): droplet bij DigitalOcean, SSH, firewall, Docker, snip online met Compose | ✅ klaar |
| | 07 | [Automatisch deployen](modules/07-automatisch-deployen/): GitHub Actions → server via SSH, HTTPS met Caddy en sslip.io | ✅ klaar |
| **2 · Kubernetes** (lokaal, op Podman) | 08 | [Waarom Kubernetes, en je eerste cluster](modules/08-kubernetes-basis/): architectuur, Podman-pods, kind, kubectl `CKAD` | ✅ klaar |
| | 09 | [Deployments](modules/09-deployments/): kopieën die zichzelf herstellen, rolling updates, rollback `CKAD` | ✅ klaar |
| | 10 | [Services en de Gateway](modules/10-services-en-gateway/): vaste adressen, load balancing, Envoy Gateway, Ingress `CKAD` | ✅ klaar |
| | 11 | [ConfigMaps en Secrets](modules/11-configmaps-en-secrets/): de website erbij, wachtwoord in een Secret `CKAD` | ✅ klaar |
| | 12 | [Opslag](modules/12-opslag/): de database in het cluster, met een PVC en een StatefulSet `CKAD` | ✅ klaar |
| | 13 | [Probes, resources en autoscaling](modules/13-probes-en-schalen/): gezond of niet, grenzen aan CPU en geheugen, en meeschalen bij drukte `CKAD` | ✅ klaar |
| | 14 | Helm (en Kustomize) `CKAD` | 🔜 |
| | 15 | Namespaces, RBAC, quota, NetworkPolicies: meerdere teams in één cluster `CKAD` | 🔜 |
| | 16 | Debuggen als een pro: events, logs, k9s, klassieke fouten `CKAD` | 🔜 |
| **3 · GitOps met Argo CD** (lokaal) | 17 | Argo CD: Applications, sync, self-heal, rollback | 🔜 |
| | 18 | CI + CD: Actions bouwt → nieuwe tag in Git → Argo CD rolt uit, met omgevingen dev/prod | 🔜 |
| **4 · Live met Kubernetes** | 19 | **4a** k3s op je droplet (dezelfde als in module 06): HTTPS met cert-manager | 🔜 |
| | 20 | **4b** AKS met Terraform: ACR, OIDC vanuit GitHub, wegwerpcluster | 🔜 |
| | 21 | **4b** Azure-integraties: Workload Identity, Key Vault + External Secrets, Gateway API | 🔜 |
| **5 · Zo werkt het in een enterprise** | 22 | Platformteam vs. app-team + centrale workflows (reusable workflows, composite actions, environments met goedkeuring) | 🔜 |
| | 23 | Centrale cluster-infra: platform-repo, add-ons via Argo CD, team-onboarding met ApplicationSets en AppProjects | 🔜 |
| | 24 | Guardrails & OTAP: Kyverno-policies, promotie dev → acc → prod via pull requests | 🔜 |
| | 25 | Eindproject: een tweede team onboarden, één Argo CD voor twee clusters (VPS + AKS) | 🔜 |

**Hoe de delen op elkaar voortbouwen:**

- In deel 1 zet je snip eerst met Compose online op je eigen server. Zo voel je later precies
  wat Kubernetes daaraan toevoegt.
- In deel 1 t/m 4 bouw je **alles zelf**. Zo begrijp je elk onderdeel.
- In deel 5 **splits** je het op zoals een enterprise dat doet. Je speelt dan zowel het
  platformteam als het app-team. Daarna weet je op je werk wat er achter die centrale workflows en
  het cluster zit, en welk deel van jou is.
- 4a en 4b staan los van elkaar. Doe er één of allebei. In module 25 komen ze samen.

**Achtergrond:** [An Introduction to Kubernetes](docs/kubernetes-introduction.md) (Engels): het hele
plaatje van Kubernetes op één plek, als naslag bij deel 2 en verder.
[Kubernetes in plaatjes](docs/kubernetes-spiekbrief.md): spiekbrief met diagrammen (cluster, nodes,
namespaces, Deployments, Services, Gateway) om de begrippen te onthouden.

Modules met `CKAD` dekken stof van het CKAD-examen (zie [Certificaat](#certificaat-nodig)).

## Thuis vs. op je werk

| Onderdeel | In deze cursus | Typisch in een enterprise |
|---|---|---|
| **CI** | eerst je eigen workflow, in deel 5 een reusable workflow in je eigen GitHub-organisatie | het platformteam beheert centrale reusable workflows; jouw repo roept ze aan met een paar regels |
| **Lokaal** | Podman | Podman (of Docker Desktop met een bedrijfslicentie) |
| **Registry** | GHCR, later ACR | ACR, alleen goedgekeurde basis-images, Docker Hub via een proxy |
| **Cluster** | lokaal cluster op Podman → k3s op een VPS → AKS als wegwerpcluster | meerdere AKS-clusters (OTAP), door het platformteam beheerd met Terraform |
| **CD** | Argo CD die je zelf installeert en beheert | één centrale Argo CD; jij krijgt een *AppProject* en levert alleen je eigen config aan |
| **Toegang** | je bent overal admin | RBAC via Entra ID-groepen: jij mag alleen in je eigen namespaces |
| **Secrets** | Kubernetes Secrets → Key Vault + External Secrets | Key Vault, nooit secrets in Git |
| **Guardrails** | Kyverno-policies die je zelf schrijft | policies die je deploy tegenhouden ("geen `:latest`", "limits verplicht") |

Elke module heeft een blok **"Op je werk"** dat deze vertaalslag per onderwerp maakt.

## Zo werkt elke module

1. **Uitleg**: het waarom, met schema's. Kort.
2. **Lab**: stap voor stap, met per stap uitleg over wat er gebeurt.
3. **Breek het**: iets gaat bewust kapot en jij vindt uit waarom. Hints en antwoorden zitten
   ingeklapt.
4. **Op je werk**: hoe dit gaat in een enterprise met een platformteam en centrale workflows.
5. **Checkpoint**: een paar vragen plus een eindopdracht die je controleert met `./check.sh`.
6. **Spiekbrief**: alle commando's uit de module op één plek.

**Je schrijft geen app-code.** Alle code, HTML en SQL staan klaar (in `bestanden/` of `app/`). Jij
leert de commando's en de configuratie die bij containers en Kubernetes hoort: Dockerfile,
`compose.yaml`, Kubernetes-YAML en workflows. Die bouwen we stap voor stap op in de README. Je
kunt elk blok overnemen, en per module staat er een uitwerking klaar.

Loop je vast, open dan Claude in deze map en vraag om hulp. Plak de foutmelding erbij.

## Wat het kost

| Wat | Wanneer nodig | Kosten |
|---|---|---|
| Podman + Podman Desktop | vanaf 00 | €0 (open source) |
| GitHub, Actions, GHCR, een eigen GitHub-organisatie | vanaf 05 | €0 met publieke repo's (zie hieronder) |
| Droplet bij DigitalOcean | modules 06–07 en 19 | $12 per maand (1 vCPU / 2 GB), voor k3s in module 19 opschalen naar $24 (2 vCPU / 4 GB). Per seconde afgerekend; weggooien als je hem niet gebruikt |
| Azure (AKS + ACR) | 4b en 23 | $200 gratis tegoed voor nieuwe accounts (30 dagen). Daarna kost een wegwerpcluster centen per uur. Een cluster dat altijd aanstaat kost ca. $50–60 per maand. |
| Domeinnaam | optioneel | €0 met `sslip.io`, of ca. €1–15 per jaar |
| CKAD-examen | optioneel | $445 (ca. €380–400), vaak 30–50% korting rond Black Friday |

**Tips om te besparen:**

- **Azure:** kijk of je via je werk een *Visual Studio-abonnement* hebt. Daar zit vaak $50–150
  Azure-tegoed per maand bij. Vraag even of je dat voor eigen leerprojecten mag gebruiken.
- **GitHub:** gebruik publieke repo's. Dan zijn *environments met verplichte goedkeuring*
  ook op het gratis plan beschikbaar. *Required workflows* (centrale workflows die je
  organisatie-breed afdwingt) zijn een Enterprise-functie. Die leggen we uit, maar je kunt ze
  thuis niet nabouwen.
- **Server:** we gebruiken een droplet bij DigitalOcean. Hetzner en netcup zijn goedkoper, maar
  vragen bij nieuwe accounts soms om een identiteitscontrole. Een uitgezette droplet kost nog
  steeds geld; alleen een verwijderde niet.

## Certificaat nodig?

**Kort antwoord: nee, maar het kan handig zijn.**

- Voor developers is **CKAD** (Certified Kubernetes Application Developer) het juiste
  examen. CKA is voor cluster-beheerders, CKS gaat over security. KCNA is meerkeuze en
  theoretisch; die kun je overslaan.
- CKAD is een **praktijkexamen**: 2 uur lang opdrachten in een echte terminal, online
  gesurveilleerd. Voor de prijs krijg je ook **één gratis herkansing** en **twee
  oefensessies op killer.sh**. Het certificaat is 2 jaar geldig.
- **Wat het je oplevert:** recruiters en consultancies filteren er soms op, en het dwingt je
  om snel met `kubectl` te worden. **Wat het niet doet:** bewijzen dat je iets in productie
  kunt draaien. Een publieke repo met werkende CI/CD en een live Kubernetes-deploy (precies
  wat je hier bouwt) zegt in een sollicitatie minstens zoveel.
- **Advies:** doe eerst deel 1 en 2 en beslis dan. Denk je nu al "ik ga het waarschijnlijk
  doen"? Black Friday / Cyber Monday is eind november, en een voucher is **12 maanden
  geldig** na aankoop.

## Bronnen

Opgezocht op 13-10-2026. Check prijzen zelf vóór je iets koopt.

- Certificaat: [CKAD-prijs](https://institute.sfeir.com/en/kubernetes-training/faq-certification-ckad/) ·
  [prijsverhoging CKA/CKAD/CKS](https://macmyths.com/new-certification-pricing-cka-ckad-cks-and-lfcs-costs-explained/)
- VPS: [Hetzner-prijzen 2026](https://wz-it.com/en/blog/hetzner-price-increase-june-2026-cpx-ccx-alternatives/) ·
  [Hetzner CX/CAX-beschikbaarheid](https://stackvaluelab.com/hetzner-cx-cax-unavailable/) ·
  [Oracle Free Tier-limieten](https://www.infoq.com/news/2026/07/oracle-cloud-free-tier-limits/) ·
  [netcup vs Contabo](https://www.eucloudcost.com/compare/contabo-vs-netcup/)
- Azure: [AKS-tiers](https://azure.microsoft.com/updates/generally-available-azure-kubernetes-service-introduces-two-pricing-tiers-free-and-standard) ·
  [Standard_B2s-prijs](https://www.devzero.io/instances/azure/Standard_B2s) ·
  [Load Balancer-kosten](https://cloudcostkit.com/guides/azure-load-balancer-pricing/) ·
  [Azure free account](https://azure.microsoft.com/en-us/pricing/free-trial-faq/) ·
  [AKS en ingress-nginx](https://blog.aks.azure.com/2025/11/13/ingress-nginx-update)
- GitHub: [environments en plannen](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments) ·
  [required workflows via rulesets](https://github.blog/changelog/2023-08-02-github-actions-required-workflows-will-move-to-repository-rules/)
- Containers: [Docker Desktop-licentie](https://docs.docker.com/subscription/desktop-license/) ·
  [Podman-documentatie](https://docs.podman.io)
