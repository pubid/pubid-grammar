#!/bin/bash
# P2: one conformance gate, three backends — all against the same baked
# artifacts and suites in this repo. Every runner must be green.
set -e
BASE="$(cd "$(dirname "$0")/.." && pwd)"
echo "== Ruby =="
(cd "${PARSANOL_RUBY:-$BASE/../../parsanol/parsanol-ruby}" && \
  for a in "$BASE"/artifacts/*.json; do
    name="$(basename "$a" .json)"
    if [ -f "$BASE/suites/$name.pgtest" ]; then
      bundle exec ruby -Ilib exe/parsanol pg test --json "$a" --suite "$BASE/suites" >/dev/null
    else
      bundle exec ruby -Ilib exe/parsanol pg test --json "$a" >/dev/null
    fi
  done && echo "ruby: all artifacts green")
echo "== Rust (docker, 4GB cap) =="
(cd "${PARSANOL_RS:-$BASE/../../parsanol/parsanol-rs}" && PG_ARTIFACT_DIR="$BASE/artifacts" ./docker-test.sh test -p parsanol --test pg_bindings)
echo "== TypeScript (wasm freshness) =="
(cd "${PUBID_TS:-$BASE/../pubid-ts}" && ./scripts/check-wasm-freshness.sh)
echo "== TypeScript (wasm) =="
(cd "${PUBID_TS:-$BASE/../pubid-ts}" && npm run build >/dev/null && npx tsc -p tsconfig.test.json >/dev/null && node --test dist-test/test/pg-runtime.test.js)
echo "cross-runtime gate: GREEN"
