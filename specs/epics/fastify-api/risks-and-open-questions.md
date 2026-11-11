# fastify-api — risks and open questions

## FY-A — No live bootstrap yet (OPEN)

Everything short of the platform is proven on every pull request: the card
against the build, the blueprint read by the pinned orun, the leak gate, the
offline bootstrap with the blueprint's own hooks, the app's own plan for the
01-product merge, and the produced app bundled by wrangler, dry-deployed,
served, smoke-tested and read route by route in the job tree orun stages. Not
proven: the repository created and linked, the token minted, a real `wrangler
deploy`, the smoke against workers.dev, and the routes read from the deployed
Worker.

## FY-B — Every route is declared before the Worker starts (ACCEPTED)

Fastify's router (find-my-way) compiles each route's parameter and constraint
functions with `new Function` as the route is registered. A Worker allows
code generation while it starts up (`allow_eval_during_startup`, the default
from compatibility date 2025-06-01) and refuses it inside a request, so
`src/worker.ts` awaits `fastify.listen` at the top level and the boot — every
route, every plugin, every schema — finishes before the first request. A
route registered later, from inside a handler, fails with an `EvalError`. The
boot must also fit the Worker's one-second startup limit; Fastify's took about
a millisecond. The unit tests check `worker.ts` awaits `listen` before it
exports the handler; the e2e fails on any `EvalError` in the Worker's log.

## FY-C — `pluginTimeout: 0` (ACCEPTED)

avvio wraps each plugin in a watchdog timer, and a Worker cannot set a timer
while it starts up: the call fails, avvio's `nextTick` swallows the error and
the boot never finishes. With the watchdog off, a plugin that never calls
`done` (or never resolves) hangs the startup instead of failing after ten
seconds with avvio's message: the Worker then fails to start, with
`Top-level await in module is unsettled`. The unit tests pin the setting.

## FY-D — pino from its Node build, by an alias (WATCH)

`wrangler.jsonc` aliases `pino` to `./node_modules/pino/pino.js`, because
pino's `browser` field gives wrangler's bundler a build without `pino.symbols`,
which Fastify's logger needs. The alias names a path: `pino` is a direct
dependency at the version Fastify resolves (9.14.0), so the path exists under
pnpm and there is one pino. A Fastify upgrade that takes a new pino major, or a
pino release that moves `pino.js`, breaks it. The unit tests check the alias
resolves to the same file Fastify loads; the e2e checks the bundle carries
`pino/pino.js` and not `browser.js`, and that pino's lines reach the log.

## FY-E — avvio's debug lines on every isolate start (ACCEPTED)

avvio logs its boot with `util.debuglog('avvio')`, and workerd's `debuglog`
is enabled whatever `NODE_DEBUG` says. Each isolate's boot writes about 58
`AVVIO:` lines to the Worker's log, once; requests write none. Silencing them
would mean patching avvio.

## FY-F — The bridge's reason phrase is `unknown` (ACCEPTED)

Through `httpServerHandler` the status line of every response is `HTTP/1.1
<status> unknown`; the status code and headers are Fastify's. HTTP clients
read the code, not the phrase (express-api's EX-D).

## FY-G — `orun plan --changed` and the first landing (WATCH)

`orun plan --changed` plans nothing for a push with no `before`; the first
landing relies on merging into orun's seeded initial commit, as every
baseline of this family does. Confirmed by the first live bootstrap.

## FY-H — stack-tectonic 0.19.0 (ACCEPTED)

The family's one pin (`intent.yaml` explains why 0.20.0 is not taken). The
Worker is bundled by wrangler's esbuild, so 0.20.0's linked install would
work for it; the pin is kept for one convention.

## FY-I — The welcome page's logo is hot-linked (ACCEPTED)

Upstream's page loads Fastify's logo from Vercel's framework-logo CDN. The port
loads Fastify's own mark from fastify.dev (`https://fastify.dev/favicon.svg`):
fastify/graphics ships no licence, so no copy of the logo is committed. An
owner who wants no third-party request adds a file of their own to a Static
Assets directory and points the `<img>` at it.

## FY-J — `fastify` stays at upstream's 5.6.1 (ACCEPTED)

The template pins `5.6.1`; 5.12.8 is current. The port keeps the template's
pin, so the Worker is the template's Fastify. Upgrading is a pull request that
bumps the pin, regenerates the lockfile and runs the tests and the e2e (which
catch a release that moves code generation into requests or changes avvio's
timers).

## FY-K — `fastify.inject()` does not run on workerd (ACCEPTED)

light-my-request, which `fastify.inject()` uses, builds its response by
calling `http.ServerResponse` as a function; workerd's `node:http` classes are
ES classes, so inside the Worker `inject` fails with `Class constructor
ServerResponse cannot be invoked without 'new'`. The Worker never calls it;
on Node (the tests) it works as usual.
