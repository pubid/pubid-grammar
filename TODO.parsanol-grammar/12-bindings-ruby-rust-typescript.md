# 12 — Bindings: Ruby, Rust, TypeScript

The model layer: how a checksummed artifact + capture schema becomes
idiomatic objects in each language — with one implementation of every
deterministic rule and a deliberate home for the non-deterministic
residue.

## Architecture principles

- **SSOT**: models are MATERIALIZED from the binding-requirements schema
  (PN 5); no hand-written serializers anywhere (lutaml-model mappings on
  Ruby; schema-driven hashing on TS/Rust). The `bindings` section of the
  artifact is the single statement of capture→field truth.
- **OCP**: the parse→shape→bindings→model pipeline is a chain of
  registered stages; per-language ingestion hooks (Tier 3) extend the
  model end without touching grammar or engine.
- **OOP**: each language exposes an Identifier base with flavor
  subclasses generated from the schema; special-casing lives in
  polymorphic ingestion methods, not conditionals scattered in parsers.
- **SOTA**: definition-driven runtimes (schema → objects) instead of
  generated code files where possible; codegen only as an optional
  accelerator (`pg schema --ts`).

## The pipeline (identical shape in all languages)

    artifact (checksum verified)
      → native parse (entry)                    [parsanol-rs | wasm | native ext]
      → bindings application                    [captures → preprocess → casts → paths]
      → model materialization                   [schema-driven]
      → ingestion hooks                         [Tier 3: the non-deterministic residue]

## Nodes

| language | nodes | status |
|---|---|---|
| Ruby | pubid monorepo (models = lutaml-model), parsanol-ruby `PG::Lutaml` | models exist; parsers migrate per flavor |
| TypeScript | pubid-ts + @parsanol/wasm | new |
| Rust | pubid-rs + parsanol::pg | new |

## Tasks

### Ruby (binder style — pubid monorepo)

- [ ] **R1 — flavor parser swap.** Each flavor's parslet parser is
      replaced by the artifact parse (`PG::Lutaml.register` per flavor);
      the builder consumes bound captures. Order: the 33 ported flavors,
      each gated by the flavor's spec suite.
- [ ] **R2 — ingestion hooks.** The non-deterministic residue (CSA
      normalization, IEC IEV shorthand, AMCA whitespace rules) moves to
      explicit pre-parse normalizer objects at the model-ingestion end —
      declared in the flavor, never in PG.
- [ ] **R3 — relaton compatibility.** Model JSON output byte-identical
      to today's (the corpus model-hashes are the gate).

### TypeScript (pubid-ts)

- [ ] **T1 — runtime materialization.** A TS runtime that reads the
      schema (from the artifact) and materializes typed objects from
      `WasmParser.fromArtifact(...).parse` + bindings (C9).
- [ ] **T2 — schema→TS types.** `parsanol pg schema --ts` codegen as the
      optional accelerator (types for IDEs; runtime stays
      schema-driven).
- [ ] **T3 — suite/corpus runner.** The `*.pgtest` + corpora run under
      vitest through wasm; green = TS conformance.

### Rust (pubid-rs)

- [ ] **RS1 — models from schema.** serde structs (or a schema-driven
      value model v1) materialized from bindings application in Rust
      (11/C7).
- [ ] **RS2 — suite/corpus runner.** Same gate as T3 on the native
      engine.

## Acceptance

- [ ] One artifact set; the SAME suite + corpora green on ruby, TS, rs.
- [ ] Rendered identifier strings byte-identical across the three.
- [ ] Zero hand-written serialization; zero identifier-string surgery
      outside Tier 1/ingestion hooks (CI lint).
