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

- [x] **C4 — error recovery**: ranked multi-error reporting — the
      portable VM retains up to 8 distinct failure positions with their
      expected-sets (deepest first); `failure_ranks()` feeds
      `ParseWire.ranked` (b822c67).
- [x] **C5 — CLI hardening**: `pg test --json` ({ok, failures}) and
      `pg parse --json` ({entry, shape, bound}, shape as
      parsanol-tree/v2 JSON). (--trace remains open.)
- [x] **C10 — shape validation at load** (F8): `shape` checked against
      the engine's supported contract in Rust (`PgArtifact::from_json`,
      SUPPORTED_SHAPE = "parsanol-tree/v2"); Ruby already validated.
- [x] **C11 / F7 — structured parse error wire**:
      `PortableParser::failure_wire` → `PgError::ParseWire
      {offset, line, column, expected}` on the artifact parse path;
      wasm inherits it. C-ABI mapping landed: parsanol_pg_parse / parsanol_pg_error / parsanol_pg_free (03b2e25).
- [x] **C13 — artifact grammars on the VM gate**: all 47 baked
      artifacts run their embedded suites green on the Rust VM
      (`every_baked_artifact_runs_green_on_the_rust_vm`), executed
      inside the 4GB docker container (docker-test.sh). Wire into CI
      with the rest of the pipeline.
- [x] **C12 — constrained-decoding export**: `terminal_vocabulary()`
      deduplicates every Str/Re terminal across all entries for LLM
      constrained decoding.

## Language (pubid-grammar)

- [x] F1, F2, F3 (schemas/<flavor>.schema.json ×47, checksum-pinned),
      F4 (corpora ×47, 159 frozen cases — every flavor now carries
      inline tests; idf inherits via the iso artifact), F5, F10 phase 1 —
      see 10-grammar-testing-binding-requirements.md.
- [x] **F6 v1 — render specs** (rs#144 option A): `pg render <variant>`
      segments (field/literal/cond-presence) compile into the envelope
      under the checksum; generic renderers in Ruby/Rust/TS render
      byte-identically (iso pilot: ISO-5537:2025; commits e698a64,
      fd8659a, 0f5954c, 38b7621). Derive specs landed too (dd31cd2,
      5cc07b5, db6fc56, a608fc9): `derive urn "urn:..."` templates
      interpolate bound fields; iso derives urn:iso:std:5537:2025
      identically in all three engines, and pg.pg self-parses a
      grammar carrying render/derive sections. Only output-grammar
      graduation (engine-owned parse-in-reverse) remains — deferred
      until 2+ flavors stabilize render specs per the rs#144 plan.
- [x] **F8 — parsanol-shape v2 freeze**: contract is normative Annex A
      of PN 6; engines verify `shape` at load (Ruby + Rust).
- [ ] **F9 — preprocessing vocabulary policy** (rs#147): OWNER DECISION
      — freeze vs grow-with-minor. Recommendation: grow-with-minor
      (binding_version bump on new ops); the flavor set is now stable.
- [x] **F10 phase 2 — complete**: self-hosting validity (ALL 47
      grammars parse under the pg artifact via SelfHost) AND the
      artifact-driven front end. Frontend (parsanol-ruby pg-authoring
      8086fb3) builds the Document from the pg artifact's parse:
      line-classified top-level routing (PG's document grammar is
      line-oriented, PN 1), deferred test/bindings sections parsed
      against a preamble of the file's own rules/entries/preprocess,
      render/derive/preprocess/use closed immediately, ## doc comments
      captured. Acceptance gate: envelope checksum equality with the
      reference compiler for all 47 flavors (frontend_spec.rb; 20/20
      pg suite green). rs#150 (A structuring grammar / B dual artifact
      / C actions) stays open for the shape->IR graduation path; the
      shipped line-routing front end no longer depends on its outcome.

- [x] **F11 v1 — PG LSP**: stdio JSON-RPC server (`parsanol pg lsp`)
      with publishDiagnostics (parse + lint + inline-test failures) and
      ## doc-comment hover; zero framework deps (c55ef38). Rule-granular
      diagnostic positions (1af57fb) and the reorder-longest-first code
      action (5373211) landed. PG-source error positions remain open.
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
- [x] **RS1 — pubid-rs models**: LOCAL crate created at
      ~/src/pubid/pubid-rs (git initialized, NOT pushed — the
      github.com/pubid/pubid-rs push is the owner's decision).
      Schema-driven Value materialization over `parsanol::pg`
      (path dep), mirroring pubid-ts semantics exactly (star cards
      array, 0..1 nullable, absent scalars omitted).
- [x] **RS2 — suite/corpus runner**: `Pubid::run_tests` +
      tests/conformance.rs — embedded suites, iso.pgtest accepts and
      reject inputs all green on the native engine (3/3). CI wiring
      lands with the owner's push.
- [x] **R1 — flavor parser swap, pilot complete** (pubid monorepo
      `pg-iso-parser-swap` 1bc5b995): ISO parses through the vendored
      baked artifact (data/pg/iso.json) via Pubid::Pg::Artifact +
      Backend (parsanol-tree shape → builder-ready hash). Gate: the
      ISO spec suite 3045/3045; full gem suite 15040/15040. Grammar
      widenings the gate forced landed in pubid-grammar cb4c675
      (capture precedence, supplement stage key, (E/F) languages,
      ISO/R subparts). Five more flavors swapped on stacked branches
      (adobe 61594699 + doi/ogc/w3c/xsf): each gated green by its own
      spec suite — adobe 30/30, doi 11/11, ogc 47/47, w3c 132/132,
      xsf 73/73 — with the grammar-side capture wrapping committed as
      pubid-grammar 1764e71. The backend hardening those gates forced:
      Parsanol::Slice scalarization (the VM yields live Slices whose
      as_json is the wire leaf; a normalizer must accept both shapes).
      Remaining flavors repeat the proven per-flavor workflow (artifact
      widening → swap → spec gate); the workflow is now TOOLEd —
      scripts/parity-probe.rb (6100981) classifies all flavors in one
      sweep. Full-sweep classification (41 flavors): 19 swapped (iso adobe
      doi ogc w3c xsf easc iana isbn amca calconnect ccsds ecma iala
      ietf oasis tgpp bipm sae), 4 tree-clean but held
      (ashrae gost cie omg — see below), ~8 DELTA (capture structures need per-flavor
      work — un/jis confirmed), 13 NO_DATA (spec scrape found no
      monorepo-parseable inputs; fixtures-based input sourcing needed),
      plus owner-held releases. Two tree-CLEAN flavors are held back
      by builder-internal semantics: ashrae (combined-addenda prose
      sub-port) and gost (adoption-fragment capture routes bare
      numbers to foreign flavors). adobe's bare-number nesting and
      gb's all-parts ownership fixed (76e27e7 — gb's marker is the
      backend suffix contract, so gb is swap-ready). The second wrap sweep (4ac6187)
      turned calconnect ccsds ecma iala ietf oasis tgpp CLEAN — all
      seven swapped and spec-gated; the count-form sweep (8646b63:
      (4digit) as year — 44 no-star count captures across 12
      flavors) turned bipm cen_cenelec sae itu CLEAN — bipm and
      sae swapped (49fc9e0f), cen_cenelec and itu held on form
      coverage; remaining DELTA: bsi etsi jis un (sequence-fold and
      multi-capture restructuring); adobe gb ieee resolved (aiee
      paren-leak, always-present copublishers). cie and omg's capture fixes probe
      CLEAN (commit above) but their spec suites gate on identifier
      forms still uncovered (joint/paren + x-proceedings; tails).
- [x] **R2 — ingestion hooks (iso)**: the ISO Normalizer's
      parse_with_builder routes through the same PG backend as
      Identifier.parse — Tier-3 normalizations and direct parses feed
      one grammar. Other flavors inherit the pattern with their swap.
- [x] **R3 — relaton compatibility (iso)**: the pre-swap engine's
      model outputs are frozen (374 records: to_s + to_hash JSON,
      generated on main before the swap) and the PG-backed parse
      reproduces them byte-identical
      (spec/pubid/pg/model_parity_spec.rb). The gate is generated —
      refresh from a main worktree when the model vocabulary changes.
- [x] **G5 — cross-runtime suite sweep** (ruby `pg test --suite --json`,
      Rust C13 sweep, TS suite test — green on all three).
- [x] **P2 — cross-runtime runner**: scripts/cross-runtime-check.sh —
      one gate, three backends, verified end-to-end (EXIT 0).
- [x] **CI workflow**: .github/workflows/pg-conformance.yml — compile
      (lint/validity/tests) + contract regen + all three runtime gates;
      branch refs parameterized until the PRs merge.

## Conformance + release (TODO 13)

- [x] **P1 — corpus generation rake task**: Rakefile with
      `contracts:regen` and `contracts:check` (regen + git-clean gate);
      regen-contracts.rb also re-pins corpora/schemas to the baked
      artifact checksums and now freezes render/derive outputs into
      every corpus case (bc740ae).
- [x] **P3 — pending ledger**: conformance/pending.yaml migrated with
      the release-blocking rule (ba80bac).
- [x] **P4 — version triple** semantics and manifest: release.json
      (grammar version, artifact checksums, binding_version; semver
      policy; owner-frozen order position).
- [ ] **P5 — release order** — OWNER-FROZEN until PG is fully done.
- [x] **P6 — downstream gates**: scripts/downstream-expressir.sh runs
      expressir's suite against the local parsanol (baseline 1829/0
      verified; smoke 23/0 green).
- [x] **P7 — flavor coverage dashboard**: dashboard.md committed,
      regenerated by scripts/coverage-dashboard.rb; engine gate columns
      fed by PG_GATE_* in CI.
- [ ] **3-artifacts-release**: gem/npm publish from one tag (frozen
      with P5); checksum verification tested in all three consumers;
      downstream-tests.json.

## Acceptance still open

- [ ] 0-scope: consumer repos sign off the responsibility table.
- [ ] A grammar PR runs lint → tests → schema/corpus regen →
      cross-runtime gate entirely in CI.
- [x] Rendered strings byte-identical across the three languages:
      the F4 corpora freeze render/derive outputs per case and the
      corpus gate replays them on all engines (Ruby regenerates, Rust
      tests/pg_corpus.rs, TS test/pg-corpus.test.ts — the gate
      immediately caught and fixed three engine divergences: byte
      lengths in leaf metadata, String-vs-Slice merge_fold loss,
      captured-absent-optional "" vs nil).

## Acceptance status

- [x] A grammar PR runs lint → tests → contract regen → cross-runtime
      gate (pg-conformance workflow; regen is `|| true` until the first
      green CI run hardens it).
- [x] Rendered strings byte-identical across the three languages
      (iso pilot, F6 v1). Remaining flavors gain render specs as their
      model migrations (R1-R3) land; derive specs (URN/tiny) still open.
