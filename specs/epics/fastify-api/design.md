# fastify-api — design

## 1. The starter

vercel/vercel `examples/fastify` at `84878e5` (the example last changed in
`6e28030`) is a Fastify project of six files: `server.ts` (one
`Fastify({ logger: true })` instance, one `fastify.get('/', …)` returning an
inline HTML welcome page with `reply.type('text/html')` — a title, a heading,
a tagline, two links and Fastify's logo hot-linked from Vercel's
framework-logo CDN — and, last, `fastify.listen({ port: 3000 })`), a
`package.json` whose one dependency is `fastify` pinned to `5.6.1` beside
`@types/node` and `typescript`, a `package-lock.json`, a `tsconfig.json`, a
`.gitignore` and a README. Vercel's Fastify preset runs `server.ts` in a Node
function and routes requests to the port it listens on.

## 2. How each Vercel piece maps

| Vercel | Here |
|---|---|
| A Node function running `server.ts`, its `fastify.listen({ port: 3000 })` | workerd: `apps/api/src/worker.ts` awaits upstream's `fastify.listen({ port: 3000 })` at the top level and exports `httpServerHandler({ port: 3000 })` from `cloudflare:node` (`nodejs_compat`), which hands each request to the server listening there |
| Fastify booting whenever `listen` runs | Fastify booting at the Worker's startup, once per isolate (§3) |
| `logger: true`, pino writing to stdout | `logger: true`; `wrangler.jsonc` aliases `pino` to its Node build, and its lines are the Worker's log |
| Zero-config detection of `server.ts` | `apps/api/wrangler.jsonc`, committed: the Worker's name, `nodejs_compat`, `src/worker.ts` as `main` (wrangler bundles it), the pino alias, per-environment `ENVIRONMENT` vars |
| `fastify: 5.6.1` | `fastify: 5.6.1`, upstream's own pin, kept; `pino: 9.14.0` beside it, the version Fastify resolves, so the alias's path exists |
| The page's title "Fastify on Vercel", its Vercel-hosted logo and its Vercel docs link | the site's name (`src/identity.ts`), Fastify's own logo (`https://fastify.dev/favicon.svg`), Cloudflare's Node.js HTTP page and Fastify's docs |
| Deploy on push | `apps/api/component.yaml` (`cloudflare-worker-turbo`): build, dry run on pull requests; build, deploy and a smoke over `/health` on merge |

## 3. What the spike proved

In a scratch copy, before any of the repository: fastify 5.6.1 (with pino
9.14.0, avvio 9.3.1, find-my-way 9.10.0), wrangler 4.151.0,
`compatibility_date` 2026-10-01 and `nodejs_compat`, served by `wrangler dev`
and probed with real requests. Each step, in order:

1. **Upstream as it is fails at load.** `fastify.listen({ port: 3000 })` at
   module scope behind `httpServerHandler({ port: 3000 })`, `logger: true`:
   `Cannot destructure property 'serializersSym' of 'pino.symbols' as it is
   undefined`, in Fastify's `logger-pino.js`. pino's `package.json` names a
   `browser` build, wrangler's bundler takes it, and that build has no
   `symbols`.
2. **pino's Node build loads.** A wrangler `alias` of `pino` to
   `pino/pino.js` gets past the load, but every request is a 500 (`Http
   server with port 3000 not found`): `listen` never settles.
3. **Booting in a request is refused.** Starting `listen` (or `ready()`, for a
   `fastify.inject()` bridge) inside the first request fails with `EvalError:
   Code generation from strings disallowed for this context`, in find-my-way's
   `HandlerStorage._compileCreateParamsObject`: Fastify's router compiles
   every route's parameter and constraint functions with `new Function` as the
   routes are registered, which happens during the boot.
4. **Startup allows code generation.** A probe Worker: `new Function` in the
   global scope returns its value; the same call in a request throws the
   `EvalError`. Cloudflare's docs: `allow_eval_during_startup` is the default
   from compatibility date 2025-06-01, so production behaves as `wrangler dev`
   does.
5. **avvio's watchdog is what stalls a startup boot.** `await app.ready()` at
   the top level leaves the module's top-level await unsettled, with the
   logger on or off. `queueMicrotask` and `process.nextTick` both run during
   startup; what does not is avvio's per-plugin timeout, a `setTimeout` it
   sets around each plugin, whose failure in the global scope is swallowed
   inside a `nextTick`. With `pluginTimeout: 0` avvio sets no timer, and
   `await app.ready()` at startup returns.
6. **Path A, shipped.** `pluginTimeout: 0`, pino aliased, `logger: true`, and
   upstream's own `await fastify.listen({ port: 3000 })` at the top level
   (it settles at startup in about a millisecond), then `httpServerHandler`:
   `/` 200 `text/html`; an unknown path Fastify's JSON 404 (`Route GET:/missing
   not found`); a JSON body parsed and echoed; a malformed one Fastify's 400
   (`FST_ERR_CTP_INVALID_JSON_BODY`); request and reply headers through; `HEAD
   /` 200 with a `Content-Length`; a boot counter read three times answers 1
   (built once per isolate); pino's `incoming request` and `request completed`
   lines in the Worker's log.
7. **Path B, rejected.** The same startup boot with a fetch →
   `fastify.inject()` bridge (light-my-request): every request 500s with
   `TypeError: Class constructor ServerResponse cannot be invoked without
   'new'` — light-my-request extends `http.ServerResponse` the ES5 way
   (`ServerResponse.call(this, …)`), and workerd's `node:http` classes are ES
   classes.
8. **avvio's debug log is always on.** `util.debuglog('avvio').enabled` is
   true under workerd whether `NODE_DEBUG` is unset or empty, so the boot
   writes about 58 `AVVIO:` lines once per isolate (risk FY-E).

The dry run of the shipped Worker is 1,549 KiB, 270 KiB gzipped, with
`ENVIRONMENT` its only binding.

## 4. The repository

express-api's, which is hono-api's: a pnpm workspace (`apps/api`, `tests/api`,
`tooling/*`), turbo, the shared TypeScript and ESLint configuration,
`intent.yaml` (dev verify-only, stage, prod after stage, the placeholder
workspace `ws_CHANGE_ME`, the API as the live-preview component), `ci.yml`
byte for byte turso-starter's as express-api carries it, and the baseline's
machinery (`blueprint.yaml`, `repo-blueprint.yaml`, `.baseline/`,
`tooling/rebrand`, `tooling/bootstrap`, `hooks/`, `testing/`). The app's build
is wrangler's own dry run with `--outdir dist`, so turbo caches the bundle and
the lane's typecheck and dry run follow it.

Upstream's `server.ts` keeps its instance and its route; its last line,
`fastify.listen`, moves to `src/worker.ts`, so the module exports the
instance. The tests import that module and listen on a free port on Node,
calling every route over HTTP — the template's behaviour independent of the
runtime — and check the three things that let it boot in a Worker
(`pluginTimeout` 0, the pino alias pointing at the copy Fastify loads, and
`worker.ts` awaiting `listen` before it exports the handler). The end-to-end
tier serves the bundle under workerd with `wrangler dev --env stage` and reads
the Worker's own log: one boot for every request, a pino line per request,
and no `EvalError`.

## 5. Alternatives rejected

- **A fetch → `fastify.inject()` bridge (Path B).** It needs no `node:http`
  server, but light-my-request cannot build its response object on workerd
  (§3.7), and it would boot Fastify the same way.
- **Booting on the first request.** Fastify's router generates code as it
  registers routes; a Worker refuses that inside a request (§3.3).
- **`logger: false`, or pino's browser build passed in.** The alias keeps
  upstream's logger and its JSON lines as they are, and the lines reach the
  Worker's log; turning it off would change the template for no gain.
- **Patching find-my-way to build its functions without `new Function`.** A
  fork of Fastify's router to maintain, when booting at startup needs none.
- **Patching avvio's debug log quiet.** About 58 lines per isolate start is
  noise, not a fault; a patched dependency is a cost on every upgrade.
- **Rewriting the route in another framework (hono-api's shape).** The
  starter is about Fastify: its instance, its logger and its router are the
  point.
