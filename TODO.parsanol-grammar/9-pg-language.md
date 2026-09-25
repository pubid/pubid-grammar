# 9 — PG: the grammar language (SOTA + SSOT)

PG (**P**arsanol **G**rammar language) is the text source format for
grammars — the decision in milestone 3 taken to its conclusion: **JSON is
the compiled artifact, text is the contract.** One `.pg` file per flavor
holds the grammar, the parse bindings, the preprocessing steps and the
entry points; it compiles to the checksummed artifact envelope whose
grammar section is the portable Grammar JSON every engine already
registers. Implemented in parsanol-ruby (`Parsanol::PG`), shipped with the
programming guide: `parsanol-ruby/docs/pg-language-guide.md`.

## What shipped (parsanol-ruby, branch `pg-language`)

- **PG parser + compiler**: full syntax (`= / [ ] ( ) n*m %x %i" " as ! &`
  — ABNF-flavoured surface, PEG semantics), one-rule-per-line layout.
- **Compile-time analysis**: left-recursion rejection (direct + indirect),
  shadowed-alternative ERROR (prefix shadowing, empty-matchable
  non-final, duplicates), order-dependence WARNINGS recorded in the
  artifact — the first-set lint that makes ABNF-style syntax safe under
  ordered choice.
- **Artifact envelope v1**: version / shape `parsanol-tree/v2` /
  binding_version / entries (root + portable grammar JSON + bindings) /
  preprocess steps / tables manifest / lint report / embedded PG source /
  canonical sha256 checksum, verified loudly on load.
- **Bindings runtime**: capture collection from the parsanol-shape tree →
  preprocess (`table_lookup`) → type cast → path assignment (incl. one
  `[]` array-grouping level).
- **Importers** (`PG::Import`): ABNF (RFC 5234 + 7405), EBNF (ISO 14977),
  pest. Each emits **PG source** (which is committed — SSOT preserved),
  self-checks by re-parsing, and documents every semantic conversion
  (ABNF's case-insensitive bare strings → `%i"…"`, ISO exceptions →
  `!(…) …`, pest `~` → explicit-whitespace note, prose-vals/special
  sequences/pest-only builtins → loud rejection).
- **lutaml-model bridge** (`PG::Lutaml.register`): registers an artifact
  as a lutaml-model string format via `Lutaml::Model::FormatRegistry` and
  defines `Model.from_<format>` — artifact parse → bindings → model
  instance. This is the "grammar = serialization-from-string input path of
  lutaml-model" decision made real. 33 specs; full suite 1398/0.

## Why this is SOTA (arXiv/repo survey 2023–2026)

- **Compiled grammar artifacts as interchange** — XGrammar
  (arXiv:2411.15100, 2024; ~232 citations; default structured-generation
  backend in vLLM/SGLang/TensorRT-LLM) and XGrammar-2 (2026) treat a
  serialized, pre-analyzed grammar as the runtime unit; llguidance
  (Microsoft, 2024) likewise. PG artifacts are the parse-side equivalent
  and a future export target for constrained decoding.
- **Ordered-choice hazards are the known PEG pain point** — pegen's own
  docs and 2024 community threads ("PEGs squash ambiguities silently").
  The PG lint converts the two provable classes to build errors and
  surfaces the rest for review — the missing engineering response.
- **Structured PEG errors** — Medeiros 2018/2019 error-recovery line and
  "Towards Automatic Error Recovery in PEGs" (2025) establish
  position/label-carrying errors as SOTA; parsanol's deepest-failure +
  expected-set diagnostics are that wire form (decision: parsanol-rs#145).
- **Grammar quality matters downstream** — Grammar-Aligned Decoding
  (arXiv:2405.21047, NeurIPS 2024) shows grammar flaws propagate into
  generated-output quality; single-source grammars with checksums are the
  supply-chain answer.

## How this plugs into the existing milestones

| Milestone | Effect of PG |
|---|---|
| 2 (grammar port) | flavors are ported **to .pg**, not to JSON by hand |
| 3 (artifacts) | the envelope gains bindings/preprocess/tables/lint/source + binding_version; checksum covers everything |
| 5 (lutaml-model) | `PG::Lutaml.register` is the concrete string-format path |
| 6 (three tiers) | `preprocess` tables are Tier 2 data in the artifact; `render:`/`derive:` sections reserved as Tier 1 output side |
| 8 (LML gaps) | LML `string_format` (lutaml-lml#12) references the artifact; the artifact now has a human-writable source language |

## Remaining work

- [ ] **G1** — render/derive sections in the envelope (parsanol-rs#144;
      LML gets none — reference only).
- [ ] **G2** — structured error wire format (parsanol-rs#145) surfaced
      through artifact-based parsing end to end.
- [ ] **G3** — shape freeze (parsanol-rs#146) recorded as
      `parsanol-tree/v2` validation at artifact load.
- [ ] **G4** — port the pubid ISO grammar to `.pg` as the pilot (milestone
      2 start), using `alt from_table` against the existing `stages` data.
- [ ] **G5** — rs/wasm consume `.pg` artifacts in CI (checksum + portable
      JSON equality gate across engines).
- [ ] **G6** — preprocessing vocabulary growth policy (parsanol-rs#147):
      grow-with-minor vs hard freeze after the ISO pilot.
- [ ] **G7** — self-hosting (parse PG with PG) and `.pg` module imports.
