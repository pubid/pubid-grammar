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
document.

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

grammar:                        # OPTIONAL — named lexical terms
  digit: "%x30-39"
  suffix_char: "%x30-39 / %x41-5A / ..."

types:                          # REQUIRED — at least one
  resource:
    key: doi                    # the semantic type token
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

templates:                      # REQUIRED
  canonical: '"doi:" {prefix} "/" {suffix}'   # the render face + an accept form
  alternates:                   # OPTIONAL — parse-in spellings
    - '[url_prefix] [scheme_prefix] [slash] {prefix} "/" {suffix}'

urn:                            # REQUIRED
  namespace: doi                # the scheme's official URN namespace
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
| reserved tokens | `ed` / `amd` / `cor` cannot be claimed as type keys, publisher or prefix tokens, or stage abbreviations |
| ambiguity: types | two types claiming the same key, the same wire tag, or the same stage abbreviation are an error citing both |
| ambiguity: templates | two accept templates that are structurally identical (an alternate that matches exactly what the canonical form matches) are an error citing both |
| duplicate field names | rejected by the strict loader with the duplicate's line; field names colliding with `grammar:` rule names are rejected in validation |
| unknown references | templates referencing an undeclared `{field}` or `grammar:` rule; URN atoms/types referencing undeclared fields |
| malformed terms | multi-line `grammar:` fragments or field patterns (line discipline is the compiler's job), unbalanced quotes/brackets |
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
