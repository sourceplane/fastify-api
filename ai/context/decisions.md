# fastify-api — decisions

The choices that shape this repository, one line each, with where the full
reasoning lives. Superseded decisions stay listed, marked, so the history
reads in order.

| # | Decision | Why | Source |
|---|---|---|---|
| 1 | The template's Fastify instance, its route unchanged but for the platform's name, logo and links, started by upstream's `fastify.listen({ port: 3000 })` behind `httpServerHandler` from `cloudflare:node`, in a plain Worker (`cloudflare-worker-turbo`) | The Workers runtime serves Node's HTTP servers; no rewrite into another framework, and the template's file stays the app module | `specs/epics/fastify-api/design.md` |
| 2 | `fastify.listen` awaited at the top level of `src/worker.ts`: Fastify boots at startup, once per isolate | Fastify's router compiles routes with `new Function`, which a Worker allows at startup and refuses in a request | design.md §3, risk FY-B |
| 3 | `pluginTimeout: 0` | avvio's per-plugin watchdog is a timer, which a Worker cannot set while it starts up; with it on, the boot never finishes | design.md §3.5, risk FY-C |
| 4 | `logger: true` kept, pino aliased to its Node build in `wrangler.jsonc`, pino a direct dependency at Fastify's version | wrangler's bundler would take pino's browser build, which has no `pino.symbols`; the Node build writes its lines to the Worker's log | design.md §3.1–3.2, risk FY-D |
| 5 | Path A (`node:http` + `httpServerHandler`), not a `fastify.inject()` bridge | light-my-request cannot build its response on workerd | design.md §3.7, risk FY-K |
| 6 | `wrangler.jsonc` is committed, `main: src/worker.ts`, `nodejs_compat`, no assets, and the package's build is wrangler's dry run | One config a deploy reads; wrangler bundles the app itself, so there is no framework build to order before the deploy | `apps/api/wrangler.jsonc` |
| 7 | `GET /health` beside the template's route, reading `process.env.ENVIRONMENT`, and one name seam (`apps/api/src/identity.ts`) the welcome page reads | The deploy smoke and the bootstrap's probes read `/health`; the rename writes the name in one place | IMPLEMENTATION-STATUS |
| 8 | The tests serve the same instance on Node and call it over HTTP, and check the boot contract (`pluginTimeout`, the pino alias, `worker.ts`'s await) | The module that ships is the module tested; the e2e serves the bundled Worker under workerd and reads its log | `tests/api/src/app.test.ts` |
| 9 | One landing (`01-product`) then the record (`02-docs`) | A landing has a fixed cost; the plan, not the phases, carries deploy order (cirrus-baseline since baseline-v22) | `repo-blueprint.yaml` |
| 10 | `ci.yml` plans nothing while `intent.yaml` names `ws_CHANGE_ME` | A bootstrap cannot set a repository variable | hono-api's design |
| 11 | stack-tectonic 0.19.0 | The family's one pin (risk FY-H) | risks-and-open-questions.md |
| 12 | `subdomain` is read from the Cloudflare connection, never asked; the console asks for no domain | It belongs to the account; a domain is an owner's step after the bootstrap | `blueprint.yaml` |
