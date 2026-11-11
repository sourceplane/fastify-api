# fastify-api — open risks

What is not yet proven or not yet decided. The full write-up of every risk,
including the accepted and resolved ones, is
`specs/epics/fastify-api/risks-and-open-questions.md`; this page lists only
what is still live, so it should be short.

| ID | Risk | State | What closes it |
|---|---|---|---|
| FY-A | No live bootstrap yet: the repository created and linked, the deploy token minted, a real `wrangler deploy` of the bundle, the smoke and the probes against workers.dev, and the routes read from the deployed Worker are all unproven | OPEN | One bootstrap from a tag against a workspace |
| FY-D | pino comes from its Node build by a wrangler alias naming `./node_modules/pino/pino.js`; a Fastify upgrade to a new pino major, or a pino release that moves the file, breaks it | WATCH | The unit test (the alias resolves to the pino Fastify loads) and the e2e (the bundle carries `pino/pino.js`, its lines reach the log) on every change |
| FY-G | `orun plan --changed` plans nothing for a push with no `before`; the first landing relies on merging into orun's seeded initial commit | WATCH | Confirmed by the first live bootstrap |

Accepted, and worth knowing before you change them: FY-B (every route is
declared before the Worker starts: Fastify compiles its router at boot, and a
Worker refuses code generation inside a request), FY-C (`pluginTimeout: 0`: a
plugin that never finishes hangs the Worker's startup), FY-E (avvio writes about
58 debug lines once per isolate start), FY-F (the bridge's reason phrase is
`unknown`), FY-H (stack-tectonic 0.19.0), FY-I (the logo is hot-linked from
fastify.dev, as upstream hot-links Vercel's), FY-J (`fastify` stays at the
template's 5.6.1), FY-K (`fastify.inject()` does not run inside the Worker).
