# 0 — Scope, repositories, and the string-manipulation boundary

## Decision: pubid-grammar exists because the grammar is a CONTRACT

The pubid monorepo (`pubid/pubid`, single gem, 22+ flavors) owns **models**:
identifier classes, update/create semantics, renderers, data YAMLs
(`update_codes`, `series`, `stages`), the conformance ledger, and — since the
parsanol port — the parsanol DSL grammar *sources* live here too, because
they are computed Ruby (TYPED_STAGES discovery, dash variants, longest-first
orderings).

This repo owns the **exported contract**: baked grammar JSON, capture
schemas, corpora, binding specs. Sources may start here and move to the
monorepo later; the artifact remains here regardless. Consumers
(pubid-ruby, pubid-ts, pubid-rs) read artifacts only — never re-transcribe
rules.

## Repo responsibilities after the split

| repo | keeps | stops owning |
|---|---|---|
| `pubid/pubid` | lutaml-model definitions, models, renderers, data YAMLs, conformance ledger, downstream tests | rule trees as executable parse code |
| `pubid/pubid-grammar` (this) | grammar DSL sources, artifacts, schemas, grammar corpora, binding specs | — |
| `pubid/pubid-ts` | TS models, toHuman/toUrn, conformance runner | engine.ts, src/flavors/*/grammar.ts (deleted — wasm + artifacts replace them) |
| `pubid/pubid-testsuite` | fixtures, model-level goldens | — |
| `parsanol/*` | engine, parsanol shape, materializers, wasm | — |

## The string-manipulation boundary (three tiers)

The rule: **outputs must be identical across languages, therefore the
specification of string manipulation is never language-specific.** Only the
object semantics around it are.

### Tier 1 — data-extractable composition (NOT language-specific)
KV keys, XML element/attribute names, URN templates, render templates
(conditional composition over typed fields). Expressed as data: lutaml-model
mappings (Ruby) + extracted definition JSON (TS) + eventually parsanol render
specs / output grammars (engine-owned "render" — parse in reverse). Drift
here is how Ruby `to_s` and TS `toHuman` diverge; data makes divergence
impossible.

### Tier 2 — data-driven normalization (NOT language-specific)
Stage codes, series tables, update codes — already YAML in the pubid
monorepo (`data/*/`). Extracted definition JSON ships to TS with the
artifacts.

### Tier 3 — genuinely language-specific residue
Object lifecycle (`update!` in place), API ergonomics (method names, keyword
args), Enumerable vs iterators, host integration (relaton). These operate on
typed fields via Tier 1 — after extraction the model layer never does raw
string surgery on identifier text.

## Acceptance for this milestone

- [ ] All consumer repos agree with this responsibility table.
- [ ] Binding-spec format drafted (5-model-definitions has the model side).
