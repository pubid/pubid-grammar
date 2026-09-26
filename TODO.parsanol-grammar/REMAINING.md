# REMAINING — the reconciled work ledger (2026-09-26)

Single source of truth for what is left. Items marked DONE here are
checked in their topic files with commit references. Ordered by the
dependency chain: engine correctness → language features → consumers
→ conformance → release (P5 stays owner-frozen).

## Engine (parsanol-ruby / parsanol-rs)

CONTAINMENT RULE: every cargo test run goes through docker-test.sh
(4GB container cap). 2026-09-26 incident: an unbounded VM loop on bsi
reached 24GB on the host. Root causes fixed: invalid grammars
(unbounded repetition over an empty-matchable body) are now rejected
by a compile-time lint; the Rust VM breaks on non-progressing
repetition iterations as defense in depth.

- [ ] **C4 — error recovery**: ranked multi-error reporting.
- [x] **C5 — CLI hardening**: `pg test --json` ({ok, failures}) and
      `pg parse --json` ({entry, shape, bound}, shape as
      parsanol-tree/v2 JSON). (--trace remains open.)
- [x] **C10 — shape validation at load** (F8): `shape` checked against
      the engine's supported contract in Rust (`PgArtifact::from_json`,
      SUPPORTED_SHAPE = "parsanol-tree/v2"); Ruby already validated.
- [x] **C11 / F7 — structured parse error wire**:
      `PortableParser::failure_wire` → `PgError::ParseWire
      {offset, line, column, expected}` on the artifact parse path;
      wasm inherits it. (C-ABI mapping remains open.)
- [x] **C13 — artifact grammars on the VM gate**: all 47 baked
      artifacts run their embedded suites green on the Rust VM
      (`every_baked_artifact_runs_green_on_the_rust_vm`), executed
      inside the 4GB docker container (docker-test.sh). Wire into CI
      with the rest of the pipeline.
- [ ] **C12 (optional) — constrained-decoding export.**

## Language (pubid-grammar)

- [x] F1, F2, F3 (schemas/<flavor>.schema.json ×47, checksum-pinned),
      F4 (corpora/<flavor>/corpus.json from the reference; ~20 early
      flavors await inline-test seeds or P1's rake), F5, F10 phase 1 —
      see 10-grammar-testing-binding-requirements.md.
- [ ] **F6 — render/derive specs** (rs#144, G1): ordered segments +
      derive data in the artifact, generic renderer per language.
      Needs its design note before implementation.
- [x] **F8 — parsanol-shape v2 freeze**: contract is normative Annex A
      of PN 6; engines verify `shape` at load (Ruby + Rust).
- [ ] **F9 — preprocessing vocabulary policy** (rs#147): OWNER DECISION
      — freeze vs grow-with-minor. Recommendation: grow-with-minor
      (binding_version bump on new ops); the flavor set is now stable.
- [ ] **F10 phase 2 — full self-hosting**: the Ruby compiler consumes
      the pg artifact as its own front end.
- [ ] **F11 — PG LSP**: diagnostics, hover, reorder code action.
- [x] **F12 — specification completion**: PN 6 (capture schema format,
      docs 82ec498) and PN 7 (conformance protocol, same commit).
- [ ] **L1–L8** (8-lml-model-gaps.md): lutaml-model/lml-side work;
      L2 done, L3 done with C11.

## Consumers (TODO 12)

- [x] Ruby: parser runtime + bindings + schema + CLI (parsanol-ruby).
- [x] Rust: C7/C8/C9 (parsanol-rs pg-artifact-wasm branch).
- [x] TypeScript: T1/T3 (pubid-ts 798c9cc).
- [x] **T2 — schema→TS emission** into pubid-ts
      (scripts/emit-schema-types.mjs through the wasm runtime;
      src/pg/generated/*.d.ts, 60619c6). Full `pg schema --ts` CLI
      parity remains open.
- [ ] **RS1 — pubid-rs models**: the pubid-rs REPO DOES NOT EXIST yet.
      OWNER DECISION: create `pubid/pubid-rs` (crate name, org). v1
      scope is small — a schema-driven serde Value materializer over
      `parsanol::pg` (path dep) mirroring pubid-ts materialize().
- [ ] **RS2 — pubid-rs suite/corpus runner**: the runner exists in
      `parsanol::pg` (run_tests/run_test_list); what remains is the
      pubid-rs crate wiring + CI. Blocked on RS1's repo decision.
- [ ] **R1 — flavor parser swap** (pubid monorepo): per flavor, gated
      by the flavor's spec suite. Pilot candidate: iso.
- [ ] **R2 — ingestion hooks**: Tier-3 normalizers move to the model
      ingestion end, declared per flavor.
- [ ] **R3 — relaton compatibility**: model JSON byte-identical
      (corpus model-hashes gate).
- [x] **G5 — cross-runtime suite sweep** (ruby `pg test --suite --json`,
      Rust C13 sweep, TS suite test — iso.pgtest green on all three).
      Formal CI workflow wiring remains open.

## Conformance + release (TODO 13)

- [ ] **P1 — corpus generation rake task** (the generator now exists;
      wire as rake + CI).
- [ ] **P2 — cross-runtime runner**: one runner, three backends.
- [ ] **P3 — pending ledger** migration from pubid-ts.
- [ ] **P4 — version triple co-release** mechanics.
- [ ] **P5 — release order** — OWNER-FROZEN until PG is fully done.
- [ ] **P6 — downstream gates** (expressir 1829/0 baseline).
- [ ] **P7 — flavor coverage dashboard**.
- [ ] **3-artifacts-release**: gem/npm publish from one tag (frozen
      with P5); checksum verification tested in all three consumers;
      downstream-tests.json.

## Acceptance still open

- [ ] 0-scope: consumer repos sign off the responsibility table.
- [ ] A grammar PR runs lint → tests → schema/corpus regen →
      cross-runtime gate entirely in CI.
- [ ] Rendered strings byte-identical across the three languages.
