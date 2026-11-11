# fastify-api — implementation plan

Three milestones, one task each, each landed as one pull request.

## FY0 — the spec (FY-1)

The repository is born with express-api's frame — `intent.yaml` (dev
verify-only, stage, prod after stage; the placeholder workspace
`ws_CHANGE_ME`, so CI plans nothing until it is linked), `ci.yml` byte for
byte turso-starter's (as express-api carries it), the shared TypeScript and
ESLint configuration, the wrangler renderer, the pnpm workspace and turbo
pipeline, and the spec index — and this doc set and the three task
contracts land on it.

## FY1 — Fastify on Workers (FY-2)

- `apps/api/src/server.ts` is upstream's `server.ts`: its instance with
  `logger: true` and `pluginTimeout: 0` (design §3.5), its route with the
  title and heading read from `SITE_NAME` (HTML-escaped), its Vercel logo and
  link now Fastify's and Cloudflare's, `/health` beside it reading
  `process.env.ENVIRONMENT`, and the instance exported;
  `apps/api/src/worker.ts` awaits upstream's `fastify.listen({ port: 3000 })`
  at the top level and exports `httpServerHandler({ port: 3000 })`;
  `apps/api/src/identity.ts` holds `SITE_NAME`; `apps/api/LICENSE.md` is
  vercel/vercel's Apache-2.0 licence.
- `fastify` stays at upstream's 5.6.1, `pino` 9.14.0 beside it;
  `apps/api/wrangler.jsonc` (`src/worker.ts` as `main`, `nodejs_compat`, the
  pino alias, no assets, per-environment vars) and `component.yaml`
  (`cloudflare-worker-turbo`) with a smoke over `/health`.
- `tests/api`: vitest serving the same instance on Node and calling `/`,
  `HEAD /`, a 404, a malformed JSON body, `/health` with and without an
  environment over HTTP, and checking the Worker's boot contract.
- The README: run, test, deploy; how each Vercel piece maps.

Done when typecheck, lint, test and build are green, and `wrangler dev`
answers every route.

## FY2 — a baseline (FY-3)

express-api's machinery on this tree: the card, the build document (one
landing, `01-product`, then the record, `02-docs`), `.baseline/` (identity,
the product's README, task contracts), the rename engine (the `SITE_NAME`
seam alone), the bootstrap helpers, the deployment-record renderer (probing
`/health` and `/`, and its render test with no PyYAML), the phase pages, the
context pack, and the baseline's tests — with the end-to-end tier replaying
the stage lane in a staged job tree (no build output in it), checking the dry
run is one bundle with no assets and pino's Node build in it, and reading
every route and the Worker's own log from the staged Worker under `wrangler
dev`. Done when every Baseline CI tier is green; tagged `baseline-v1`.
