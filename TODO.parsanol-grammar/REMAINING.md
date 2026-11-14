# REMAINING — the reconciled work ledger (synced 2026-11-12)

Single source of truth for what is left. Items marked DONE here are
checked in their topic files with commit references. Ordered by the
dependency chain: engine correctness → language features → consumers
→ conformance → release (P5 stays owner-frozen).

Reality snapshot 2026-11-12: 48 flavors (aiee, ire, nesc ride the ieee
grammar fleet) plus two PFS dev grammars (`doi_pfs`, `etsi_pfs` —
generated definitions, dev-alias flavors in pubid; not routed), 415
committed corpus cases + the PFS golden/etsi corpora, every flavor on
edition-2 typed bindings (see dashboard.md, regenerated this sync).
The grammar CI job runs on ubuntu-24.04 with ruby 3.4.8 — bakes and
contract regens stay on that toolchain because the artifact stamps
embed the Ruby version; the compiler pin is `PARSANOL_VERSION` in
`.github/workflows/parg-conformance.yml` (1.3.126) and the
cross-engine wasm gate is pinned to `@parsanol/wasm` 0.10.46
(rs 0.20.14 — the phantom-array harvest of parsanol-ts#66, ruby
ancestor parsanol-ruby#399, is fixed there; 0.10.32 predates the fix).

## Landed 2026-11-12 (this sync's waves)

- [x] **ISO historic ballot faces decode-to-modern** (owner ruling,
      Option B): TYPE-first ballot supplement faces
      (`[P|F]?DAM [N] BASE [:year][/Amd.N]`) parse and decode onto the
      stored-twin identities — stage from token, implied number 1 at
      build time (identity-bearing), base kept whole; `Am1` accepted
      as an `Amd 1` alias; ballot-letters-vs-stored-round drift rows
      spec-pinned. 12 anchors raise→parse; 213,414-stored-face probe
      0 diff lines. (56833fe; grammar branches `ballot_supplement_identifier`,
      `ballot_space_supplement_identifier`, `typed_stages_ballots`.)
- [x] **IEC legacy DAM-family decode-to-modern** (same ruling):
      `IEC/FDAM 60038-1` ≡ `IEC FDAM 60038-1` ≡ `IEC 60038-1/FDAM1` —
      the designation moves whole onto a concrete InternationalStandard,
      supplement number defaults to 1; #693's part→supplement-number
      move deleted. CDCOR all-caps alias, PDAM/FPDAM typed stages,
      copublisher captured as a top-level scalar (the wasm
      phantom-array workaround, see parsanol-ts#66).
      (c13db43, ecb32f0, 77c05e8, c711eb6; follow-up 0793420 adds the
      `[language]` slot to the on-base supplement branch so
      `ISO/IEC 19772:2009(en)/DAM1:2019` parses.)
- [x] **NIST default-series plain-number branch** (pubid#711): bare
      `800-90B` and publisher-led `NIST 800-90B` parse and default to
      series SP / publisher NIST — `800-90B == NIST SP 800-90B`, MR
      face = the stored DOI surface. 43,109-input replay, 0
      regressions; contracts re-pinned. (7307c69, 22564c2.)
- [x] **CI wasm gate pin 0.10.46** (b76be8d): the cross-engine gate
      was pinned to 0.10.32 (rs 0.19.19), predating the phantom-array
      fix — valid rules reded. Upstream finding filed as
      parsanol/parsanol-ts#66 with the version matrix
      (0.10.30/0.10.32 carry it; 0.10.46 fixed).
- [x] **PFS — the PubID Format Schema, phase 1 + the etsi bracket**
      (pubid#706, owner-adopted): the compiler (`lib/pubid/grammar/pfs/`,
      `scripts/pfs`) — strict YAML load, fail-closed validation
      (pfs:1, reserved tokens, ambiguity rejection citing the rule),
      edition-2 generation, bake integration, example verification —
      with `definitions/doi.pfs` (02fedd4, b8cab61) and
      `definitions/etsi.pfs` (e3d8578) as the two compiled definitions.
      Parity: doi 55/55 byte-identical vs the coded flavor; etsi
      accept 24,718/24,718 with to_hash/to_pubid_urn parity 18,945/
      24,718 (rows carrying the three undeclarable constructs pinned
      per-construct in pubid's `spec/pubid/etsi_pfs/parity_spec.rb` —
      progress turns the pins red). Dev-alias flavors only; cutover is
      a separate decision.
- [x] **PFS — the module library + the two proof ports** (pubid#706 s4):
      `definitions/modules/*.pfsmod` bound via `modules: {module:, version:,
      parameters:}` — v1 set iso.inner/iec.inner/en.overlay/
      national.prefix/supplements.core/edition.core; modules declare
      IDENTITY (wrapper-with-adopted + base_module + adopted_field) and
      hooks; fail-closed versioning; collision citations name both
      claimants. Proofs: `calconnect_pfs` 400-example BYTE-PARITY over
      the whole corpus (the acceptance test — forces the
      sub-numbering extension, `fields.<n>.sub_numbering`);
      `cen_pfs` 55 rows absorbed byte-identically, 134 pinned as the
      unabsorbed ledger (the measured tier call). Also landed:
      presence-guard rendering, `date:` calendar binding,
      `urn.official` segments, type `web:`, publisher_prefixes —
      additive; doi_pfs regenerates byte-identically.
      (pubid-grammar#112 + pubid#714; phase-3 compiler needs named by
      cen_pfs: multi-type emission, typed-stage serialization,
      wrapper-class synthesis, adopted-base coded hooks,
      publisher-type defaults, fused URN segments.)
- [x] **PFS cen_pfs full absorption — the six declared-emission
      features** (pubid-grammar#121, 2026-11-14): multi-type declared
      emission (type `tokens:`, builder token dispatch, the token-free
      default class); draft-stage serialization (`stages:` spellings +
      URN codes, the field `map:`/`render:` value maps, the compact
      "stage" => "pren" class hook); cen's wrapper shapes (string
      ordinals, the per-wrapper optional ordinal, wrapper-owned date
      columns, the slash-vs-plus run dispatch, the consolidated bundle
      and the fragment wrapper); the adopted-base dispatch
      (`adopted: {field:, hook: coded}` — the section-4 escape hatch,
      two explicit call points, the hook vendored in pubid); publisher
      -type defaults (`publisher_default:`); fused URN segments
      (`pub_group`, `adopted_mr`, `stage_code`, the wrapper chains and
      the plus marker); plus the template language's required group.
      cen_pfs absorbs 189/189 corpus rows byte-identically on all five
      identity surfaces, zero rows pinned (the pubid flip rides the
      same issue); doi_pfs/calconnect_pfs/etsi_pfs regenerate
      byte-identically (the regression net), contracts re-pinned at
      1.3.126, the wasm gate green at 0.10.46.
- [ ] **PFS v2 — the six compiler gaps** (the etsi bracket's pinned
      backlog): collection bindings; conditional render segments;
      supplement wrapper types; int-kind URN cores (+ the generator's
      `core.map(&:to_sym)` load crash on non-empty cores); URN-generator
      declaration surface (namespace-only today); MR-slug `mr_*` hooks.
      Named segments (owner directive 2026-11-13): PFS grammar fragments and
      generated rules must carry SEMANTIC names (`number`, `publisher`,
      `copublisher`, ...) so the grammar is self-understandable to the
      bodies reading it — anonymous/combinator-soup names are a v2
      validation rejection (the generator names every segment; user
      fragments with unnamed captures are rejected citing the rule).
Each is the precise blocker for full byte-parity on etsi rows
      (3,772 collection-part / 1,833 ed.N / 168 supplement-wrapper
      rows) and for the tier-B extension catalog's conditional-segment
      item. Phase 3 also owes: the module library (iso.inner/iec.inner/
      en.overlay/national.prefix), the cen_cenelec NSB proof, the
      CalConnect port (sub-numbering extension), and the remaining
      tier-A ports — in flight at sync time.

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
- [x] **C5 — CLI hardening**: `parg test --json` ({ok, failures}) and
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
      identically in all three engines, and pg.parg self-parses a
      grammar carrying render/derive sections. Only output-grammar
      graduation (engine-owned parse-in-reverse) remains — deferred
      until 2+ flavors stabilize render specs per the rs#144 plan.
- [x] **F8 — parsanol-shape v2 freeze**: contract is normative Annex A
      of PN 6; engines verify `shape` at load (Ruby + Rust).
- [x] **F9 — preprocessing vocabulary policy** (rs#147): RESOLVED
      grow-with-minor (owner decision, 2026-11-11): declarative
      preprocess vocabulary v1.1 — `const_map`, `default_when_absent`,
      `rename` beside `table_lookup`, all sharing the uniform
      `{op, table, from, to}` step wire shape, engine-executed on both
      engines. Shipped in the parsanol 0.20.14 train (crates 0.20.14,
      rubygems 1.3.138, pypi 0.1.25, npm parsanol 0.10.46 +
      @parsanol/wasm 0.20.14). Binding version: v1-only artifacts stay
      byte-identical at 1; artifacts using post-v1 ops declare 2;
      engines refuse >= 3 at load.
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
      src/pg/generated/*.d.ts, 60619c6). Full `parg schema --ts` CLI
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
      sweep. Full-sweep classification (41 flavors): 28 swapped (iso adobe
      astm api asme ansi jcgm plateau cen_cenelec gb un; astm via the
      adjunct designation/EA-suffix shape fix), originally 25 (iso adobe
      api asme ansi jcgm plateau cen_cenelec gb un; api via the R2
      MPMP normalize_input hook), originally 25 (iso adobe
      ansi jcgm plateau cen_cenelec gb un; probe entry resolution
      collapsed NO_DATA — api asme astm oiml iec evs nist are now
      DELTA-classified with sampled diffs), originally 22 (iso adobe
      cen_cenelec gb un — cen_cenelec via the R2 normalize_input
      ingestion hook and longest-canonical-name resolution),
      originally 19 (iso adobe
      gb un; additions through b4bb6789 and the un merge opt-out),
      originally 19 (iso adobe
      doi ogc w3c xsf easc iana isbn amca calconnect ccsds ecma iala
      ietf oasis tgpp bipm sae), 4 tree-clean but held
      (ashrae gost cie omg — see below), ~8 DELTA (capture structures need per-flavor
      work — un/jis confirmed), NO_DATA reduced to csa only (probe entry
      resolution collapsed the class),
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
      coverage; remaining DELTA: bsi etsi (sequence-fold and
      multi-capture restructuring; jis and un resolved since the
      sweep); adobe gb ieee resolved (aiee
      paren-leak, always-present copublishers). cie and omg's capture fixes probe
      CLEAN (commit above) but their spec suites gate on identifier
      forms still uncovered (joint/paren + x-proceedings; tails).
      LANDING STATE 2026-11-11, verified: the DELTA list above is
      CLOSED — pubid main carries the whole fleet. The pg-namespace
      stacks (`pg-iso-parser-swap` 1bc5b995 + 185c14c4 →
      `pg-adobe-parser-swap` +adobe doi ogc w3c xsf easc iana isbn amca
      calconnect ccsds ecma iala ietf oasis tgpp bipm sae →
      `pg-cen-cenelec-swap` +gb un; 21 flavors, still unmerged locals)
      were superseded by pubid 7a253feb's squash reconciliation
      (data/parg/ + Pubid::Parg::Backend, pg namespace removed) and
      then the typed-binding migration: every flavor routes through
      `Pubid::Parg::Model.bound`, the parslet parsers are empty shells,
      and spec/pubid/parg/ gates it (backend, error-contract,
      freshness, model-parity, typed-binding-parity). No swap PRs
      remain to open — landing the stacks would regress main off the
      typed-binding path. Per-flavor gates on current main (2026-11-11):
      all 21 stack flavors green (iso 3128, adobe 30, doi 11, ogc 52,
      w3c 132, xsf 73, easc 26, iana 115, isbn 18, amca 68, calconnect
      106, ccsds 23, ecma 143, iala 86, ietf 209, oasis 92, tgpp 212,
      bipm 575, sae 313, gb 88, un 10 — 0 failures each) and bsi+etsi
      608 green.
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
- [x] **G5 — cross-runtime suite sweep** (ruby `parg test --suite --json`,
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
- [ ] **P5 — release order** — owner-accepted 2026-11-11:
      pubid-grammar → parsanol engines (DONE — the 0.20.14 train is
      out) → pubid swap landing → one-tag 3-artifact release.
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
