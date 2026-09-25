# 8 — LML & lutaml-model gaps: the model + string-format definition layer

The target architecture (user, 2026-09):

> lutaml-model defines two things: the **information model** of a pubid
> identifier, and its **serialization models** (YAML/JSON/XML — and now
> identifier **strings**). The parsanol grammar links grammar objects
> (plus optional preprocessing) to fill those models — the grammar is the
> **"serialization from string"** input path of lutaml-model. Models are
> authored in **LML** (`lutaml-lml`), so LML syntax must grow to cover the
> pubid use cases, and the use cases drive the primitives.

Findings below come from `lutaml-lml/docs/lml-models-and-instances-syntax.adoc`
(read in full), `lutaml-model`'s `FormatRegistry`/mapping surface, and the
pubid monorepo (`Pubid::FormatRegistry`, `lib/pubid/schema/`,
`lib/pubid/rendering/`, `urn_generator/`).

**Decision points filed as issues (2026-09-25)** — options + recommendation
on each, awaiting owner calls:

| Decision | Issue |
|---|---|
| Artifact envelope v2: parse bindings section | parsanol/parsanol-rs#143 |
| Artifact envelope: render/derive specs (output side) | parsanol/parsanol-rs#144 |
| Structured parse error wire format | parsanol/parsanol-rs#145 |
| parsanol-shape v2 freeze + load-time validation | parsanol/parsanol-rs#146 |
| Preprocessing vocabulary + executor (binder vs engine) | parsanol/parsanol-rs#147 |
| LML serialization mapping blocks (KV/XML/JSON) | lutaml/lutaml-lml#11 |
| LML string_format + division of labor with artifacts | lutaml/lutaml-lml#12 |
| `type` collision: override keyword vs `=` disambiguation | lutaml/lutaml-lml#13 |
| Enum member payloads + table-driven enums | lutaml/lutaml-lml#14 |
| Defaults, nil policy, derived-field declarations | lutaml/lutaml-lml#15 |
| Model/schema versioning + co-release gate | lutaml/lutaml-lml#16 |
| Instance-layer semantics (5 sub-decisions) | lutaml/lutaml-lml#17 |

## Key discovery: the extension point already exists

`Lutaml::Model::FormatRegistry.register(format, mapping_class:, transformer:,
adapter_class:, error_types:, key_value:, ...)` registers a **custom
serialization format** end-to-end — it generates `to_<fmt>`/`from_<fmt>` on
every model, wires error types, and registers mapping methods. A grammar-backed
identifier-string format (`:pubid` per flavor, or a generic `:string_format`)
is a *registration*, not a fork of lutaml-model.

And pubid already evolved toward it independently: `Pubid::FormatRegistry`
holds `{renderer:, parser:}` pairs per flavor with parent-chain fallback. That
is the seed of the format transformer — it should eventually *be* a
lutaml-model `FormatRegistry.register` call whose parser side is the parsanol
artifact.

## What LML already covers

Classes (attributes, types, cardinality, docs), enums with member docs,
`reference:(Class.key)` typed refs, collections (`class X < Array` +
`member_type`/`member_unique` — planned), instance data with lists/nested
instances/enum refs, `require`, and an executor DSL (import/export/collection
validation). Enough to sketch pubid's *information model* today.

## Gap 1 — LML has no serialization mappings at all

LML compiles `attribute` declarations to plain `Serializable` classes. There
is **no syntax** for what lutaml-model calls `mapping do ... end` — KV names,
XML element-vs-attribute, ordered children, namespaces, `render_nil`,
`delegate`, content mapping. For pubid, the whole point of milestone 5
(TODO/5) is schema-driven KV/XML mappings shared by three languages; those
declarations must live in LML, not be re-hand-written in Ruby per language.

**Add to LML (per class):**

```
class IsoIdentifier {
  attribute number { type String  cardinality 1 }
  ...
  mapping key_value {
    map number, to: "number"
    map type, to: "type", render_nil: false
  }
  mapping xml {
    map originator { attribute: true }
    map supplements, to: "supplement", sequence: true
  }
}
```

LML needs only a constrained, declarative subset of the mapping DSL (wire
name, attribute/element choice, collection shape, nil policy, `when`
variants later). The compiler emits real lutaml-model `mapping` blocks.
**Primitive work:** lutaml-lml `model_compiler` grows mapping compilation;
lutaml-model is unchanged (it already accepts mappings from any builder).

## Gap 2 — LML has no string-format (grammar) binding

Nothing in LML can say "instances of this class serialize to/from the
identifier string per grammar artifact X, entry point Y". This is the core
of the user's architecture and the biggest missing concept. Proposed
addition, per class or per model block:

```
class IsoIdentifier {
  string_format :pubid {
    artifact "pubid/iso"          # grammar artifact ref (TODO/3 envelope)
    root "iso_identifier"         # entry point
    map capture: "year",        to: "year",       type: Integer
    map capture: "supplements", to: "supplements", collection: true
    preprocess :stage_code,     table: "stages"     # named step, data-backed
    render segments: [ ... ]    # Tier-1 render spec (see TODO/6), v1
  }
}
```

Semantics: `from_pubid(str)` = artifact parse (parsanol) → parsanol-shape
tree → preprocessing pipeline → attribute assignment; `to_pubid` = render
spec over typed fields. Declared **once**, materialized identically by
Ruby/wasm/Rust binders.

**Primitive work:**
- **parsanol: binding section in the artifact** (TODO/3 envelope gains
  `bindings:`): stable capture names (depends on parsanol-shape v2, TODO/1),
  capture→attribute maps, type casts, named preprocessing steps + data-table
  refs. Today the envelope has only atoms/entry points — the binding is the
  missing bridge from tree to model.
- **parsanol: structured parse errors** with offsets (expected-at, deepest
  failure) so `from_pubid` raises lutaml-model-style errors like `from_xml`
  (`error_types:` in FormatRegistry is ready to receive them).
- **lutaml-model: grammar-backed format reference implementation** — a
  transformer/adapter pair that consumes an artifact + binding (Ruby first,
  driven by parsanol-ruby; wasm/Rust reuse the same artifact).

## Gap 3 — the `type` attribute collision (breaks pubid today)

LML instance hydration cannot model a data attribute named `type`: bare or
`=`-assigned `type` is treated as an instance-type override (documented
WARNING). pubid identifiers **have** a `type` field (`:amd`, `:tr`,
`:standard`, discriminator for identifier subclasses) — first instance file
hits this. Fix: type override only via a reserved spelling (or explicit
`isa`/`instance_type` keyword); plain `type` is data.

## Gap 4 — enums cannot carry data payloads

pubid's stage/series/update_codes tables attach fields per member
(`abbreviation`, `abbr_prev`, URN segment, harmonized codes). LML enums have
members + `definition` text only — no per-member attributes, no typed
payload, no way to load members from data:

```
enum Stage {
  draft10 { abbreviation "WD"  urn_segment "wd" }
  published { abbreviation "IS"  urn_segment "published" }
}
enum Stage from_table "stages"   # or: data-driven members (Tier 2 YAML)
```

Primitive work: enum member attribute syntax in LML; compile to
lutaml-model enums-as-classes (lutaml-model already supports enum-with-payload
via value objects). Data-table-driven enums make the existing flavor YAMLs
Tier-2 truth inside the model layer instead of parser-side magic.

## Gap 5 — present-nil vs absent, defaults, derived fields

- LML cardinality `0..1` has no nil-policy: lutaml-model distinguishes
  `render_nil` / absent vs explicit nil; pubid render output depends on it
  (omitted stages vs empty `""`). Add `nil_policy`/`render_nil` to LML
  attributes.
- No **defaults** in LML (`pubid` fields like `year` inference, default
  originator). lutaml-model supports defaults; LML needs `default <value>`.
- No **derived/consolidated** fields: lutaml-model has consolidation maps;
  pubid computes `tiny`, URN, alt forms. Expose `derive <attr> from ...`
  (v1: named derivation functions registered per language; v2: rendered by
  the output grammar — TODO/6 Tier 1 graduate path).

## Gap 6 — instance-layer correctness gaps that pubid corpora will trip

From the implementation-status table: single nested instance hydrates to a
1-element array under scalar cardinality; maps/ranges parse but don't
survive hydration; enum refs stay raw strings; `members` strictness and
collection compile are planned; top-level repeated
`collection`/`import`/`export` blocks don't accumulate. None block milestone
5 (definitions), but the conformance corpora (TODO/4) will be authored as
instance data — the hydration fixes land before corpus generation starts.

## Gap 7 — no model versioning in LML

TODO/3 makes artifact semver a contract; the **model schema JSON** needs the
same. LML has no `version` declaration on the `models` block. Add
`models PubidModels version "1.0.0" { ... }` → exported in schema JSON,
checked by conformance runners (schema/model/artifact versions must move
together in a release — one PR bumps all three or CI fails).

## Driving use cases (what proves the primitives)

| # | Use case | Exercises |
|---|---|---|
| U1 | `Pubid::Core::Identifier` re-expressed in LML: classes, `type` enum, cardinalities, nil policies; compiled Ruby passes the pubid spec suite | Gaps 1, 3, 4, 5 |
| U2 | ISO flavor `from_pubid`/`to_pubid` via declared `string_format` over the artifact — round-trip byte-identical, errors typed | Gaps 2, 3, 5; parsanol bindings + errors |
| U3 | Stage/series tables as data-driven enums used by both parse preprocessing and render conditions | Gap 4; artifact preprocessing |
| U4 | pubid-ts materializes models from exported schema JSON + artifact; conformance corpus green | Gaps 1, 7 + TODO/3/4/5 |
| U5 | One grammar-artifact + one schema release flips all three languages | TODO/3 pipeline |

## Tasks

- [ ] **L1 (lutaml-model):** document + reference-implement grammar-backed
      custom formats via `FormatRegistry.register` (transformer consumes
      artifact + binding). Ruby/parsanol-ruby first.
- [ ] **L2 (parsanol):** artifact envelope `bindings:` section (capture→
      attribute, casts, preprocessing steps); walker+VM expose stable
      capture metadata (parsanol-shape v2 dependency, TODO/1).
- [ ] **L3 (parsanol):** structured parse errors (offset, expected-set,
      deepest-failure) exposed in ruby/wasm, mapped to lutaml-model
      `error_types`.
- [ ] **L4 (lutaml-lml):** mapping-block syntax (Gap 1) → model_compiler
      emits lutaml-model mappings.
- [ ] **L5 (lutaml-lml):** `string_format` declaration (Gap 2) → compiled
      model registers the format; artifact/table refs resolved by the
      binder, not LML.
- [ ] **L6 (lutaml-lml):** fix `type` collision (Gap 3); enum member
      attributes + `from_table` (Gap 4); `default`/nil-policy/`derive`
      (Gap 5); `models ... version` (Gap 7).
- [ ] **L7 (lutaml-lml):** instance-layer hydration fixes (Gap 6) before
      corpus authoring begins.
- [ ] **L8 (pubid):** migrate `Pubid::FormatRegistry` to lutaml-model
      format registration (U2 as the pilot, ISO flavor).

## Acceptance

- [ ] U1–U4 green (pubid spec suite on compiled-from-LML Ruby models;
      round-trip corpus byte-identical; TS materialization parity).
- [ ] A model change that affects the string format requires exactly one
      edit in LML — grammar artifact, Ruby, TS, and schema JSON all move
      via the release pipeline with no hand-written serializer changes.
- [ ] No `respond_to?`-style duck typing and no hand-rolled `to_h`/
      `from_h` anywhere in the new layers — all (de)serialization via
      lutaml-model mappings.
