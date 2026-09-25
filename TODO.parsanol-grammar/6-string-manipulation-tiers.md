# 6 — String manipulation: the three tiers (rendering, URN, KV/XML)

The claim "string manipulation must be language-specific" is true only for
a narrow residue. Ultrathink breakdown:

## Why the naive claim fails

An identifier's rendered form ("ISO/IEC 12345-1:2020/AMD 1:2003") is a
normative output — it MUST be byte-identical whether Ruby, TS or Rust
produces it. If each language hand-writes its renderer, we have recreated
the exact drift problem the grammar repo exists to kill (three
implementations of one specification). "Language-specific" can only ever
apply to where the code lives, never to what the code computes.

## The three tiers

### Tier 1 — composition (shared, data or engine-owned)
- **KV / JSON / XML**: already data via lutaml-model mappings (see 5).
- **URN**: standardized templates over fields (`urn:iso:std:iso:...`) —
  declarative template per flavor, data.
- **Render (to_s, toHuman, reference formats)**: conditional composition
  over typed fields with load-bearing orderings. Two candidate homes:
  1. **Render specs as data** (template DSL: ordered segments, conditions
     over fields, literal glue) consumed by a generic renderer per
     language. Identifiers are small structured strings — tractable.
  2. **Engine-owned render service**: parsanol render specs as an *output
     grammar* consuming model-JSON — parse in reverse. One implementation
     in Rust, exposed via Ruby/wasm like parse. The bidirectional-parsanol
     endgame.
  Start with 1 (faster to port per flavor, diffable); graduate hot or
  shared parts to 2.
### Tier 2 — normalization (shared, data)
Already YAML: `update_codes`, `series`, `stages` per flavor. Ship the
extracted forms to TS with the artifacts (Tier 2 of 0-scope).

### Tier 3 — genuinely language-specific (thin)
- Object lifecycle: `update!`/`create` mutability semantics, in-place
  amendment application.
- API ergonomics: method names, keyword arguments, Ruby `Enumerable`
  integration, TS iteration protocols.
- Host integration: relaton interop, ActiveSupport quirks.
These operate on typed fields (Tier 1 outputs), never on raw identifier
text. If a Tier 3 method finds itself doing string surgery on identifier
components, that logic belongs in Tier 1.

## Tasks

- [ ] Inventory: per flavor, enumerate render formats/styles, URN forms,
      and classify each rule into Tier 1 composition / Tier 2 data /
      Tier 3 residue.
- [ ] Render-spec format definition (ordered segments, field references,
      conditions, literal glue, style variants).
- [ ] Generic renderer: Ruby first (replaces renderer.rb per flavor),
      TS second — outputs byte-identical on the render corpus.
- [ ] Render corpus: (model JSON, format, expected string) triples per
      flavor, generated from the Ruby reference.
- [ ] URN templates as data; URN corpus.
- [ ] Graduate shared render specs to the engine render service (output
      grammar) when two+ flavors stabilize.

## Acceptance

- [ ] Render corpus green on Ruby + TS (+ engine render service when it
      exists), byte-identical.
- [ ] No identifier-string surgery outside Tier 1 (CI lint: forbid
      string mutation of component fields in model code).
