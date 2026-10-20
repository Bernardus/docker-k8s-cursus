# Module 07 — Automatisch deployen, met HTTPS

**Doel:** snip krijgt een adres met **HTTPS** (slotje in de browser), en elke push naar `main`
zet de nieuwe versie **automatisch** op je server: bouwen, scannen, deployen en controleren.
Je hoeft niet meer met de hand in te loggen.

**Tijd:** ±2 uur

**Nodig:** module 06 afgerond. snip draait op je droplet `209.38.110.50`, en `ssh snip` werkt.

> In deze module staan jouw eigen gegevens ingevuld:
>
> | | |
> |---|---|
> | IP-adres van je droplet | `209.38.110.50` |
> | Adres voor HTTPS | `209-38-110-50.sslip.io` |
> | GitHub-repo | `Bernardus/docker-k8s-cursus` |

---

## Uitleg

### Een naam voor je IP-adres: sslip.io

Een HTTPS-certificaat wordt uitgegeven voor een **naam** (zoals `snip.example.com`), niet voor
een kaal IP-adres. Je browser controleert dan of de server die hij bereikt echt bij die naam
hoort. Je zou een domein kunnen kopen, maar er is een gratis alternatief:
**[sslip.io](https://sslip.io)**. Dat is een DNS-dienst die elke naam van de vorm
`<ip-met-streepjes>.sslip.io` vertaalt naar dat IP-adres:

```
209-38-110-50.sslip.io  ──DNS──►  209.38.110.50
```

Je hoeft niets in te stellen: die naam werkt al.

### HTTPS met Caddy

Voor HTTPS heb je een certificaat nodig, en dat moet je elke paar maanden vernieuwen. **Caddy**
is een webserver die dat helemaal zelf doet:

1. Caddy start en ziet in zijn configuratie de naam `209-38-110-50.sslip.io`.
2. Hij vraagt bij **Let's Encrypt** (een gratis certificaatuitgever) een certificaat aan.
3. Let's Encrypt controleert of die naam echt naar deze server wijst, via een verzoek op
   poort 80.
4. Caddy krijgt het certificaat, bewaart het, en vernieuwt het op tijd.

Caddy wordt de nieuwe voordeur. nginx blijft de webpagina serveren en `/api` doorsturen, maar
krijgt zelf geen poort naar buiten meer:

```
 internet
    │ :80 → doorsturen naar :443
    │ :443 (HTTPS)
┌───▼─────────────────────── droplet ─────────────────────────────┐
│  caddy ──► web (nginx) ──► api ──► db                            │
│    └─ volume caddy-data (certificaten)                           │
└──────────────────────────────────────────────────────────────────┘
```

Waarom nginx niet vervangen? Het kan, want Caddy kan ook bestanden serveren. Maar zo zie je
een opbouw die je overal tegenkomt: een aparte laag voor HTTPS vóór je apps. In Kubernetes heet
die laag straks een *Ingress* of *Gateway*.

### Push-deploy: de pipeline logt in op je server

```
 git push
    │
    ▼
 job build    bouwen → scannen → pushen naar GHCR      (module 05)
    │ geslaagd? geeft versie door, bijv. sha-abc1234
    ▼
 job deploy   (alleen op main)
    ├─ SSH-sleutel klaarzetten       uit de GitHub-secrets
    ├─ bestanden naar de server      rsync
    ├─ nieuwe versie starten         SNIP_VERSION=sha-abc1234 → docker compose up -d
    └─ controleren                   https://.../api/info geeft sha-abc1234?
```

De pipeline doet dus precies wat jij in module 06 met de hand deed, alleen met een eigen
sleutel. Dat noemen we een **push-deploy**: de pipeline duwt de nieuwe versie naar de server.
Onthoud dit woord. In deel 3 zie je de tegenhanger, **pull**: daar haalt Argo CD zelf op wat
er moet draaien.

### Secrets, variables en environments in GitHub

| | Voor | Zichtbaar? | Bij ons |
|---|---|---|---|
| **secret** | geheime waarden | nooit, ook niet in logs (wordt `***`) | de privé-SSH-sleutel, de host key |
| **variable** | gewone instellingen | ja | het IP-adres, het domein |
| **environment** | een doelomgeving, bijv. `production` | ja, met historie van deploys | `production` |

Secrets en variables hang je aan een **environment**. Alleen jobs die zeggen
`environment: production` kunnen erbij. Later (module 22) kun je op een environment ook regels
zetten, zoals "iemand moet eerst goedkeuren".

### Twee sleutels, twee rollen

| Sleutel | Van wie | Passphrase | Waar |
|---|---|---|---|
| `~/.ssh/snip_vps` | **jij** | ja | alleen op je Mac |
| `~/.ssh/snip_deploy` | **de pipeline** | nee (een pipeline kan niets typen) | privé: als GitHub-secret |

Een aparte sleutel voor de pipeline betekent: lekt hij ooit, dan haal je alleen die weg, en
jouw eigen toegang blijft werken.

---

## Lab

### Deel A — HTTPS

**1. Het adres werkt al**

```bash
dig +short 209-38-110-50.sslip.io
```

`209.38.110.50`. Open <http://209-38-110-50.sslip.io>: daar is snip al, zonder slotje.

**2. Een Caddyfile**

Op je Mac, in `app/`, maak het bestand `Caddyfile` (zonder extensie):

```
# Caddy is de voordeur van snip: hij regelt HTTPS (certificaat aanvragen en verlengen)
# en stuurt alles door naar nginx. {$SNIP_DOMAIN} komt uit .env op de server.
{$SNIP_DOMAIN} {
	encode
	reverse_proxy web:80
}
```

Dat is de hele configuratie. `encode` comprimeert de antwoorden, `reverse_proxy` stuurt alles
door naar de service `web`. HTTPS staat nergens: dat doet Caddy standaard.

**3. compose.server.yaml uitbreiden**

Twee wijzigingen in `app/compose.server.yaml`.

Bij `web`: **haal het `ports`-blok weg**. Caddy is nu de voordeur.

```yaml
  web:
    image: nginx:alpine
    restart: unless-stopped
    volumes:
      - ./web/site:/usr/share/nginx/html:ro
      - ./web/nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - api
```

Voeg `caddy` toe onder `services:`, en twee volumes onderaan:

```yaml
  caddy:
    image: caddy:2-alpine
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    environment:
      SNIP_DOMAIN: ${SNIP_DOMAIN:?zet SNIP_DOMAIN in .env}
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy-data:/data # certificaten: bewaren, anders vraagt Caddy er bij elke start een nieuw aan
      - caddy-config:/config
    depends_on:
      - web

volumes:
  db-data:
  caddy-data:
  caddy-config:
```

Twijfel je? Vergelijk met de [uitwerking](uitwerking/compose.server.yaml).

**4. Naar de server**

Op je Mac:

```bash
cd ~/Documents/local/docker-k8s-cursus
rsync -av app/Caddyfile snip:snip/Caddyfile
rsync -av app/compose.server.yaml snip:snip/compose.yaml
ssh snip "echo SNIP_DOMAIN=209-38-110-50.sslip.io >> snip/.env"
```

**5. Starten**

```bash
ssh snip
cd snip
docker compose up -d
docker compose logs -f caddy
```

Wacht op een regel met `certificate obtained successfully`. Dat duurt meestal een paar
seconden. `Ctrl+C` stopt het meekijken.

**6. Het slotje**

Open **<https://209-38-110-50.sslip.io>**: snip, met een slotje. Klik op het slotje: het
certificaat is uitgegeven door **Let's Encrypt** voor `209-38-110-50.sslip.io`.

Op je Mac:

```bash
curl -sI http://209-38-110-50.sslip.io | head -3
```

`308 Permanent Redirect` naar `https://...`. Caddy stuurt gewoon `http` automatisch door. En
`http://209.38.110.50` (het kale IP-adres)? Dat geeft nu een lege pagina: Caddy bedient alleen de
naam waarvoor hij een certificaat heeft. Vanaf nu is snip `https://209-38-110-50.sslip.io`.

### Deel B — Sleutels en geheimen voor de pipeline

**7. Een sleutel voor de pipeline**

Op je Mac, **zonder** passphrase (druk twee keer op Enter, of gebruik `-N ""` zoals hieronder):

```bash
ssh-keygen -t ed25519 -C "github-actions-snip" -f ~/.ssh/snip_deploy -N ""
```

Zet de publieke sleutel op de server, naast die van jezelf:

```bash
ssh snip 'cat >> ~/.ssh/authorized_keys' < ~/.ssh/snip_deploy.pub
ssh -i ~/.ssh/snip_deploy -o IdentitiesOnly=yes deploy@209.38.110.50 whoami
```

`deploy`: de pipeline-sleutel werkt.

**8. De vingerafdruk van je server**

Als de pipeline verbinding maakt, moet hij zeker weten dat hij met **jouw** server praat en
niet met een bedrieger ertussen. Daarvoor geef je hem de *host key* van je server, zoals jouw Mac
die bij de eerste keer `ssh` onthield (`yes` op de fingerprint-vraag):

```bash
ssh-keyscan -t ed25519 209.38.110.50
```

Eén regel met `209.38.110.50 ssh-ed25519 AAAA...`.

**9. Environment, secrets en variables op GitHub**

```bash
cd ~/Documents/local/docker-k8s-cursus
gh api -X PUT repos/Bernardus/docker-k8s-cursus/environments/production --silent
gh secret set DEPLOY_SSH_KEY --env production < ~/.ssh/snip_deploy
known_hosts=$(ssh-keyscan -t ed25519 209.38.110.50 2>/dev/null)
echo "$known_hosts"   # moet één regel zijn: 209.38.110.50 ssh-ed25519 AAAA...
gh secret set DEPLOY_KNOWN_HOSTS --env production --body "$known_hosts"
gh variable set DEPLOY_HOST --env production --body 209.38.110.50
gh variable set SNIP_DOMAIN --env production --body 209-38-110-50.sslip.io
```

Controleer op GitHub: **Settings → Environments → production**. Je ziet de twee secrets
(zonder waarde, die toont GitHub nooit meer) en de twee variables.

> De privésleutel staat nu op twee plekken: op je Mac en als secret bij GitHub. Op je Mac
> heb je hem niet meer nodig. Je mag hem weggooien, en dat is zelfs netter:
> `rm ~/.ssh/snip_deploy` (laat `snip_deploy.pub` gerust staan).

### Deel C — De pipeline deployt

**10. De workflow uitbreiden**

Vier wijzigingen in `.github/workflows/snip-api.yml`.

**a.** Bij `on:` (twee keer): `paths` wordt breder. Nu deployen we ook bij een wijziging aan de
website, de Caddyfile of het compose-bestand:

```yaml
    paths: ["app/**", ".github/workflows/snip-api.yml"]
```

**b.** De job `build` geeft de versie door aan de volgende job. Voeg direct onder
`runs-on: ubuntu-24.04` van `build` toe:

```yaml
    outputs:
      version: ${{ steps.versie.outputs.version }} # doorgeven aan de deploy-job
```

**c.** De stap "Naam en versie bepalen" krijgt een `id`, en schrijft de versie ook als output:

```yaml
      - name: Naam en versie bepalen
        id: versie
        run: |
          # GHCR accepteert alleen kleine letters in image-namen.
          echo "IMAGE=ghcr.io/${GITHUB_REPOSITORY_OWNER,,}/snip-api" >> "$GITHUB_ENV"
          echo "VERSION=sha-${GITHUB_SHA::7}" >> "$GITHUB_ENV"
          echo "version=sha-${GITHUB_SHA::7}" >> "$GITHUB_OUTPUT"
```

**d.** Helemaal onderaan, een tweede job (inspringen op dezelfde hoogte als `build:`):

```yaml
  deploy:
    needs: build # pas na een geslaagde build
    if: github.ref == 'refs/heads/main' && github.event_name != 'pull_request'
    runs-on: ubuntu-24.04
    environment:
      name: production
      url: https://${{ vars.SNIP_DOMAIN }}
    concurrency: production # nooit twee deploys tegelijk
    env:
      HOST: ${{ vars.DEPLOY_HOST }}
      DOMAIN: ${{ vars.SNIP_DOMAIN }}
      VERSION: ${{ needs.build.outputs.version }}
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1

      - name: SSH klaarzetten
        env:
          SSH_KEY: ${{ secrets.DEPLOY_SSH_KEY }}
          KNOWN_HOSTS: ${{ secrets.DEPLOY_KNOWN_HOSTS }}
        run: |
          if [ -z "$SSH_KEY" ] || [ -z "$KNOWN_HOSTS" ]; then
            echo "::error::DEPLOY_SSH_KEY of DEPLOY_KNOWN_HOSTS is leeg (stap 9)"
            exit 1
          fi
          install -m 700 -d ~/.ssh
          printf '%s\n' "$SSH_KEY" > ~/.ssh/id_ed25519
          chmod 600 ~/.ssh/id_ed25519
          printf '%s\n' "$KNOWN_HOSTS" > ~/.ssh/known_hosts

      - name: Bestanden naar de server
        run: |
          rsync -av --delete app/web app/db "deploy@$HOST:snip/"
          rsync -av app/Caddyfile "deploy@$HOST:snip/Caddyfile"
          rsync -av app/compose.server.yaml "deploy@$HOST:snip/compose.yaml"

      - name: Nieuwe versie starten
        run: |
          # $VERSION wordt bewust hier al ingevuld, vóór het commando naar de server gaat.
          # shellcheck disable=SC2029
          ssh "deploy@$HOST" "cd snip \
            && sed -i '/^SNIP_VERSION=/d' .env \
            && echo 'SNIP_VERSION=$VERSION' >> .env \
            && docker compose pull --quiet \
            && docker compose up -d --remove-orphans"

      - name: Controleren of de nieuwe versie draait
        run: |
          for _ in $(seq 1 20); do
            if curl -fsS "https://$DOMAIN/api/info" | grep -q "\"versie\":\"$VERSION\""; then
              echo "✔ $VERSION draait op https://$DOMAIN"
              exit 0
            fi
            sleep 3
          done
          echo "✘ na 60 seconden draait $VERSION nog niet op https://$DOMAIN"
          exit 1
```

De hele workflow staat ook in de [uitwerking](uitwerking/.github/workflows/snip-api.yml).

Wat de nieuwe onderdelen doen:

| Onderdeel | Wat |
|---|---|
| `needs: build` | deploy start pas als build geslaagd is, dus ook pas als de scan groen is |
| `if: ... main ...` | alleen deployen vanaf `main`, nooit vanuit een pull request |
| `environment: production` | toegang tot de secrets en variables van `production`, en een deploy-historie op GitHub |
| `concurrency: production` | twee pushes kort na elkaar? Dan wacht de tweede deploy tot de eerste klaar is |
| `${{ needs.build.outputs.version }}` | de versie die build doorgaf, bijv. `sha-abc1234` |
| `rsync --delete` | `web/` en `db/` op de server worden precies gelijk aan Git |
| `sed ... SNIP_VERSION` | zet de versie vast in `.env` op de server, zodat een herstart dezelfde versie houdt |
| `docker compose pull` + `up -d` | nieuwe images ophalen, en alleen containers vervangen die veranderd zijn |
| de controle-stap | pas groen als de site echt de nieuwe versie geeft, via HTTPS |

Er staan **geen** actions van derden in om SSH te doen. `ssh` en `rsync` staan al op de runner.
Elke action die je niet gebruikt, kan ook niet gehackt worden (module 05).

**11. Committen en pushen**

```bash
cd ~/Documents/local/docker-k8s-cursus
git add app/Caddyfile app/compose.server.yaml .github/workflows/snip-api.yml
git commit -m "Automatisch deployen naar de droplet, met HTTPS"
git push
gh run watch
```

Je ziet nu twee jobs: **build** en daarna **deploy**. Het eindigt met:

```
✔ sha-abc1234 draait op https://209-38-110-50.sslip.io
```

Op de pagina van je repo staat rechts nu **Deployments → production**, met een link naar je
site.

**12. Een zichtbare wijziging**

Pas de ondertitel van de website aan. Dit commando doet het voor je:

```bash
sed -i '' 's|Korte links. Web (nginx)|Korte links, automatisch gedeployd. Web (nginx)|' app/web/site/index.html
git commit -am "Nieuwe ondertitel"
git push
gh run watch
```

Ververs <https://209-38-110-50.sslip.io>: de nieuwe tekst staat er. Van commit tot live, zonder
dat je de server hebt aangeraakt.

**13. Terug naar een vorige versie**

Elke versie staat met zijn eigen tag in GHCR. Een vorige versie terugzetten is dus alleen een
andere tag kiezen:

```bash
gh run list --workflow snip-api.yml --branch main --status success --limit 5 \
  --json headSha,displayTitle --jq '.[] | "sha-\(.headSha[0:7])  \(.displayTitle)"'
```

Elke geslaagde run op `main` heeft een image met de tag `sha-` plus de eerste 7 tekens van zijn
commit.

Kies een oudere `sha-...` en zet die op de server:

```bash
ssh snip "cd snip && sed -i '/^SNIP_VERSION=/d' .env && echo SNIP_VERSION=sha-xxxxxxx >> .env && docker compose up -d"
curl -s https://209-38-110-50.sslip.io/api/info
```

Je draait de oude versie. Dit is een **rollback**: binnen seconden, zonder iets te bouwen. De
volgende push zet automatisch weer de nieuwste versie neer.

> Een rollback met de hand op de server is een noodgreep: wat er draait, wijkt dan af van
> wat er in Git staat. In deel 3 doe je een rollback netjes via Git, en houdt Argo CD de
> server en Git gelijk.

---

## Breek het

### 💥 1. Een vervalste server

Stel dat iemand zich tussen GitHub en je server heeft gezet. Speel het na door de pipeline een
**verkeerde** host key te geven: die van GitHub zelf.

```bash
gh secret set DEPLOY_KNOWN_HOSTS --env production --body "$(ssh-keyscan -t ed25519 github.com 2>/dev/null | sed 's/^github.com/209.38.110.50/')"
gh workflow run snip-api.yml
sleep 5
gh run watch
```

<details>
<summary>Uitleg en oplossing</summary>

De stap "Bestanden naar de server" faalt met `Host key verification failed`. De pipeline ziet
dat de server een andere vingerafdruk heeft dan afgesproken, en weigert verbinding te maken.
Precies goed: zo stuurt hij nooit bestanden of commando's naar een bedrieger.

Je ziet ook: de deploy faalt, maar **de site draait gewoon door** met de vorige versie. Een
mislukte deploy laat niets kapot achter.

Zet de juiste vingerafdruk terug, en start opnieuw:

```bash
gh secret set DEPLOY_KNOWN_HOSTS --env production --body "$(ssh-keyscan -t ed25519 209.38.110.50 2>/dev/null)"
gh workflow run snip-api.yml
```
</details>

### 💥 2. Poort 443 dicht

Haal bij DigitalOcean in je firewall `snip-fw` de regel voor **HTTPS (443)** weg, en open
<https://209-38-110-50.sslip.io>.

<details>
<summary>Uitleg</summary>

De site laadt niet. `http://` werkt nog wel, maar stuurt je door naar `https://`, en daar komt
niemand doorheen. Laag voor laag, net als in module 06: Caddy draait, het certificaat is er, maar
de firewall houdt 443 tegen.

Zet de regel terug.
</details>

### 💥 3. Wat als `caddy-data` geen volume was?

<details>
<summary>Uitleg</summary>

Dan zou Caddy bij elke herstart (elke deploy, elke reboot) een **nieuw** certificaat aanvragen.
Let's Encrypt heeft limieten: na te veel aanvragen voor dezelfde naam in een week krijg je even
geen certificaten meer, en dan staat je site zonder HTTPS. Certificaten zijn dus ook
**data die moet blijven bestaan**, net als je database. Daarom krijgen ze een volume.

(Caddy probeert in dat geval automatisch een tweede uitgever, ZeroSSL, maar daar wil je niet op
leunen.)
</details>

---

## Op je werk

- **Push-deploy via SSH** zie je bij kleinere projecten veel. Bij jullie gaat het anders: de
  pipeline bouwt alleen, en **Argo CD haalt** de nieuwe versie zelf binnen (pull). De pipeline
  hoeft dan nergens op in te loggen, en er staan geen SSH-sleutels van productie in GitHub. Dat
  is veiliger, en daar gaat deel 3 over.
- **HTTPS** wordt in een enterprise zelden per app geregeld. Meestal zit er een centrale laag vóór:
  een Ingress- of Gateway-controller met **cert-manager** in Kubernetes, of Azure Front Door of
  Application Gateway. Jij krijgt een hostnaam, en het certificaat wordt voor je geregeld.
- **Environments met goedkeuring.** Bij jullie heeft `production` waarschijnlijk regels: alleen
  vanaf `main`, en iemand moet eerst goedkeuren. Dat stel je in module 22 zelf in.
- **Sleutels draaien.** Deploy-sleutels en secrets moeten regelmatig vervangen worden (*rotation*).
  Met OIDC (module 20) zijn er helemaal geen langlevende sleutels meer nodig.

---

## Checkpoint

<details>
<summary>1. Waarom gebruiken we <code>209-38-110-50.sslip.io</code> en niet gewoon het IP-adres?</summary>

Een HTTPS-certificaat wordt voor een naam uitgegeven. sslip.io geeft je gratis een naam die naar
je IP-adres wijst.
</details>

<details>
<summary>2. Waarom heeft <code>web</code> geen <code>ports</code> meer?</summary>

Caddy is de voordeur: hij neemt 80 en 443, regelt HTTPS en stuurt door naar `web`. Alleen
de voordeur hoeft van buiten bereikbaar te zijn.
</details>

<details>
<summary>3. Wat is het verschil tussen een secret en een variable in GitHub?</summary>

Een secret is geheim: je ziet hem nooit meer terug, ook niet in logs. Een variable is een gewone
instelling die iedereen met toegang mag zien.
</details>

<details>
<summary>4. Waarom heeft de pipeline een eigen sleutel, zonder passphrase?</summary>

Een pipeline kan geen passphrase typen. Met een eigen sleutel kun je die van de pipeline intrekken
zonder dat jouw toegang verdwijnt.
</details>

<details>
<summary>5. Waarom geef je de pipeline de host key van je server mee?</summary>

Zodat hij zeker weet dat hij met jouw server praat. Bij een andere vingerafdruk weigert SSH
verbinding te maken (breek-het 1).
</details>

<details>
<summary>6. Wat is het verschil tussen een push-deploy en een pull-deploy?</summary>

Bij push logt de pipeline in op de server en zet de nieuwe versie neer. Bij pull (Argo CD) kijkt
het cluster zelf in Git wat er moet draaien, en haalt het dat op. De pipeline hoeft er dan
niet bij te kunnen.
</details>

### Eindopdracht

Als je het lab hebt gedaan, heb je alles. Controleer vanaf je Mac:

```bash
cd ~/Documents/local/docker-k8s-cursus/modules/07-automatisch-deployen
./check.sh
```

Het script controleert: HTTPS met een geldig certificaat, de doorsturing van http naar https, dat
alleen Caddy van buiten bereikbaar is, het environment met secrets en variables op GitHub, en dat
de laatste run op `main` heeft gedeployd en de site precies die versie draait.

Groen? Dan heb je **deel 1 afgerond**. Je kunt een app in containers verpakken, lokaal met
Compose draaien, en via een pipeline met HTTPS online zetten. In **deel 2** gaat snip naar
Kubernetes. Dan zie je wat Kubernetes toevoegt aan wat je nu hebt.

---

## Spiekbrief

| Commando | Wat het doet |
|---|---|
| `dig +short NAAM` | naar welk IP-adres wijst een naam? |
| `curl -sI URL` | alleen de headers (status, doorsturing) |
| `ssh-keygen -t ed25519 -f PAD -N ""` | sleutel zonder passphrase (voor machines) |
| `ssh-keyscan -t ed25519 HOST` | vingerafdruk (host key) van een server |
| `gh secret set NAAM --env ENV` | secret zetten (waarde via `<` of `--body`) |
| `gh variable set NAAM --env ENV --body WAARDE` | variable zetten |
| `gh workflow run WORKFLOW` | workflow met de hand starten |
| `gh run watch` | lopende run volgen |

| Workflow | |
|---|---|
| `needs: job` | pas na die job |
| `outputs:` + `$GITHUB_OUTPUT` | een waarde doorgeven aan een volgende job |
| `environment: naam` | secrets/variables van die omgeving, en een deploy-historie |
| `concurrency: naam` | nooit twee runs met deze naam tegelijk |
| `${{ secrets.X }}` / `${{ vars.X }}` | secret / variable gebruiken |

| Caddyfile | |
|---|---|
| `naam { ... }` | site voor die naam, met automatische HTTPS |
| `reverse_proxy service:poort` | doorsturen |
| `encode` | antwoorden comprimeren |
