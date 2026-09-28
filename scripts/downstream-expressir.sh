#!/bin/bash
# P6: downstream gate — expressir's full suite against the LOCAL parsanol.
# Baseline: 1829/0 (verified 2026-09-26, parsanol 1.3.53).
# RUBYOPT prepends the local parsanol lib so it shadows the installed gem.
set -e
BASE="$(cd "$(dirname "$0")/.." && pwd)"
EXPR="${EXPRESSIR_DIR:-$BASE/../../lutaml/expressir}"
PARS="${PARSANOL_RUBY:-$BASE/../../parsanol/parsanol-ruby}"
cd "$EXPR"
RUBYOPT="-I$PARS/lib" bundle exec rspec --format progress
