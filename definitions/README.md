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
the compiler enforces. v1 expresses the tier-A surface (issue #706's
declarability matrix): publishers, type tokens, field patterns, canonical/
alternate templates, typed-stage bindings, the URN schema, examples.

## A worked example

[`doi.pfs`](doi.pfs) is the reference definition — the smallest tier-A
scheme, compiled as the dev-alias flavor `doi_pfs`. Read it alongside this
document. The two Phase-2 ports are worked examples of the extensions:
[`calconnect.pfs`](calconnect.pfs) (the §8 acceptance port — the
sub-numbering extension, the calendar binding, the official URN segments
and the presence-guarded render face) and [`cen.pfs`](cen.pfs) (the §4
module-composition port — the measured boundary of what the module
library absorbs; its header documents the six coded-machinery blockers
the pubid harness `spec/pubid/cen_pfs/` pins as a ledger).

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

fields:                         # REQUIRED — at least one
  prefix:
    pattern: '"10" "." 2*digit' # one PARG term; the whole pattern is the capture
    kind: string                # v1 carries `string`
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
      - { path: prefix, prefix: prefix }
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

Templates carry four kinds of segments; nothing else:

- `"literal"` — a quoted literal face (no quotes/backslashes inside).
- `{field}` — a declared `fields:` entry; compiles to its capture rule,
  renders as the identifier's value.
- `bare_word` — a reference to a `grammar:` rule.
- `[ … ]` — an optional segment (nested templates allowed; parse-only:
  optionals never render).
- `a / b` — alternation, split on ` / ` outside quotes and brackets.

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
`adopted_field`) and `hooks:`. A definition binds it with `{module:,
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

### v1 boundaries

Declared for later versions, rejected (or unimplemented) in v1, so a
definition using them fails closed rather than compiling halfway:

- field kinds other than `string` (int-kind patterns are a later extension);
- multiple `types:` per scheme for the Ruby emission (the PARG grammar
  handles the general shape; the generated flavor is single-type);
- free-standing `stages:` maps (body→harmonized mappings without a type)
  and `supplements:` declarations — the edition/supplement machinery's
  tokens (`ed`, `amd`, `cor`) are RESERVED in v1 and cannot be claimed as
  type keys, publisher/prefix tokens, or stage abbreviations;
- semantic decode rules (the DAM-family problem) — v1 alternates are
  spelling-only, per the facets ruling.

## What the compiler enforces (all at compile time, all cited)

Every rejection raises `Pfs::InvalidDefinition` (or `Pfs::ExampleFailure`)
whose message begins with the offending rule — the section path of the
declaration that failed.

| Rule | Check |
|---|---|
| `pfs` | exactly `1`; a higher major fails closed (additive versioning, the engine's `binding_version` precedent) |
| unknown keys | any key the compiler does not know is an error — a key it does not know means a dialect newer than `pfs: 1` |
| reserved tokens | `ed` / `amd` / `cor` cannot be claimed as type keys, publisher or prefix tokens, or stage abbreviations — nor by a module's tokens or its parameters |
| ambiguity: types | two types claiming the same key, the same wire tag, or the same stage abbreviation are an error citing both |
| ambiguity: templates | two accept templates that are structurally identical (an alternate that matches exactly what the canonical form matches) are an error citing both |
| ambiguity: modules | fragment/token collisions across the composition cite both claimants (see the module table above) |
| duplicate field names | rejected by the strict loader with the duplicate's line; field names colliding with `grammar:` rule names are rejected in validation |
| unknown references | templates referencing an undeclared `{field}` or `grammar:` rule; URN atoms/types/official segments referencing undeclared fields |
| malformed terms | multi-line `grammar:` fragments or field patterns (line discipline is the compiler's job), unbalanced quotes/brackets |
| render faces | a canonical optional with no field inside cannot render (presence undecidable) |
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
