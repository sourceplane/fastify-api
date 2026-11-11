#!/usr/bin/env bash
# TIER 2 — the API a bootstrap produces builds, deploys (dry) and serves.
#
# placement.test.sh proves the tree a bootstrap ends with is the right tree.
# This proves it WORKS, by doing to it what its own pipelines will:
#
#   1. at the 01-product landing (the commit its one pull request merges),
#      the landing's own checks — install with the lockfile the API ships,
#      render fixtures, typecheck, lint, test, build; then the same at the
#      02-docs landing. Both landings are checked in the box with
#      `orun validate` and `orun plan` alone (`checks: local`; their PR's CI
#      on an `orun/BASE-…` branch is `plan` alone, and the convergence on
#      main builds, deploys and smoke-tests the API), and a later pull
#      request of the API runs ci.yml's verify lanes, which build, type-check
#      and dry-deploy the Worker — so THIS is where the lint and the tests run
#      over a bootstrapped API: before the tag, not after a build has merged
#      it;
#   2. the stage lane's own steps, read out of `orun plan` in the product for a
#      pull request — EVERY `run:` step of the job, in order, exactly as
#      planned: the install, `verify-worker-structure` (the committed
#      `package.json` and `wrangler.jsonc`, checked BEFORE any build),
#      `wire-fixture`, the build, the typecheck and `deploy-dry-run`
#      (`wrangler deploy --dry-run --env stage`). The deploy profile has no
#      dry run, so the PR plan is the one with a deploy to rehearse. They run
#      IN THE TREE THE RUNNER STAGES for the job (testing/lib/stage-job.py),
#      with no build output in it and the dependency layout the pinned
#      composition produces: if its install step is `scope: lane`, the
#      top-level node_modules is a symlink to the source checkout's; if not,
#      the job's own install step runs inside the staged tree;
#   3. serve the built Worker with `wrangler dev --env stage` and run the
#      component's OWN `smokeCommand` against it, verbatim and then inside the
#      deploy profile's planned `smoke` step (its retry loop and all) — the
#      check the real deploy ends with — and check that it refuses the wrong
#      environment; then read every route the app promises: `/` upstream's
#      welcome page under the site's name (and HEAD), `/health` the site's own
#      name and THIS environment (which only the Worker deployed with
#      `--env stage` answers), an unknown path Fastify's JSON 404 and a
#      malformed JSON body Fastify's 400; and read the Worker's own log: ONE
#      Fastify boot for every request (it boots at startup, the only place a
#      Worker may generate code), a pino line per request (upstream's logger,
#      on pino's Node build), and no EvalError.
#
# What it cannot do is the platform's half: create the repository, mint the
# brokered Cloudflare token, deploy for real and probe workers.dev. That is a
# bootstrap against a workspace (BOOTSTRAP.md); everything short of it is here.
#
# Needs: orun, node, pnpm, python3 (+PyYAML), git, curl, setsid, and the
# network for `pnpm install` (or a warm store). A few minutes: three installs.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
# shellcheck source=lib/bootstrap.sh
source "$here/lib/bootstrap.sh"

for bin in orun node pnpm python3 git curl setsid; do
  command -v "$bin" >/dev/null || { echo "e2e.test.sh needs $bin on PATH" >&2; exit 1; }
done

scratch="$(mktemp -d)"
dev_pid=""
# wrangler dev runs under pnpm, node and workerd processes; a TERM to the
# first does not reach the rest, and waiting on it then never returns. So it is
# started as its own process group (setsid) and the whole group is stopped.
cleanup() {
  if [ -n "$dev_pid" ]; then
    kill -TERM -- "-$dev_pid" 2>/dev/null || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 -- "-$dev_pid" 2>/dev/null || break; sleep 0.5; done
    kill -KILL -- "-$dev_pid" 2>/dev/null || true
  fi
  rm -rf "$scratch"
}
trap cleanup EXIT
values="$here/fixtures/acme.json"
repo="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['reponame'])" "$values")"
sub="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['subdomain'])" "$values")"
export CI=1 WRANGLER_SEND_METRICS=false TURBO_TELEMETRY_DISABLED=1
free_port() { python3 -c "import socket;s=socket.socket();s.bind(('127.0.0.1',0));print(s.getsockname()[1]);s.close()"; }

# The landing's own checks, step for step, run here at once on the whole
# tree. A pull request in the API builds, type-checks and dry-deploys the
# Worker through ci.yml's lanes; the lint and the tests run here, and by hand
# before a push.
LANDING_CHECKS=(
  "pnpm install --frozen-lockfile"
  "pnpm run wire:fixture"
  "pnpm typecheck"
  "pnpm lint"
  "pnpm test"
  "pnpm build"
)
checks() { # DIR LOG
  local dir="$1" log="$2" cmd
  for cmd in "${LANDING_CHECKS[@]}"; do
    echo "   \$ $cmd" | tee -a "$log"
    if ! (cd "$dir" && bash -c "$cmd") >> "$log" 2>&1; then
      echo "FAIL: \`$cmd\` failed in $dir" >&2; tail -40 "$log" >&2; return 1
    fi
  done
}

echo "── the offline bootstrap (testing/lib/bootstrap.sh)"
tree="$scratch/$repo"
bootstrap_offline "$root" "$tree" "$values" "$scratch/logs" > "$scratch/bootstrap.log" 2>&1 || {
  echo "FAIL: the offline bootstrap stopped" >&2; tail -40 "$scratch/bootstrap.log" >&2; exit 1; }
s00="$(git -C "$tree" rev-parse HEAD~2)"; s01="$(git -C "$tree" rev-parse HEAD~1)"
echo "   2 phases placed and landed on orun's Initial commit"

# ── 1. each landing's own checks ───────────────────────────────────────────
echo "── 01-product's landing: install, the fixture render, typecheck, lint, test, build"
git -C "$tree" worktree add -q "$scratch/at-01" "$s01"
checks "$scratch/at-01" "$scratch/checks-01.log"
git -C "$tree" worktree remove --force "$scratch/at-01"

echo "── 02-docs's landing (the finished API), under the same checks"
checks "$tree" "$scratch/checks-api.log"

# ── 2. the stage lane, as a pull request plans it ──────────────────────────
echo "── the stage lane: every run step the PR plan gives api@stage, in a staged job tree"
(cd "$tree" && orun plan --intent intent.yaml --trigger github-pull-request --changed \
   --base "$s00" --head "$s01" --env stage --output "$scratch/plan-pr.json") > "$scratch/plan-pr.log" 2>&1 \
  || { echo "FAIL: orun plan (pull request)" >&2; tail -15 "$scratch/plan-pr.log" >&2; exit 1; }
python3 - "$scratch/plan-pr.json" "$scratch/steps" "$tree" <<'PY'
import json, pathlib, sys
import yaml
plan = json.load(open(sys.argv[1]))
out = pathlib.Path(sys.argv[2]); out.mkdir()
tree = pathlib.Path(sys.argv[3])
job = next(j for j in plan["jobs"] if j["component"] == "api" and j["environment"] == "stage")
params = yaml.safe_load((tree / "apps/api/component.yaml").read_text())["spec"]["parameters"]
order, uses = [], []
for s in job["steps"]:
    if "use" in s:
        uses.append(f"{s['id']}\t{s['use']}\t{json.dumps(s.get('with') or {})}")
        continue
    order.append(s["id"])
    (out / f"{s['id']}.sh").write_text(s.get("run") or "")
    (out / f"{s['id']}.wd").write_text(s.get("working-directory") or ".")
    if s.get("scope"):
        (out / f"{s['id']}.scope").write_text(s["scope"])
(out / "order").write_text("\n".join(order) + "\n")
(out / "uses").write_text("\n".join(uses) + "\n")
(out / "path").write_text(job.get("path") or "apps/api")
(out / "profile").write_text(job["profile"])
(out / "node").write_text(params["nodeVersion"])
(out / "pnpm").write_text(params["pnpmVersion"])
for k, v in (job.get("env") or {}).items():
    (out / "env").open("a").write(f"export {k}={json.dumps(v)}\n")
PY
order="$(tr '\n' ' ' < "$scratch/steps/order")"
echo "   $(cat "$scratch/steps/profile"): $order"
for need in install-workspace-dependencies verify-worker-structure build-worker deploy-dry-run; do
  grep -qx "$need" "$scratch/steps/order" || { echo "FAIL: the stage lane plans no $need step" >&2; exit 1; }
done
[ "$(grep -n -x verify-worker-structure "$scratch/steps/order" | cut -d: -f1)" -lt "$(grep -n -x build-worker "$scratch/steps/order" | cut -d: -f1)" ] \
  || { echo "FAIL: the structure check is planned after the build" >&2; exit 1; }
# The `use:` steps set up the runner's toolchain; here it is this machine's,
# so it must be the one the component asks for.
node_major="$(node -p 'process.versions.node.split(".")[0]')"
[ "$node_major" = "$(cat "$scratch/steps/node")" ] || { echo "FAIL: node $node_major here, the lane sets up $(cat "$scratch/steps/node")" >&2; exit 1; }
[ "$(pnpm --version)" = "$(cat "$scratch/steps/pnpm")" ] || { echo "FAIL: pnpm $(pnpm --version) here, the lane sets up $(cat "$scratch/steps/pnpm")" >&2; exit 1; }
echo "   setup-node $node_major and setup-pnpm $(pnpm --version) stand in for the lane's \`use:\` steps"

# The job's private tree, staged as orun stages it, from a source checkout
# with no build output (a CI checkout has none, so step 1's is removed rather
# than copied in) and the dependencies the pinned composition says: a
# lane-scoped install ran once in the source tree (step 1 ran the same
# command) and is linked in, or the job installs its own.
rm -rf "$tree/apps/api/.wrangler" "$tree/apps/api/dist" "$tree/tests/api/coverage"
work="$tree/.orun/runs/e2e/api.stage.verify-deploy/work"
install_scope="$(cat "$scratch/steps/install-workspace-dependencies.scope" 2>/dev/null || echo job)"
if [ "$install_scope" = lane ]; then
  python3 "$here/lib/stage-job.py" "$tree" "$work" --shared-deps
  [ -L "$work/node_modules" ] || { echo "FAIL: the staged tree's node_modules is not the lane's symlink" >&2; exit 1; }
else
  python3 "$here/lib/stage-job.py" "$tree" "$work"
  [ ! -e "$work/node_modules" ] || { echo "FAIL: the staged tree carries node_modules it should install" >&2; exit 1; }
fi
for built in apps/api/dist apps/api/.wrangler; do
  [ ! -e "$work/$built" ] || { echo "FAIL: the staged tree carries build output ($built)" >&2; exit 1; }
done
echo "   staged: $(realpath --relative-to="$tree" "$work"); install scope: $install_scope; no build output"

while IFS= read -r step; do
  [ -n "$step" ] || continue
  if [ "$step" = install-workspace-dependencies ] && [ "$install_scope" = lane ]; then
    echo "   · $step (lane-scoped: ran once in the source tree)"; continue
  fi
  echo "   ▸ $step"
  # The runner's per-job environment: the job's env (intent environment
  # `env:`) and ORUN_ENVIRONMENT; the step runs in the component's directory.
  if ! (cd "$work/$(cat "$scratch/steps/path")/$(cat "$scratch/steps/$step.wd")" && \
        { [ -f "$scratch/steps/env" ] && source "$scratch/steps/env"; true; } && \
        export ORUN_ENVIRONMENT=stage && bash -e "$scratch/steps/$step.sh") > "$scratch/$step.log" 2>&1; then
    echo "FAIL: the stage lane's $step step" >&2; tail -40 "$scratch/$step.log" >&2; exit 1
  fi
done < "$scratch/steps/order"
[ "$install_scope" = lane ] || { [ -d "$work/node_modules" ] && [ ! -L "$work/node_modules" ]; } \
  || { echo "FAIL: the job's install did not land inside its own tree" >&2; exit 1; }
grep -Eq 'env\.ENVIRONMENT \("stage"\)' "$scratch/deploy-dry-run.log" \
  || { echo "FAIL: the dry run did not resolve env.stage (ENVIRONMENT=stage)" >&2; tail -20 "$scratch/deploy-dry-run.log" >&2; exit 1; }
echo "   the dry run bundled the Worker with env.stage's ENVIRONMENT=\"stage\""
# Nothing beside the bundle: no additional modules and no static assets (the
# home page is the HTML its route returns).
if grep -Eq 'Attaching additional modules|from the assets directory' "$scratch/deploy-dry-run.log"; then
  echo "FAIL: the Worker uploads modules or assets beside its bundle" >&2; tail -20 "$scratch/deploy-dry-run.log" >&2; exit 1
fi
# The build's bundle (dist/, the package's build script) carries pino's Node
# build, which wrangler.jsonc's alias names, and not its browser build, which
# has no pino.symbols for Fastify's logger.
bundle="$work/apps/api/dist/worker.js"
[ -f "$bundle" ] || { echo "FAIL: the build wrote no dist/worker.js" >&2; exit 1; }
grep -Eq 'node_modules/pino/pino\.js' "$bundle" \
  || { echo "FAIL: the bundle does not carry pino's Node build (pino/pino.js)" >&2; exit 1; }
if grep -Eq 'node_modules/pino/browser\.js' "$bundle"; then
  echo "FAIL: the bundle carries pino's browser build" >&2; exit 1
fi
echo "   nothing beside the bundle; the bundle carries pino's Node build, not its browser build"

# ── 3. serve it, and smoke it as the deploy does ───────────────────────────
echo "── wrangler dev --env stage over the staged Worker"
port="$(free_port)"; iport="$(free_port)"
(cd "$work/apps/api" && exec setsid pnpm exec wrangler dev --config wrangler.jsonc --env stage \
   --ip 127.0.0.1 --port "$port" --inspector-port "$iport" --show-interactive-dev-session=false) \
   > "$scratch/dev.log" 2>&1 < /dev/null &
dev_pid=$!
url="http://127.0.0.1:$port"
for _ in $(seq 1 90); do
  curl -s -o /dev/null "$url/health" && break
  kill -0 "$dev_pid" 2>/dev/null || { echo "FAIL: wrangler dev exited" >&2; tail -30 "$scratch/dev.log" >&2; exit 1; }
  sleep 1
done
curl -s -o /dev/null "$url/health" || { echo "FAIL: wrangler dev never answered" >&2; tail -30 "$scratch/dev.log" >&2; exit 1; }

smoke="$(python3 -c "import yaml,sys;print(yaml.safe_load(open(sys.argv[1]))['spec']['parameters']['smokeCommand'])" "$tree/apps/api/component.yaml")"
echo "   ▸ the component's own smokeCommand, verbatim, DEPLOYED_URL=$url ORUN_ENVIRONMENT=stage"
DEPLOYED_URL="$url" ORUN_ENVIRONMENT=stage bash -c "$smoke" || { echo "FAIL: the deploy's smoke refused the API" >&2; exit 1; }
if DEPLOYED_URL="$url" ORUN_ENVIRONMENT=prod bash -c "$smoke" 2>/dev/null; then
  echo "FAIL: the smoke passed prod's check against the stage Worker — it does not read the environment" >&2; exit 1
fi
echo "   ▸ …and it refuses the stage Worker as prod"

(cd "$tree" && orun plan --intent intent.yaml --trigger github-push-main --changed \
   --base "$s00" --head "$s01" --env stage --output "$scratch/plan-push.json") > "$scratch/plan-push.log" 2>&1 \
  || { echo "FAIL: orun plan (push to main)" >&2; tail -15 "$scratch/plan-push.log" >&2; exit 1; }
python3 - "$scratch/plan-push.json" "$scratch/smoke-step.sh" <<'PY'
import json, sys
plan = json.load(open(sys.argv[1]))
job = next(j for j in plan["jobs"] if j["component"] == "api" and j["environment"] == "stage")
assert job["profile"].endswith(".deploy"), job["profile"]
step = next(s for s in job["steps"] if s["id"] == "smoke")
open(sys.argv[2], "w").write(step["run"])
PY
echo "   ▸ the deploy profile's planned smoke step (its retry loop around the same command)"
(DEPLOYED_URL="$url" ORUN_ENVIRONMENT=stage bash "$scratch/smoke-step.sh") > "$scratch/smoke-step.log" 2>&1 \
  || { echo "FAIL: the planned smoke step refused the API" >&2; tail -20 "$scratch/smoke-step.log" >&2; exit 1; }

echo "   ▸ every route the app promises, and the Worker's own log"
python3 - "$url" "$values" "$scratch/dev.log" <<'PY'
import html, json, re, sys, urllib.error, urllib.request
base, values, devlog = sys.argv[1], json.load(open(sys.argv[2])), sys.argv[3]
name = values["productname"]
problems = []
def bad(m): problems.append(m)
requests = 0
def call(path, method="GET", body=None, ctype=None):
    global requests
    requests += 1
    req = urllib.request.Request(base + path, method=method, data=body)
    if ctype:
        req.add_header("content-type", ctype)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, r.headers, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.headers, e.read()

# / — upstream's welcome page, named by the site's name (escaped in the HTML;
# compared decoded), with Fastify's logo and links in place of Vercel's.
s, h, body = call("/")
page = body.decode()
if s != 200 or h.get("content-type") != "text/html":
    bad(f"/ answered {s} {h.get('content-type')}")
title = re.search(r"<title>(.*?)</title>", page, re.S)
if not title or html.unescape(title.group(1)) != name:
    bad(f"/ is titled {title and title.group(1)!r}, not {name!r}")
if f"<h1>Welcome to {name}</h1>" not in html.unescape(page):
    bad("/ does not welcome visitors to the site by its name")
for need in ('src="https://fastify.dev/favicon.svg"', 'href="https://fastify.dev"',
             'href="https://developers.cloudflare.com/workers/runtime-apis/nodejs/http/"',
             "A fast and low overhead web framework running on Cloudflare Workers"):
    if need not in page:
        bad(f"/ lost {need}")
if re.search(r"vercel", page, re.I):
    bad("/ still names Vercel")
s, h, body = call("/", "HEAD")
if s != 200 or body or int(h.get("content-length") or 0) != len(page.encode()):
    bad(f"HEAD / answered {s} with {len(body)} bytes, content-length {h.get('content-length')}")

# /health — the deploy's contract: the site's name and THIS environment,
# which only the Worker running env.stage's vars (in process.env) answers.
s, h, body = call("/health")
try:
    health = json.loads(body)
except ValueError:
    health = None
    bad(f"/health is not JSON: {body[:80]!r}")
if health is not None:
    if s != 200 or health.get("status") != "ok":
        bad(f"/health answered {s} {health}")
    if health.get("name") != name:
        bad(f"/health names the site {health.get('name')!r}, not {name!r}")
    if health.get("environment") != "stage":
        bad(f"/health reports environment {health.get('environment')!r}, not 'stage'")

# An unknown path: Fastify's own JSON 404 — the router, compiled at boot,
# answering under workerd. A JSON body is parsed before routing; a malformed
# one is Fastify's 400.
s, h, body = call("/no-such-route")
if s != 404 or json.loads(body or b"{}") != {"message": "Route GET:/no-such-route not found", "error": "Not Found", "statusCode": 404}:
    bad(f"/no-such-route answered {s} {body[:100]!r}, want Fastify's 404")
s, h, body = call("/", "POST", b'{"a":1}', "application/json")
if s != 404 or b"Route POST:/ not found" not in body:
    bad(f"POST / answered {s} {body[:100]!r}, want Fastify's 404")
s, h, body = call("/", "POST", b'{"a":', "application/json")
if s != 400 or json.loads(body or b"{}").get("code") != "FST_ERR_CTP_INVALID_JSON_BODY":
    bad(f"a malformed JSON body answered {s} {body[:100]!r}, want Fastify's 400")

# The Worker's log. Fastify booted once (avvio's root plugin ran once) for all
# of these requests: at startup, not per request. Upstream's logger wrote a
# pino line for each request. No code generation was refused.
for _ in range(5):
    call("/health")
log = re.sub(r"\x1b\[[0-9;]*m", "", open(devlog, encoding="utf-8", errors="replace").read())
boots = log.count("AVVIO: exec root")
if boots != 1:
    bad(f"Fastify booted {boots} times for {requests} requests, want once (at startup)")
pino = len(re.findall(r'"msg":"incoming request"', log))
if pino < requests:
    bad(f"pino logged {pino} incoming requests for {requests} requests")
if "EvalError" in log or "Code generation from strings disallowed" in log:
    bad("the Worker refused code generation: something compiled per request")

if problems:
    for p in problems:
        print(f"  ✕ {p}", file=sys.stderr)
    sys.exit(1)
print(f"   / the welcome page (and HEAD); /health {json.dumps(health)}; Fastify's 404 and 400; "
      f"one boot for {requests} requests, {pino} pino request lines, no EvalError")
PY

echo "e2e.test.sh: ok"
