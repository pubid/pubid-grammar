# Adding a flavor, end to end

This is the checklist for taking a new standard flavor from a grammar to
a released identifier in every consumer. It follows the existing
flavors; read `grammars/iso.parg` and `grammars/xsf.parg` alongside it
(ISO for the data-driven, heavily typed shape; XSF for the minimal one).

The rule behind every step: **the artifact is the only parsing input**.
Consumers never re-transcribe rules, so a change that stops at the
grammar never reaches a user.

## 0. Set up the checkouts

The repos must sit side by side so the pinned refs resolve:

```
src/pubid/pubid-grammar        this repo — the contract
src/pubid/pubid                Ruby gem — the reference
src/pubid/pubid-testsuite      the corpus (SSOT for expected outputs)
src/pubid/pubid-ts             the TypeScript mirror
src/parsanol/parsanol-ruby     the engine (RUBY_REF in CI)
```

Use the engine ref pinned in `.github/workflows/parg-conformance.yml`
(`RUBY_REF`). A different compiler version produces a different
artifact envelope (`compiler_version`), so a bake from an unpinned
engine will not reproduce the committed artifacts byte-for-byte.

## 1. Write the grammar

Add `grammars/<flavor>.parg`:

```
grammar PubidXsf version "0.1.0" {
  digit = %x30-39
  special_number = "README" / "xxxx"
  number = (1*digit / special_number) as number
  identifier = "XEP " number
  entry identifier: identifier

  test {
    accept "XEP 0001"
    accept "XEP README"
    reject "nonsense"
    example "XEP 0001" { number: "0001" }
  }
}
```

- `grammar <Name> version "<semver>"` names the artifact; the file name
  is the flavor key everywhere downstream (`<flavor>.parg` →
  `<flavor>.json` → `data/parg/<flavor>.json` → `vendor/parg/<flavor>.json`).
- `entry <rule>: <rule>` names the default parse entry.
- `use <other>` imports another flavor's grammar. Values that can be
  computed (stage lists, dash variants, longest-first orderings) should
  come from `tables/…` with `alt from_table "<file>" column "<name>"`,
  not be hand-copied.
- `test { … }` is the **mandatory capture-level self-test**. `accept`
  and `reject` are smoke checks; `example "<input>" { key: "value" }` is
  the capture expectation the compiler replays at bake time
  (`Native.parse_json_grammar`, the graph wasm/rs actually executes). An
  accept-only test cannot catch a dead choice member — a new alternative
  that the catch-all swallows still "accepts". Write at least one
  `example` per new capture path.
- Bindings, render and derive declarations (`bindings`, `render`,
  `derive` in the envelope) travel with the artifact; add them when the
  flavor needs model binding or rendered/derived strings.

## 2. Bake the artifact

From the **gem's** bundle (so the engine version matches the pin):

```bash
cd ../pubid
bundle exec parsanol parg compile \
  ../pubid-grammar/grammars/<flavor>.parg \
  -o ../pubid-grammar/artifacts/<flavor>.json
```

The command prints the artifact checksum and lint warnings. Verify the
bake is fresh against the source:

```bash
bundle exec parsanol parg check \
  --source ../pubid-grammar/grammars/<flavor>.parg \
  --artifact ../pubid-grammar/artifacts/<flavor>.json
```

Then regenerate the derived contracts (schemas + F4 corpora):

```bash
cd ../pubid-grammar
rake contracts:regen
```

Commit **all three**: `grammars/<flavor>.parg`,
`artifacts/<flavor>.json`, `schemas/<flavor>.schema.json`,
`corpora/<flavor>/corpus.json`. CI's first step is
`git diff --exit-code -- schemas corpora`, so a grammar PR without its
derived files fails.

`corpora/<flavor>/corpus.json` freezes, for every parseable test input,
the native engine's tree (`parsanol_tree`), its bound map, and any
rendered/derived strings. These are the cross-engine expectations.

## 3. Run the conformance gates

Locally:

```bash
bundle exec parsanol parg test artifacts/<flavor>.json
scripts/cross-runtime-check.sh
```

CI runs, per PR:

- **grammar** — compile every grammar, run its embedded tests, and
  require `schemas/`/`corpora/` to match the grammars;
- **rust** — `parg_bindings` against the artifacts;
- **typescript** — the iso runtime test plus the **cross-engine corpus
  gate**: every corpus case must parse through the wasm engine to the
  native tree the corpus froze, row for row, and every artifact must
  carry a fresh `source_hash`/`compiler_version`
  (`pubid-ts/scripts/corpus-parity.mjs`).

A drift fails with `flavor#index`, the input, and the want/got trees.
Do not edit a corpus expectation to make a gate pass; if the native
tree is wrong, fix the grammar and rebake, then regenerate the corpus.

## 4. Add the Ruby flavor

1. Copy the artifact into the gem: `data/parg/<flavor>.json` (the
   shipped artifacts are the parser of record;
   `spec/pubid/parg/freshness_spec.rb` requires the freshness envelope).
2. Register the module in `lib/pubid.rb` (`autoload :<Flavor>` and
   `Pubid::Registry.register(:<flavor>, Pubid::<Flavor>)`).
3. Add the module: `parser.rb` (delegating to the artifact), `builder.rb`
   (parse tree → attributes), `identifiers/` (lutaml models — no
   hand-rolled serialization), `renderer.rb`, `urn_generator.rb`, and a
   `urn_parser.rb` that inverts the generator.
4. Add specs and fixtures. Fixtures are **generated**:
   `bundle exec rake "validation:classify[<flavor>]"` reads
   `spec/fixtures/<flavor>/…/full/identifiers.txt` and rewrites
   `pass/`/`fail/` — never hand-edit those two directories.
5. Run the cross-flavor contracts that every flavor must satisfy:
   `spec/pubid/prefixes_spec.rb`, `parse_interface_spec.rb`,
   `partial_ref_spec.rb`, `parse_error_spec.rb`, `identifier_roundtrip_spec.rb`,
   `annotated_rendering_spec.rb` (add the flavor's entries where the
   specs carry tables).
6. Document the flavor's forensics in `lib/pubid/<flavor>/CLAUDE.md`
   and generate `docs/identifier-patterns/<flavor>.md` with
   `rake docs:patterns`.

## 5. Add the corpus round

The corpus lives in `pubid-testsuite`:

```bash
cd ../pubid-testsuite
FLAVOR=<flavor> rake corpus:regen     # export + provenance
FLAVOR=<flavor> rake corpus:check     # fail on drift
```

- The exporter writes `tests/<flavor>/*.yaml` and `_status.yaml`
  (curated fields are hand-editable; payloads are generated).
- Provenance pins the gem commit, the grammar commit and every
  artifact checksum. Any payload change without a provenance refresh
  fails CI as a tampered payload.
- Update the case counts in the testsuite README in the same PR.
- Negatives stay in lockstep across the ledger, the fail fixtures and
  the gem twin (see `TODO.correct-test-suite/`).

The full rhythm per wave: gem PR → rebase-merge on green → alpha
release → corpus round → ts mirror (with a pin bump and a fresh
conformance/ledger run) → npm patch → relaton pin.

## 6. Mirror in pubid-ts

1. Add the flavor under `src/flavors/<flavor>/` as declarations on the
   shared model (never per-flavor hand-rolled serialization), and wire
   `grammarImplementation`.
2. `npm run artifact` — rebuilds the corpus artifact and **vendors all
   grammar artifacts** into `vendor/parg/`. Commit the result in the
   same change that bumps `.github/pins.yaml`
   (`testsuite_ref`, `grammar_ref`). CI now requires
   `vendor/parg/*.json` to be byte-identical to the pinned grammar ref.
3. Run `npm test`: the corpus conformance runner asserts every case
   except the documented ledger
   (`conformance/pending.yaml` — every entry needs a reason + ref; a
   satisfied pend must be unmarked).
4. If the flavor emits URNs, port `parseUrn` and regenerate
   `test/fixtures/urn-parity.json.gz` from the reference's
   `UrnParser.parse` over the corpus. The harness asserts exact parity;
   do not add a known-divergent allowance without a reference-side
   defect and a pinned reason.
5. Document the port in the flavor's notes and bump the pins in the
   same PR.

## 7. Release

- Gem: dispatch `release.yml` with the next `2.0.0.pre.alpha.N`.
- Corpus: re-provenance the new alpha.
- ts: publish the next patch (`release.yml -f version=X.Y.Z`); the
  release job runs the full suite, the cross-engine gate and the
  vendored-artifact check before publishing.
- relaton: pin the released alpha in `Gemfile` (comment why; no rawbib
  expectation moves unless the release changes a rendered face).

## The checks that catch mistakes

| Mistake | Gate |
|---|---|
| Grammar PR without rebaked artifact/schemas/corpora | `git diff --exit-code -- schemas corpora` |
| Artifact not compiled from the current `.parg` | freshness envelope (`source_hash` + `compiledFrom`) |
| Native/wasm engine drift | cross-engine corpus gate (row-level diff) |
| Stale vendored artifacts in the published package | `vendor/parg` byte comparison in ts CI/release |
| Corpus payload changed without provenance | testsuite tampered-payload check |
| Hand-edited fixtures | classify regenerates `pass/`/`fail/` |
| A pending case that now passes | pending-satisfied alarm |
