# 13 — Conformance and release pipeline

The lock that makes the whole graph trustworthy: one artifact set,
three runtimes, deterministic releases.

## Architecture principles

- **SSOT**: the Ruby reference generates corpora; every other runtime
  must reproduce them. Nothing is hand-patched to green (the
  satisfied-alarm rule: a pending case that passes MUST be unmarked).
- **SOTA**: CI gates are statistical where perf-related (median-of-N,
  25% threshold) and exact where correctness-related (trees, hashes,
  rendered strings).

## Nodes

| repo | gate |
|---|---|
| pubid-grammar | corpora, schemas, suites (the contract) |
| parsanol-ruby | reference generation + native/FFI execution |
| parsanol-rs | walker/VM/wasm execution |
| pubid / pubid-ts / pubid-rs | model-level conformance |

## Tasks

- [ ] **P1 — corpus generation** (TODO/4): rake task over the flavor
      suites + pubid-testsuite fixtures → committed triples; regenerated
      on every grammar PR (diffs reviewable).
- [ ] **P2 — cross-runtime runner.** One runner, three backends:
      tree equality exact; model-hash equality exact; rendered strings
      byte-identical (after F6 render specs).
- [ ] **P3 — pending ledger.** pubid-ts's pending.yaml moves here; every
      entry needs `reason` + `ref`; satisfied pending fails CI.
- [ ] **P4 — version triple co-release.** artifact version + schema
      version + corpus version move in one release PR; runners verify
      the triple and fail loudly on mixed states.
- [ ] **P5 — release order** (OWNER triggers; frozen until PG is
      complete): parsanol-rs → parsanol-ruby → pubid-grammar artifacts →
      pubid → expressir bundle bump.
- [ ] **P6 — downstream gates.** expressir full suite (baseline 1829/0,
      2026-09-26) and pubid spec suite run against the new releases
      BEFORE the release completes (workflow, not afterthought).
- [ ] **P7 — flavor coverage dashboard.** CI publishes: per flavor —
      compiled? tests? suite? schema? corpus? — so "all flavors" is a
      number, not a claim.

## Acceptance

- [ ] A one-line grammar change propagates: artifact release → all three
      language runtimes green on the same corpus, with zero manual
      serialization edits anywhere.
