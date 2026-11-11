#!/usr/bin/env bash
# hooks/render-deployment-docs.sh runs in the build box, which has python3 but
# not PyYAML: a hook that imports yaml stops 02-docs with exit 1 while the app
# is live. This runs the hook on a scaffolded app under a python3 with no
# third-party packages (and again under the system python3 when it has
# PyYAML), and checks the record names both Workers, reads the workspace from
# intent.yaml when none is passed, and renders the README section. The probes
# go to the network (workers.dev answers any name, a 404 for a Worker that is
# not there), so the record is checked for a status on each row, not for one
# status.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

python3 -m venv --without-pip "$work/bare"
if "$work/bare/bin/python3" -c 'import yaml' 2>/dev/null; then
  echo "render.test.sh: the bare python3 still imports yaml — cannot test" >&2; exit 1
fi

app="$work/app"; mkdir -p "$app/.github/workflows" "$app/.rebrand"
printf '{"reponame":"acme-tools","subdomain":"acme"}\n' > "$app/.rebrand/values.json"
printf '# acme-tools\n\nAn API.\n' > "$app/README.md"
printf 'jobs:\n  lane:\n    steps:\n      - with:\n          version: v2.78.4\n' > "$app/.github/workflows/ci.yml"
cat > "$app/intent.yaml" <<'YAML'
execution:
  state:
    # the app's own workspace
    workspace: ws_TEST0000  # linked
environments:
  stage:
    env:
      BASE_DOMAIN: acme-tools.example.com
YAML

fail=0
for py in "$work/bare/bin" ""; do
  label="${py:+without PyYAML}"; label="${label:-with the system python3}"
  [ -n "$py" ] || python3 -c 'import yaml' 2>/dev/null || { echo "   (skipped: system python3 has no PyYAML)"; continue; }
  rm -rf "$app/ai"
  if ! (cd "$app" && PATH="${py:+$py:}$PATH" bash "$here/hooks/render-deployment-docs.sh" . "" "$here" >/dev/null 2>"$work/err"); then
    echo "  ✕ $label: the hook failed"; sed 's/^/      /' "$work/err"; fail=1; continue
  fi
  rec="$app/ai/context/deployment.md"
  for env in stage prod; do
    grep -q "https://acme-tools-api-${env}.acme.workers.dev/health" "$rec" \
      || { echo "  ✕ $label: the record does not probe the $env Worker's /health"; fail=1; }
  done
  grep -q 'ws_TEST0000' "$rec" || { echo "  ✕ $label: the workspace was not read from intent.yaml"; fail=1; }
  [ "$(grep -cE '^\| (health|home page) \((stage|prod)\) \| https://[^ ]+ \| (LIVE \([0-9]+\)|unreachable|answering [0-9]+)' "$rec")" = 4 ] \
    || { echo "  ✕ $label: the record does not give each of the 4 probes a status"; fail=1; }
  grep -q 'v2.78.4' "$rec" || { echo "  ✕ $label: the CI lane pin was not read"; fail=1; }
  [ -f "$app/ai/context/operations.md" ] || { echo "  ✕ $label: operations.md was not healed"; fail=1; }
  grep -q '<!-- 02-docs:begin -->' "$app/README.md" || { echo "  ✕ $label: README section missing"; fail=1; }
  [ "$fail" = 0 ] && echo "   $label: record rendered, workspace read from intent.yaml"
done
[ "$fail" = 0 ] || exit 1
echo "render.test.sh: ok"
