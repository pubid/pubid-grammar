# 11 — The grammar compiler/interpreter (Ruby, Rust, wasm)

The engine layer: who compiles, who executes, and how the layers stay
open for extension.

## Architecture principles

- **SSOT — one compiler.** Ruby (`Parsanol::PG`) is the ONLY `.pg`
  compiler. Rust/wasm consume the checksummed artifact
  (`parsanol::pg`, `WasmParser.fromArtifact`) and never parse `.pg`.
  A second compiler would be a second language; don't.
- **OCP — registries, not switches.** Lints, preprocessing ops, and
  importers are registered strategies. Adding behavior = registering a
  class; the compile pipeline is unchanged.
- **OOP — the IR is a hierarchy.** PG's Node grows into a typed IR with
  a visitor: lint rules, table collection, checksum emission, and the
  future self-hosting parser all walk the same tree.
- **SOTA**: compiled-artifact interchange (XGrammar/llguidance),
  2025 PEG error recovery (labels + ranked multi-error reporting),
  tree-sitter-grade authoring feedback (LSP, 10).

## Nodes

| repo | role |
|---|---|
| parsanol-ruby | the compiler, CLI, artifact tooling (reference) |
| parsanol-rs | portable engines (walker, VM), artifact runtime, wasm |
| parsanol-ruby native/FFI | the same rs engines behind Ruby |

## Tasks

### Compiler (Ruby — reference implementation)

- [x] **C1 — IR + visitor.** DONE 2026-09-24 (pg-language branch): Document IR + visitor.rb. Replace ad-hoc walks with a visitor over
      the node set; port lint/table-collect/emission onto it (OCP
      prerequisite for everything below).
- [x] **C2 — lint registry.** DONE 2026-09-24: PG::Lints registered strategies (LeftRecursion, Alternatives), pure errors/warnings. Each lint (left recursion, prefix
      shadowing, empty shadowing, duplicates, order warnings) is a
      registered strategy with severity; flavors can add project lints.
- [x] **C3 — preprocess op registry.** DONE 2026-09-25: PG::Preprocess registry, table_lookup first; mirrored in Rust (bindings.rs) with the op check. `table_lookup` becomes the first
      registered op; new ops (G6 policy) register without touching the
      compiler or Bindings.
- [ ] **C4 — error recovery.** Implement ranked multi-error reporting
      (2025 PEG recovery work): parse failures report all errors with
      labels, not just the deepest. Feeds F7's wire format.
- [ ] **C5 — CLI hardening.** `--json` machine output, `--trace`
      (cause tree on failure), batch mode (`pg test grammars/`) used by
      CI as the drift alarm for all flavors.
- [x] **C6 — self-hosting (engine side).** DONE 2026-09-26 (a92a1fb): the pg artifact parses pg.pg; see F10 for the open phase-2 slice.

### Artifact runtime (Rust + wasm — consumers)

- [x] **C7 — bindings application in Rust.** Port Bindings
      (capture collection → preprocess ops → casts → paths) onto
      `parsanol::pg`; preprocess ops are a Rust trait registry mirroring
      C3. Unblocks pubid-rs end to end.
      DONE 2026-09-26 (parsanol-rs 7fb2262, branch pg-artifact-wasm):
      `pg::bindings` with Ruby-parity fixture replay; envelopes now
      embed table rows (checksum-covered, filesystem-free engines).
- [x] **C8 — schema + suite parity in Rust.** `Schema::from_artifact`
      and suite running against the Rust runtime; CI runs every
      `*.pgtest` on rs AND ruby (the G5 equality gate).
      DONE 2026-09-26 (8dd13b2): `pg::schema` (from_artifact +
      TypeScript emission, camelCase and namespaced-entry semantics
      mirrored in Ruby 7830e69) and `pg::suite` (parse_shape emits the
      parsanol-tree/v2 leaf contract; run_tests/run_test_list). The
      Rust engine replays the Ruby-generated fixture inputs and must
      reproduce both shape and bound hash. Per-flavor *.pgtest CI sweep
      remains open (the G5 runner wiring).
- [x] **C9 — wasm full runtime.** fromArtifact gains bindings +
      schema + suite (browser-side testing without any server); the
      TS binding (12) builds on exactly this surface.
      DONE 2026-09-26 (8dd13b2): `PgArtifactJs` — checksum-verified
      load, entryNames, parseShape, applyBindings, parseAndBind,
      runTests, schema, schemaTypescript.
- [ ] **C10 — shape validation at load** (F8): `shape` checked against
      the engine's supported contract; mismatch = loud failure.
- [ ] **C11 — error wire format** (F7): the flat error struct exposed
      by walker, VM, wasm, C ABI; expected-set dedup identical across
      engines.
- [ ] **C12 — constrained-decoding export (optional, SOTA).** Artifact
      → XGrammar/llguidance grammar export for LLM structured
      generation. Only after C1-C11; it is a consumer of the same SSOT.

### Interpreter parity (existing engines)

- [ ] **C13 — artifact grammars on the VM.** Every flavor artifact runs
      walker AND VM with tree equality in CI (BYTE_DISPATCH + packrat
      paths already in place; the gate makes it contractual).

## Live gate: found by the self-description corpus (2026-09-26)

- [x] **C-BUG1 — RESOLVED 2026-09-26 (grammar-level).** pg.pg's
      `element` could match empty (`[rep_prefix pq] [pred / postfixed]`
      with everything skippable) — a zero-width bomb the Ruby
      interpreter absorbed but the native engine chased into unbounded
      memory. Fix: `element = pq (rep_prefix pq [...] / pred /
      postfixed)` — requires consumption; all pg.pg tests pass
      NATIVELY. Root rs zero-width hardening remains an optional
      follow-up; the C8 gate caught the divergence exactly as designed.

- [ ] Adding a lint, a preprocess op, or an importer touches ZERO
      existing pipeline code (registration only).
- [ ] `pg test grammars/` green on ruby, rs, and wasm from one artifact
      set; schemas byte-identical where generated on both runtimes.
- [ ] No `.pg` parser exists outside parsanol-ruby (verified by grep
      gate in CI).
