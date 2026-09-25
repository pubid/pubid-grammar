# 4 — Corpus and cross-runtime conformance

## Corpus format (per flavor, `corpora/<flavor>/`)

```json
{
  "id": "iso.adapted_standard.001",
  "input": "ISO/IEC 12345:2020",
  "root": "identifier",
  "tree": { "parsanol-tree/v2 node": "..." },
  "model": { "kv hash of the Ruby reference model": "..." },
  "source": "pubid-testsuite/spec/fixtures/...#L12"
}
```

- `tree` is generated from the Ruby reference (parsanol walker) — it is the
  recognition contract.
- `model` is generated from the Ruby model `to_hash` — it is the binding
  contract (each language's materializer + model must reproduce it).

## Tasks

- [ ] Corpus generator: rake task over pubid-testsuite fixtures; run per
      flavor release and on grammar change; committed here (reviewable
      diffs).
- [ ] Conformance runner: consumes corpus + artifacts + engine; runs on
      rs / ruby / wasm. Tree equality is exact; model equality via each
      language's serialization.
- [ ] Pending ledger migration: pubid-ts `conformance/pending.yaml` moves
      here. Rules preserved: every pending entry needs `reason` + `ref`;
      a pending case that passes raises the satisfied-alarm and MUST be
      unmarked.
- [ ] Cross-runtime gate: ruby runner green on CI (parsanol-ruby), wasm
      runner green (pubid-ts CI), rs runner green (parsanol-rs CI).
- [ ] Divergence protocol: a case green on engine-TS-clone but red on
      wasm is a parsanol-vs-parslet finding — file it in parsanol, fix the
      engine, never patch the corpus.

## Acceptance

- [ ] All flavors: corpus green on all three runtimes.
- [ ] Pending ledger reduced to documented reference divergences only.
