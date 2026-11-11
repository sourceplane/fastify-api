# fastify-api — Vercel's Fastify template on Cloudflare Workers

**The template is a Fastify server with one route that answers with a
welcome page, its logger on, run by Vercel as a Node function; the Workers
runtime serves Node's HTTP servers, so the port keeps the app as it is:
upstream's `fastify.listen({ port: 3000 })`, awaited when the Worker starts —
the one moment a Worker lets Fastify compile its router — and
`httpServerHandler` from `cloudflare:node` handing that server every request,
bundled by wrangler into one Cloudflare Worker, a `/health` route beside it,
deployed by Orun to stage and prod on every merge — and the baseline that
makes a copy of it somebody else's app in one landing.**

| | |
|---|---|
| Status | In progress — FY1 on main: the site runs on Workers |
| Upstream | [vercel/vercel `examples/fastify`](https://github.com/vercel/vercel/tree/main/examples/fastify) (Apache-2.0), at `84878e5` (2026-10-27; the example last changed in `6e28030`) |
| Reference | [express-api](https://github.com/sourceplane/express-api) — the same Node HTTP server behind `httpServerHandler`, its scaffolding, tests and bootstrap; [elysia-api](https://github.com/sourceplane/elysia-api) — the same Vercel welcome page on a framework that compiles at startup |
| Key | `FY` |

## Read in this order

1. [design.md](design.md) — the starter, how each Vercel piece maps to
   Cloudflare, what the spike proved, the repository and the build, and the
   alternatives rejected.
2. [implementation-plan.md](implementation-plan.md) — the milestones and
   what each one lands.
3. [risks-and-open-questions.md](risks-and-open-questions.md) — what is not
   proven, and what was accepted.
4. [IMPLEMENTATION-STATUS.md](IMPLEMENTATION-STATUS.md) — what shipped, and
   every departure from the upstream starter.

## Milestones

| Milestone | What it lands | Task |
|---|---|---|
| FY0 — the spec | the repository, its intent, CI, tooling and spec index; this doc set | FY-1 |
| FY1 — Fastify on Workers | the template in `apps/api`, booted at startup behind `httpServerHandler`, its tests, the README | FY-2 |
| FY2 — a baseline | the console card, the build document, the context pack and the baseline's tests | FY-3 |
