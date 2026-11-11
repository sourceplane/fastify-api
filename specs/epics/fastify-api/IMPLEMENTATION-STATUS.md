# fastify-api — implementation status

| Milestone | State | Landed |
|---|---|---|
| FY0 — the spec | ✅ | FY-1 |
| FY1 — Fastify on Workers | ✅ | FY-2 |
| FY2 — a baseline | planned | FY-3 |

## Departures from the upstream template

Everything not listed here is the template as it is upstream at `84878e5`.

| # | What | Why |
|---|---|---|
| 1 | The app lives in `apps/api` of a pnpm workspace (`@app/api`); upstream's `package.json`, `package-lock.json`, `.gitignore`, `tsconfig.json` and README are replaced by the workspace's; `server.ts` is `src/server.ts`; `dev` is `wrangler dev`, and `build` (wrangler's dry run), `deploy`, `typecheck` and `lint` are added | The workspace's shape (express-api's) |
| 2 | `fastify: 5.6.1` kept; `pino: 9.14.0` added as a direct dependency; `wrangler` beside `@types/node` and `typescript` | The template's Fastify (risk FY-J); the alias needs pino's path (FY-D); the deploy tool |
| 3 | `src/server.ts`: `Fastify({ logger: true, pluginTimeout: 0 })` (upstream `{ logger: true }`) | avvio's watchdog timer cannot be set while a Worker starts up (design §3.5, risk FY-C) |
| 4 | `src/server.ts`: upstream's last line, `fastify.listen({ port: 3000 })`, moves to `src/worker.ts`, awaited at the top level, followed by `export default httpServerHandler({ port: 3000 })` from `cloudflare:node`; `server.ts` exports the instance | The Worker boots Fastify at startup, the one place it may generate code (design §3.3–3.6, risk FY-B); the tests listen on a port of their own |
| 5 | `src/server.ts`: `<title>` and the heading read `SITE_NAME` (`"Fastify on Workers"`; upstream's are "Fastify on Vercel" and "Welcome to Fastify"), HTML-escaped; the tagline says "running on Cloudflare Workers" (upstream "running on Vercel"); the logo is Fastify's own (`fastify.dev/favicon.svg`, upstream Vercel's framework-logo CDN); the "Vercel docs" link is "Cloudflare docs" (Cloudflare's Node.js HTTP page) | One rename seam; the page no longer names a platform it does not run on (risk FY-I) |
| 6 | `GET /health` added: `{"status":"ok","name":SITE_NAME,"environment":process.env.ENVIRONMENT}` | The deploy's smoke and the bootstrap's probes read it (express-api's contract) |
| 7 | `src/identity.ts` added: `export const SITE_NAME = "Fastify on Workers"`; `src/cloudflare-node.d.ts` declares `cloudflare:node` | The rename's one seam; the one Workers API the app imports, typed without retyping Node's globals |
| 8 | `tsconfig.json` extends the workspace's base (ES2022, strict, Node types) in place of upstream's `module: NodeNext` | The workspace's config; ES2022 modules for the top-level await |
| 9 | `wrangler.jsonc` (`<repo>-api`, `main: src/worker.ts`, `nodejs_compat`, `alias: { pino: ./node_modules/pino/pino.js }`, no assets, `env.{dev,stage,prod}` vars) and `component.yaml` (`cloudflare-worker-turbo`, a smoke over `/health`, the live preview) | The Worker's config and the deploy contract replace Vercel's (design §2–3); pino's browser build cannot load (risk FY-D) |
| 10 | `apps/api/LICENSE.md` is vercel/vercel's Apache-2.0 licence, with its copyright line ("Copyright 2017 Vercel, Inc."); upstream's `package.json` names none and the repository ships no NOTICE; `src/server.ts` carries the modification notice | The example ships under its repository's licence; the product carries it |
| 11 | Tests: `tests/api/src/app.test.ts` (vitest): the same instance listening on Node, every route called over HTTP, and the boot contract checked | The template ships none |
