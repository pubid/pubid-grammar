# 1 — Engine prerequisites (parsanol-rs / parsanol-ruby / @parsanol/wasm)

Everything downstream consumes these. Owner: parsanol repos.

## Tasks

- [ ] **parsanol-shape v2 spec + emitter.** Self-describing nodes (explicit
      kinds, no tag-as-items[0]), spans opt-in per node, version field in the
      serialized form. v1 stays as a legacy adapter for parslet-era consumers.
- [ ] **Capture-schema derivation.** From a Grammar, derive the tree schema:
      node kinds, capture paths, cardinalities, literal types. This drives
      binding-spec validation and (later) typed-accessor codegen.
- [ ] **wasm surface.** parse → parsanol-shape v2 as JS values; structured
      errors `{ position, expected[] }` instead of strings; `root` selection
      per parse (flavor dispatch + per-type entry points).
- [ ] **Ruby + TS materializers.** Generic walker: parsanol-shape tree +
      binding spec → language objects. Tested in the parsanol repos against
      synthetic grammars, then consumed by pubid.
- [ ] **Render service sketch (Tier 1, see 6).** model-JSON + render spec →
      string, engine-owned. Defer implementation until 5 lands the model
      definitions; spec the interface now.

## Acceptance

- [ ] Same grammar JSON + same input → identical v2 trees on rs / ruby / wasm
      (cross-runtime golden test in parsanol CI).
- [ ] Schema derivation stable and checksummed.
- [ ] Wasm parse errors carry position + expected set.
