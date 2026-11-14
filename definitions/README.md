# PFS — the PubID Format Schema (`definitions/`)

One data file (`.pfs`, YAML) per body declares its identifier scheme. The
compiler (`scripts/pfs` + `lib/pubid/grammar/pfs/`, pubid/pubid#706)
generates the PARG edition-2 grammar from the declarations, bakes the
artifact through the existing parsanol pipeline, verifies the REQUIRED
examples against the baked artifact, and can emit the Ruby flavor module
that vendors it. The compiled flavor registers in the same flavor registry
as the coded ones — input guards, the unified error namespace, URN schema
registration and the cross-flavor property gates are inherited by
construction, because the generated code enters pubid through the same
doors.

This is the v1 language reference: what a `.pfs` file may declare, and what
the compiler enforces. v1 grew past the tier-A first wave (issue #706's
declarability matrix: publishers, type tokens, field patterns, canonical/
alternate templates, typed-stage bindings, the URN schema, examples) into
the full declared-emission surface — multi-type emission, draft-stage
serialization, the wrapper shapes, the adopted-base dispatch, publisher
defaults and the fused URN segments (the phase-3 constructs below).

## A worked example

[`doi.pfs`](doi.pfs) is the reference definition — the smallest tier-A
scheme, compiled as the dev-alias flavor `doi_pfs`. Read it alongside this
document. The Phase-2 ports are worked examples of the extensions:
[`calconnect.pfs`](calconnect.pfs) (the §8 acceptance port — the
sub-numbering extension, the calendar binding, the official URN segments
and the presence-guarded render face) and [`etsi.pfs`](etsi.pfs) (the
language bracket at the largest corpus — 24,718 rows, byte-identical on
every identity surface since the phase-3 constructs landed).
[`cen.pfs`](cen.pfs) began as the §4 module-composition port and is now
the full declared-emission absorption: the nine CEN/CENELEC deliverable
families declared as types on the six compiler features of
pubid-grammar#121 (merged as #122), 189/189 corpus rows byte-identical
with the coded flavor, zero rows pinned (pubid#721); its header
documents the features and the honest non-corpus boundaries.

## The file

A `.pfs` file is plain YAML: mappings, sequences, scalars. Anchors,
aliases, tags and merge keys are rejected; so are DUPLICATE keys (YAML's
silent last-key-wins would hide a copy-pasted declaration — a schema that
is the wizard's lossless substrate must round-trip exactly).

```yaml
pfs: 1                          # REQUIRED — the schema major

scheme: doi                     # REQUIRED — the scheme key
title: "Digital Object Identifier"

organization:                   # REQUIRED
  name: "DOI Foundation"        # informational
  publisher: "DOI"              # the flavor's PUBLISHER constant
  prefixes: ["doi:", "DOI:", "10."]   # head-dispatch tokens for Pubid.parse

modules:                        # OPTIONAL — the module library (see below)
  - module: iso.inner           # the module name
    version: 1                  # REQUIRED — the version written against
    parameters: { prefixes: ["BS"] }   # module-declared parameters

grammar:                        # OPTIONAL — named lexical terms
  digit: "%x30-39"
  suffix_char: "%x30-39 / %x41-5A / ..."

date:                           # OPTIONAL — the calendar binding
  fields: [year, month, day]    # fold into the shared Components::Date

types:                          # REQUIRED — at least one
  resource:
    key: doi                    # the semantic type token
    web: resource               # OPTIONAL — the type's web segment (default key)
    title: "DOI"
    short: "DOI"
    tag: "pubid:doi:resource"   # the _type wire tag (default pubid:<scheme>:<name>)
    stage:                      # OPTIONAL — the typed-stage binding
      code: pubdoi              # body-local code
      stage_code: published     # harmonized stage
      abbr: ["DOI"]             # parse-in spellings
    # a type may also carry tokens: (the spellings that select it),
    # publisher_default: and adopted: — the phase-3 constructs below

fields:                         # REQUIRED — at least one
  prefix:
    pattern: '"10" "." 2*digit' # one PARG term; the whole pattern is the capture
    kind: string                # string, or list (the collection bindings)
    sub_numbering:              # OPTIONAL — extension 6 (calconnect 0707.1)
      separators: [".", "-"]    # folds `[ (sep…) 1*digit ]` onto the pattern

templates:                      # REQUIRED
  canonical: '"doi:" {prefix} "/" {suffix}'   # the render face + an accept form
  alternates:                   # OPTIONAL — parse-in spellings
    - '[url_prefix] [scheme_prefix] [slash] {prefix} "/" {suffix}'

urn:                            # REQUIRED
  namespace: doi                # the scheme's official URN namespace
  official:                     # OPTIONAL — the official URN's ordered segments
    - series                    # a field (omitted when it did not capture)
    - date: [year, month, day]  # a fused date group (joined with "-")
  schema:                       # the pubid-scheme schema (PubidUrn.define)
    atoms:
      - { path: prefix, prefix: prefix }   # kind: list / id / ids (string default)
    types:
      - { type: "pubid:<key>:identifier", token: id, core: [] }

examples:                       # REQUIRED — the live test panel
  positives:
    - input: "doi:10.1000/182"
      renders: "doi:10.1000/182"    # asserted against the canonical template
  negatives:
    - "doi:"
```

### Template language

Templates carry these kinds of segments; nothing else:

- `"literal"` — a quoted literal face (no quotes/backslashes inside).
- `{field}` — a declared `fields:` entry; compiles to its capture rule,
  renders as the identifier's value.
- `bare_word` — a reference to a `grammar:` rule.
- `[ … ]` — an optional segment (nested templates allowed; parse-only:
  optionals never render).
- `a / b` — alternation, split on ` / ` outside quotes and brackets.
- `( … )` — a required group: the parenthesized alternation of whole
  faces. Parse accepts the first alternative that matches; render emits
  the first alternative whose fields captured, and a group whose faces
  all miss is an error — cen's head dispatch picks the draft face, the
  Guide face, the adopted face, else the publisher face.

The `canonical:` template must be a single sequence (it is the render
face); `alternates:` are additional accept spellings that normalize to it.
Multi-alternative accept surfaces compile to a brace-bodied rule with one
alternative per line — edition-2 formatting discipline is the compiler's
job, never the definition's.

An optional segment in the canonical face is a **presence guard**: it
renders its inner face iff every field DIRECTLY inside captured (a nested
optional decides its own presence inside). `CC[/series] number[:year…]`
renders `CC/WD 51017:2024-07-23` and `CC 18011` alike, with no stray
separators — the tier-A declarable rendering surface (presence guards,
never value branches). An optional with no field anywhere inside cannot
render and is rejected.

### The module library (`modules:`)

Schemes are not written from scratch — national standards bodies adopt
the ISO/IEC inner formats and CEN overlays them. The library
([`modules/*.pfsmod`](modules/)) ships that machinery as named, versioned,
composable modules a definition binds. The v1 set:

| Module | What it carries |
|---|---|
| `iso.inner` / `iec.inner` | the inner document face as a referenceable module (the study drafts define the faces) — NOT the declared ISO/IEC schemes, which stay tier-D coded |
| `en.overlay` | the CEN adoption layer: the EN face with its draft tokens (prEN/FprEN) |
| `national.prefix` | the parameterized NSB tokens (DIN, BS, NF, SS-, NEN-, UNE-, ÖNORM, CAN/CSA) — the parameter is data |
| `supplements.core` / `edition.core` | the core operators as bindings: a definition binds its body's vocabulary, never redefines what the operator does |

Two rules keep modules sound, and both are compile-time:

1. **Modules declare IDENTITY composition, not just grammar.** An NSB
   identifier is a wrapper-with-adopted (the adopted document is the
   base) — the bsi/cen `adopted` model is the in-fleet precedent. A
   module whose `identity:` names a `base_module:` holds the definition
   to BINDING that module.
2. **Modules declare their extension hooks.** National irregularity (BS
   `+A1` amendments, re-dating) is declared as named hooks; where a body
   exceeds the parameters, it drops to a coded hook beside its
   definition — explicit, never implicit.

A module document (`.pfsmod`) carries the same strict surface: `module:`
(a dotted lower-case name), `version:`, optional `grammar:` fragments,
`tokens:` it claims, `parameters:` (typed; v1 carries `tokens`),
`identity:` (v1 carries `wrapper-with-adopted` with `base_module` and
`adopted_field`) and `hooks:` (plus the informational `title:` /
`description:`). A definition binds it with `{module:,
version:[, parameters:]}` — a bare name would let the version drift
silently.

What the compiler enforces across the composition:

| Rule | Check |
|---|---|
| unknown module | fail-closed — a module the library does not carry cannot be composed |
| version | the bound version must equal the shipped one: newer is refused (fail-closed, the `pfs:` rule), stale is refused too (a module's major is its contract; no silent downgrade) |
| parameters | supplied keys must match the module's declared parameters; a required parameter missing is an error; reserved tokens fail inside parameter values |
| fragment collisions | a `grammar:` name claimed by two modules, or by a module and the definition, cites both — templates resolve against the MERGED view, so a collision would be a silent rebinding |
| token claims | two co-bound modules claiming one token cite both; a module's claim shared with the binding definition (its prefixes, its stage abbreviations) is co-ownership, not competition — binding IS the sharing |
| identity base | a module whose identity names `base_module` holds the definition to binding it |

The composed flavor carries the resolved composition as an introspectable
`MODULES` constant (name, bound version, identity), and the grammar
header lists the bound modules with their source hashes, so regeneration
drift cites the module document.

### The calendar binding (`date:`)

`date: {fields: [year, month, day]}` folds the declared fields into the
shared `::Pubid::Components::Date` — the coded flavors' own shape: one
attribute, flat `year`/`month`/`day` key_value converters, a builder
that composes the component (nil for a partial reference), and the
canonical hash stays flat. Without it, every field is a plain string
attribute (doi's shape).

### The sub-numbering extension (`sub_numbering:`)

A field may declare `sub_numbering: {separators: [...]}` — the tier-B
extension 6, at the pattern level: the field's pattern gains
`[ (sep1 / sep2 …) 1*digit ]`, and the capture stays WHOLE (CalConnect's
`0707.1` is part of the number, exactly as the coded flavor models it).
The wizard offers it as a form field.

### The phase-3 constructs (pubid#706 phase 3, all fail-closed)

The compiler gaps the brackets pinned are now declarations — the six
etsi-bracket gaps first, then the six cen-bracket declared-emission
features (pubid-grammar#121, merged as #122). All fail-closed:

- **collection bindings** — a `kind: list` field binds its `item:` capture
  per repetition (`parts` binds `part` into `["1", "0"]`, dropped when
  empty). The list's `render:` composition drives the face (`prefix`
  glues each item before itself: "-1-0"; `infix` joins).
- **conditional render segments** — canonical optionals render as
  presence guards, and an ALTERNATED optional renders its first
  alternative whose fields captured (`[" V" {version} / " ed." {edition}]`)
  — the compiled renderer and the compiler's own verifier share the
  semantics, and the `renders:` rows pin them.
- **the fold** — a builder-only capture folds onto another field's
  column plus a boolean flag (`edition` → `version` + `is_edition`); the
  source's render presence is the flag, the target's is suppressed
  while it holds.
- **supplement wrappers** — the `supplements:` declaration generates the
  run grammar from the declared kind faces and the builder folds the run
  into SYNTHESIZED wrapper classes (`{_type, number, base}`, outermost
  last — the printed order IS the nesting).
- **int-kind URN cores** — `urn.schema.types[].core` entries may be
  `[path, kind]` pairs (`[[number, int]]`, the coded schemas' supplement
  ordinals); bare paths stay string-kind (the legacy emission).
- **the official URN surface** — `urn.official` segments may carry
  `lower:`, an `affix:`, an `edition_affix:` (replaces the affix while
  the fold flag holds), or a `compose:` of glued slots (the composed
  document code).
- **MR hooks** — the `mr:` declaration fills the shared MrString
  renderer's slots (`type` / `number` / `year` / `edition`) from the
  columns; undeclared segments keep the shared model's answer, and the
  wrapper classes carry the supplement suffix themselves.
- **named segments** (owner directive 2026-11-13) — every grammar
  segment carries a semantic name; a `grammar:` fragment with an
  UNNAMED capture is a compile-time rejection citing the rule, and the
  compiler names every generated rule the same way (`number`,
  `part`, `supplement_kind`, ...).
- **multi-type declared emission** (#121 feature 1) — a type's
  `tokens:` names the spellings that SELECT it (type-position `TR`/
  `Guide`, publisher-position `CR`/`ENV`); the generated builder
  dispatches the class from the captured token, and the token-free
  non-adopted type is the scheme default (cen declares nine families).
- **draft-stage serialization** (#121 feature 2) — a free-standing
  `stages:` map names each draft stage's accepted spellings and its
  official-URN stage code (`pren: {tokens: ["prEN"], urn: proposal}`).
  A field's `map:` folds the captured spelling to the stored code and
  its `render:`/`urn:` map the stored value back to the spelling / the
  URN code; the typed-stage trio compacts to `"stage" => "pren"` by the
  class hook.
- **the cen wrapper shapes** (#121 feature 3) — the supplements
  declaration extends to a string `number_kind:` ordinal, the
  per-wrapper `number_optional:` (the unnumbered "/AC"), the
  wrapper-owned date columns (`date:` on the run, `fields:` on the
  wrapper), the slash-vs-plus run dispatch (standalone wrapper chain
  vs the synthesized consolidated bundle) and the `fragment:` wrapper
  (the FRAG face); the bundle's members serialize under the
  compiler-generated `identifiers` column.
- **the adopted-base dispatch** (#121 feature 4) — `adopted:
  {field:, hook: coded}` is the §4 coded escape hatch: the generated
  builder calls the hook vendored beside the flavor at two explicit
  points (the captured adopted run; the hook's implicit probe). Without
  the section the capture builds nothing.
- **publisher-type defaults** (#121 feature 5) — a type's
  `publisher_default:` names the token the publisher column defaults
  to; `to_hash` drops the column when its value equals the default.
- **fused URN segments** (#121 feature 6) — `urn.official` gains the
  `pub_group` segment (publisher + copublishers fused and downcased:
  "cen-clc-etsi"), the `adopted_mr` segment (the adopted document's MR
  string, its separators fused to colons) and the `stage_code` segment
  ("stage.proposal"), with the wrappers' declared `mr:`/`urn:` chains
  and the consolidated plus marker.

### v1 boundaries (still)

- semantic decode rules (the DAM-family problem) — alternates are
  spelling-only, per the facets ruling.

Per-scheme boundaries live in the definition's own header: cen documents
the loose coded forms its declared accept surface does not carry (the
bare `prEN`, the numberless `CEN/TR`, the `EN ... ED1` edition face, the
`GUID` spelling — none occurs in the pinned corpus) and the coded
`EN cannot be TR` builder guard the declaration does not carry.

## What the compiler enforces (all at compile time, all cited)

Every rejection raises `Pfs::InvalidDefinition` (or `Pfs::ExampleFailure`)
whose message begins with the offending rule — the section path of the
declaration that failed.

| Rule | Check |
|---|---|
| `pfs` | exactly `1`; a higher major fails closed (additive versioning, the engine's `binding_version` precedent) |
| unknown keys | any key the compiler does not know is an error — a key it does not know means a dialect newer than `pfs: 1` |
| reserved tokens | `ed` / `amd` / `cor` cannot be claimed as type keys, publisher or prefix tokens, or stage abbreviations — nor by a module's tokens or its parameters |
| ambiguity: types | two types claiming the same key, the same wire tag, the same stage abbreviation, the same spelling token (one spelling selects exactly one class; a token doubling as another type's stage abbreviation is an error), or the same publisher default are an error citing both |
| ambiguity: stages | two stages claiming one accepted spelling cite both |
| adopted | the declared field must be a builder-only string capture; the hook must be `coded` — the escape hatch calls the hook vendored beside the generated flavor |
| ambiguity: templates | two accept templates that are structurally identical (an alternate that matches exactly what the canonical form matches) are an error citing both |
| ambiguity: modules | fragment/token collisions across the composition cite both claimants (see the module table above) |
| duplicate field names | rejected by the strict loader with the duplicate's line; field names colliding with `grammar:` rule names are rejected in validation |
| unknown references | templates referencing an undeclared `{field}` or `grammar:` rule; URN atoms/types/official segments referencing undeclared fields |
| malformed terms | multi-line `grammar:` fragments or field patterns (line discipline is the compiler's job), unbalanced quotes/brackets |
| render faces | a canonical optional with no field inside cannot render (presence undecidable); a list's item capture and the supplement run's internals are not render surfaces |
| named segments | a `grammar:` fragment with an unnamed capture (`( … )` without `as name`) is rejected citing the rule (owner directive 2026-11-13) |
| lists | a `kind: list` field requires a declared `item:` (plain string, unclaimed) and a `render:` composition; a fold requires a plain `into:` target and a collision-free `flag:` |
| supplements | the run/item/kind/number names must be free; two wrappers claiming one kind face, or one wire tag, cite both |
| examples | REQUIRED: at least one positive; every positive must parse against the generated grammar, render as its declared `renders:`, and bind identically through the BAKED artifact; every negative must fail to parse |

The examples double as the grammar's embedded `test` block (accept /
reject / example rows with the capture expectations the compiler derived
at compile time), so the baked artifact replays them in every engine.

## Compiling

```bash
# compile + bake + verify (the engine pin is mandatory — bake-one.rb rule)
ruby scripts/pfs compile definitions/doi.pfs --as doi_pfs \
  --parsanol-version "$(grep -o 'PARSANOL_VERSION: .*' \
    .github/workflows/parg-conformance.yml | awk '{print $2}')"

# emit the Ruby flavor module for vendoring (the pubid PR's lib/ files)
ruby scripts/pfs compile definitions/doi.pfs --as doi_pfs \
  --parsanol-version 1.3.126 --ruby-out <pubid-repo>/lib

# regenerate the derived contracts (schemas/ + corpora/), then commit
# grammars/, artifacts/, schemas/, corpora/ together
rake contracts:regen
```

Generation is deterministic: recompiling a definition reproduces the
committed `.parg` and artifact byte-for-byte (spec-pinned), and CI fails
on any drift between the definitions and the committed outputs.

## Naming

The definition's `scheme:` is the scheme key (`doi`); `--as` chooses the
compiled flavor key (`doi_pfs`). They differ exactly when a compiled
flavor lands as a dev alias beside its coded sibling — coexistence, not
cutover; cutover is a separate decision. The dev alias carries the
scheme-canonical wire tag and URN namespace (both declared), so its
`to_hash`, `to_s`, `to_urn` and `to_pubid_urn` stay byte-identical with
the coded flavor while `Pubid.parse` keeps routing to the coded one
(registry keys sort the coded key first).
