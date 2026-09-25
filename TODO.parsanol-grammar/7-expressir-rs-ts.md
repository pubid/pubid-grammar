# 7 — Expressir: the same graph, core-model style

Expressir follows the same architecture with one deliberate difference:
the **model lives in Rust** (core-model style) instead of per-language
binders (binder style), because the EXPRESS model is large,
performance-critical, and its semantics (rendering, equality, URNs) are
best implemented exactly once.

Owner: lutaml/expressir. Prerequisite: milestone 1 (parsanol-shape v2 +
wasm surface).

## Nodes

| repo | status | role |
|---|---|---|
| `lutaml/expressir` | exists | Ruby models/binding + grammar source + artifacts |
| `expressir-rs` | NEW | Rust model layer + parser binding (parsanol walker) — TODO.max-perf/9 |
| `expressir-ts` | NEW | TS bindings via wasm over expressir-rs models |

## Tasks

- [ ] **E0 housekeeping.** Move the 300+ `EXPRESS_arm_concatenated_comparison_results*.txt`
      parity dumps out of the repo root into an ignored `tmp/parity/` (or
      regenerate-on-demand); they bury the repo.
- [ ] **E1 grammar artifact.** Port the EXPRESS grammar from Parslet to
      parsanol DSL inside expressir; export the artifact (the grammar is
      large — ~10k instructions — keep the backend-hint in the artifact so
      the engine routes it to the right backend).
- [ ] **E2 expressir-rs.** Rust model layer: parse → Rust EXPRESS models
      (Repository/Schema/...), rendering, equality. Consume the grammar
      artifact. This is TODO.max-perf/9 — the builder allocation storms
      and the 100k-object RSS profile die here.
- [ ] **E3 expressir (Ruby) flip.** Ruby becomes a thin binding over
      expressir-rs (magnus/ffi): model objects cross as native Ruby
      objects backed by Rust. Full spec suite green.
- [ ] **E4 expressir-ts.** wasm bindings over expressir-rs exposing the
      model API to TS; TS conformance against the Ruby-generated corpus
      (EXPRESS fixtures → expected model JSON).
- [ ] **Cross-runtime gates.** Same corpus through ruby / rs / ts:
      identical rendered EXPRESS + identical model JSON.

## Style note

- pubid = **binder style**: models are small, idiomatic per language, and
  the Ruby models are the ecosystem standard (relaton).
- expressir = **core-model style**: one Rust model, thin bindings —
  because the model IS the product (parse ↔ render round-trips, giant
  repositories) and triple-implementing it is the cost being eliminated.

## Success graph (both families)

```
parsanol-rs ─┬─▶ parsanol-ruby ─▶ pubid gem ◀─ pubid-grammar artifacts
             ├─▶ @parsanol/wasm ─▶ pubid-ts
             └─▶ expressir-rs ─┬─▶ expressir (ruby)
                               └─▶ expressir-ts
```

Every edge: same grammar artifact + same corpus + same parsanol shape.
Success = a grammar or engine change ships once and every language
inherits it, proven by CI.
