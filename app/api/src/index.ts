// snip-api: een kleine URL-shortener.
// Je hoeft deze code niet te schrijven of te begrijpen; de cursus gaat over hoe je hem verpakt en draait.

import { hostname } from 'node:os'
import { randomBytes } from 'node:crypto'
import { serve } from '@hono/node-server'
import { Hono } from 'hono'
import pg from 'pg'

// Alle instellingen komen uit environment variables, zodat hetzelfde image overal draait.
const port = Number(process.env.PORT ?? 3000)
const host = process.env.HOST ?? '0.0.0.0'
const version = process.env.APP_VERSION ?? 'dev'
const db = new pg.Pool({ connectionString: process.env.DATABASE_URL })

// Valt de database weg (herstart, nieuwe pod), dan breekt een open verbinding af. Zonder deze
// regel crasht de hele app daarop; nu loggen we het en maakt de pool later een nieuwe verbinding.
db.on('error', (err) => console.error('databaseverbinding verbroken:', foutTekst(err)))

const app = new Hono()

// Leesbare foutmelding, ook als er meerdere pogingen mislukten (bijv. IPv4 én IPv6).
const foutTekst = (err: unknown): string =>
  err instanceof AggregateError
    ? err.errors.map((e) => (e as Error).message).join('; ')
    : (err as Error).message

// Leeft de app? (Kubernetes gebruikt dit later als liveness probe.)
app.get('/health', (c) => c.json({ status: 'ok' }))

// Kan de app bij de database? (Later de readiness probe.)
app.get('/health/db', async (c) => {
  try {
    await db.query('SELECT 1')
    return c.json({ database: 'ok' })
  } catch (err) {
    return c.json({ database: 'onbereikbaar', fout: foutTekst(err) }, 503)
  }
})

// Welke container beantwoordt dit verzoek? Handig zodra er meerdere draaien.
app.get('/api/info', (c) =>
  c.json({ app: 'snip-api', versie: version, container: hostname(), node: process.version }),
)

app.get('/api/links', async (c) => {
  const { rows } = await db.query('SELECT code, url, created_at FROM links ORDER BY created_at')
  return c.json(rows)
})

app.post('/api/links', async (c) => {
  const body = await c.req.json<{ url?: string; code?: string }>().catch(() => ({}) as { url?: string; code?: string })
  if (!body.url || !URL.canParse(body.url)) {
    return c.json({ fout: 'geef een geldige url mee, bijv. {"url": "https://example.com"}' }, 400)
  }
  const code = body.code ?? randomBytes(3).toString('hex')
  const { rows } = await db.query(
    'INSERT INTO links (code, url) VALUES ($1, $2) ON CONFLICT (code) DO NOTHING RETURNING code, url, created_at',
    [code, body.url],
  )
  if (rows.length === 0) return c.json({ fout: `code "${code}" bestaat al` }, 409)
  return c.json(rows[0], 201)
})

// De eigenlijke shortener: /gh → doorsturen naar github.com
app.get('/:code', async (c) => {
  const { rows } = await db.query('SELECT url FROM links WHERE code = $1', [c.req.param('code')])
  if (rows.length === 0) return c.json({ fout: 'onbekende code' }, 404)
  return c.redirect(rows[0].url, 302)
})

app.onError((err, c) => {
  console.error(err)
  return c.json({ fout: err.message }, 500)
})

// Zorg dat de tabel bestaat. Lukt dat niet (database nog niet klaar), dan start de app toch;
// /health/db laat dan zien wat er mis is.
await db
  .query(
    `CREATE TABLE IF NOT EXISTS links (
       code       text PRIMARY KEY,
       url        text NOT NULL,
       created_at timestamptz NOT NULL DEFAULT now()
     )`,
  )
  .catch((err) => console.error('kon tabel niet aanmaken:', foutTekst(err)))

const server = serve({ fetch: app.fetch, port, hostname: host }, (info) => {
  console.log(`snip-api ${version} luistert op http://${info.address}:${info.port}`)
})

// Netjes afsluiten als Podman of Kubernetes "stop" zegt (SIGTERM), of bij Ctrl+C (SIGINT):
// geen nieuwe verzoeken meer aannemen, lopende afmaken, databaseverbindingen sluiten.
for (const signaal of ['SIGTERM', 'SIGINT'] as const) {
  process.on(signaal, () => {
    console.log(`${signaal} ontvangen, netjes afsluiten...`)
    server.close(() => db.end().finally(() => process.exit(0)))
    setTimeout(() => process.exit(1), 8000).unref() // noodrem
  })
}
