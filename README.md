# fastify-api

Vercel's [Fastify on Vercel](https://github.com/vercel/vercel/tree/main/examples/fastify)
template — a [Fastify](https://fastify.dev/) server whose one route, `GET /`,
answers with the template's welcome page, its logger on — running as one
**Cloudflare Worker**: upstream's `fastify.listen({ port: 3000 })`, and the
Workers runtime's Node.js HTTP server support (`httpServerHandler` from
`cloudflare:node`) hands that server every request. Bundled by wrangler, deployed by
[Orun](https://github.com/sourceplane/orun) to stage and prod on every merge.
Packaging it as an Orun baseline is the next milestone (FY2).

The template's code is the code. What the port adds is the Worker's entry
(`fastify.listen`, awaited at startup, behind `httpServerHandler`), the Worker's
config, the monorepo wrapper, a test package, the deploy contract and a
`/health` route the deploy smoke-tests; what it changes is Fastify's
`pluginTimeout` (off: a Worker cannot set a timer while it starts up), where
pino comes from (its Node build, by a wrangler alias), and the platform's name,
logo and links in the page. See
[`specs/epics/fastify-api`](specs/epics/fastify-api/README.md)
for the design, the milestones and the as-built status.

The example is Apache-2.0-licensed (vercel/vercel); its licence ships with the
app as `apps/api/LICENSE.md`.

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
