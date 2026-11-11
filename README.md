# fastify-api

Vercel's [Fastify on Vercel](https://github.com/vercel/vercel/tree/main/examples/fastify)
template — a [Fastify](https://fastify.dev/) server whose one route, `GET /`,
answers with the template's welcome page, its logger on — running as one
**Cloudflare Worker**: upstream's `fastify.listen({ port: 3000 })`, and the
Workers runtime's Node.js HTTP server support (`httpServerHandler` from
`cloudflare:node`) hands that server every request. Bundled by wrangler, and
packaged as an **Orun baseline**: one command takes a new app from nothing to
live on stage and prod, in its own repository, under its own name — in ONE
landing.

The template's code is the code. What the port adds is the Worker's entry
(`fastify.listen`, awaited at startup, behind `httpServerHandler`), the Worker's
config, the monorepo wrapper, a test package, the deploy contract and a
`/health` route the deploy smoke-tests; what it changes is Fastify's
`pluginTimeout` (off: a Worker cannot set a timer while it starts up), where
pino comes from (its Node build, by a wrangler alias), and the platform's name,
logo and links in the page. What the baseline adds is everything needed to make a
copy of it somebody else's — built the way
[cirrus-baseline](https://github.com/sourceplane/cirrus-baseline) is. See
[`specs/epics/fastify-api`](specs/epics/fastify-api/README.md)
for the design, the milestones and the as-built status.

The example is Apache-2.0-licensed (vercel/vercel); its licence ships with the
app as `apps/api/LICENSE.md`.

## Instantiating a product

```bash
git clone --depth 1 --branch <baseline-tag> https://github.com/sourceplane/fastify-api
cd fastify-api
orun new --blueprint repo-blueprint.yaml --out ~/apps/acme-api --run-hooks --resume \
  --set reponame=acme-api --set productname="Acme API" \
  --set githuborg=acme-inc --set subdomain=<workers-dev-subdomain>
```

Or, once the platform's registry lists it, from the Orun console (Baselines →
`fastify-api` → Build). Two phases — `01-product` (the repository, its CI and
the whole app in one pull request, deployed to stage and prod by one
convergence, smoke-tested) and `02-docs` (the live deployment recorded) —
each landing one pull request in the new repository.
**[BOOTSTRAP.md](BOOTSTRAP.md)** is the operator guide;
[docs/phases/](docs/phases/README.md) has a page per phase.

The new repository receives the **app only** — the Worker, its tests, its CI,
its tooling, a README of its own and its operating contract — renamed
throughout to the app's name, repository and Cloudflare Worker. None of this
repository's machinery ships, and nothing that ships names it.

| What makes it a baseline | Where |
|---|---|
| The console card (inputs, secrets, programme) | `blueprint.yaml` |
| The build document (modules, phases, hooks) | `repo-blueprint.yaml` |
| This tree's identity, and the bootstrap's task contracts | `.baseline/` |
| The rename engine | `tooling/rebrand/rebrand.mjs` |
| The bootstrap's helpers (deferrals, redeploy marker, work-tree strip) | `tooling/bootstrap/` |
| The deployment-record renderer | `hooks/render-deployment-docs.sh` |
| The app's README and context pack | `.baseline/product/README.md`, `ai/context/` |
| The baseline's tests: contract, leak, offline bootstrap, end to end | `testing/`, `.github/workflows/baseline.yml` |
| Cutting a `baseline-vN` tag | `.github/workflows/tag.yml` |

## What is here (the product)

| Surface | Where |
|---|---|
| The welcome page, `GET /` — the template's route, named by the site's name, and `GET /health` — the site's name and the environment it runs as, on upstream's Fastify instance, its logger on | `apps/api/src/server.ts` |
| The Worker's entry: `await fastify.listen({ port: 3000 })` at startup, then `httpServerHandler({ port: 3000 })` | `apps/api/src/worker.ts` |
| The site's name (the rename's seam) | `apps/api/src/identity.ts` |
| Worker config (name, `nodejs_compat`, `src/worker.ts` as the entry, pino's Node build by alias, per-environment vars) | `apps/api/wrangler.jsonc` |
| Deploy contract | `apps/api/component.yaml` (`cloudflare-worker-turbo`) |
| Tests | `tests/api` (vitest: the same Fastify instance listening on Node, called over HTTP) |
| The example's licence (Apache-2.0) | `apps/api/LICENSE.md` |

## Getting started

```bash
pnpm install
pnpm typecheck
pnpm lint
pnpm test
pnpm build            # wrangler's dry run → apps/api/dist (the Worker's one bundle)
```

Run the Worker under workerd:

```bash
pnpm --filter @app/api dev            # wrangler dev, http://localhost:8787
curl http://localhost:8787/           # the welcome page
curl http://localhost:8787/health     # {"status":"ok","name":"Fastify on Workers","environment":"local"}
```

Add a route in `apps/api/src/server.ts` (`fastify.get('/hello', async () => 'hi')`),
before the instance is exported: every route must be declared before the Worker
starts, because Fastify compiles its router while it boots, and a Worker may
generate code at startup, not per request. A JSON body is parsed for you.
Read the Worker's vars from `process.env`, as `/health` does. The logger is
upstream's: each request writes a pino line to the Worker's log.

## How it maps to Vercel

| Vercel | Here |
|---|---|
| Vercel's Fastify preset runs `server.ts` and its `fastify.listen({ port: 3000 })` in a function | The same instance on workerd: `apps/api/src/worker.ts` awaits upstream's `fastify.listen({ port: 3000 })` at the top level and exports `httpServerHandler({ port: 3000 })` from `cloudflare:node` (`nodejs_compat`), which hands each request to that server |
| Fastify boots whenever `listen` runs | Fastify boots at startup, once per isolate: its router (find-my-way) compiles every route with `new Function`, which a Worker allows while it starts up (`allow_eval_during_startup`) and refuses inside a request; `pluginTimeout: 0`, because avvio's per-plugin timer cannot be set at startup |
| `logger: true`, pino writing to stdout | `logger: true`, unchanged: `wrangler.jsonc` aliases `pino` to its Node build (wrangler's bundler would take pino's browser build, which Fastify cannot load), and its lines go to the Worker's log |
| Vercel's zero-config detection of `server.ts` | `wrangler.jsonc` names `src/worker.ts` as the Worker's `main`; wrangler bundles it (Fastify and pino, about 270 KiB gzipped) |
| The page's title "Fastify on Vercel", its Vercel-hosted logo and its Vercel docs link | the site's name (`src/identity.ts`), Fastify's own logo (`fastify.dev`), and links to Cloudflare's Node.js HTTP page and Fastify's docs |
| `vc dev` · `vc deploy` | `wrangler dev` · `wrangler deploy --env <stage\|prod>` |
| Deploy on push | Orun deploys `<repo>-api-{stage,prod}` on merge to `main` and smoke-tests `/health` (`apps/api/component.yaml`) |
| "Deploy with Vercel" (clone the template) | `orun new --blueprint repo-blueprint.yaml` — a new repository, branded, deployed |

## CI

| Workflow | What it runs | Ships to an app |
|---|---|---|
| `ci.yml` | the Orun pipeline, and the only workflow an app carries: `orun plan --changed`, then one job per lane. A pull request runs the verify lanes (the Worker bundled by wrangler, type-checked and dry-deployed per environment; the tests' `quick-check` lane installs and checks the package, it does not run them), except the bootstrap's own landings (`orun/BASE-*`), where `plan` alone is the check; a merge deploys stage → prod. It plans nothing while `intent.yaml` names the placeholder workspace `ws_CHANGE_ME`, as this repository does. A manual run (Orunbase's Deploy button, or Run workflow on `main`) plans the environment and components it names under the push-to-main trigger, so they deploy as a merge deploys them | yes |
| `baseline.yml` | the baseline's own tiers: contract tests, the blueprint read by the pinned orun, the leak gate, the offline bootstrap, the app bundled by wrangler, dry-deployed, served and read route by route | no |
| `tag.yml` | cuts a `baseline-vN` tag (manual) | no |
