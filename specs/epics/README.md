# Epics

Orun-style work programs. Each epic is a folder carrying `epic.yaml` (the
declaration the platform reads: slug, key prefix, milestones with exit
criteria and task keys) beside its doc set. The pull request that adds the
folder is the adoption; the merge creates the epic in the workspace.

| Epic | Cluster | Status | What it is |
|------|---------|--------|------------|
| [`fastify-api/`](./fastify-api/) | **FY** | ✅ Shipped (`baseline-v1`); live bootstrap pending | Vercel's Fastify on Vercel template, its instance and route kept, booted at the Worker's startup behind the runtime's Node.js HTTP server support in one Cloudflare Worker — and an Orun baseline that instantiates it in one landing (FY2) |

As-built ≠ intent: what shipped lives in each epic's `IMPLEMENTATION-STATUS.md`.
