# 5 — Model definitions via lutaml-model (KV/XML mappings)

Extract the pubid identifier models' serialization definitions as
lutaml-model declarations in the pubid monorepo. Owner: pubid/pubid.
This makes the model side schema-driven so all three languages agree
without hand-writing serializers per language.

## Tasks

- [ ] Re-express each identifier class as a lutaml-model class: `attribute`
      declarations (names, types, cardinality, defaults) + KV mapping +
      XML mapping + JSON mapping.
- [ ] Derive the **model schema JSON** from the declarations (rake task):
      field names, types, required-ness, mappings. This is what pubid-ts
      (and pubid-rs) consume — a definition-driven runtime materializes
      the same objects in TS instead of hand-written `toHash`/`fromHash`.
- [ ] Conformance model-JSON becomes lutaml-model `to_hash` output — the
      corpus `model` entries (see 4) are generated from it and are
      canonical by construction.
- [ ] XML: flavors that render XML get `xml` mapping blocks; flavors that
      do not, skip. The mapping is data either way.
- [ ] Validations: keep model-level validations (update semantics, stage
      validity) as Ruby code on the lutaml-model classes — Tier 3 residue,
      see 6. Express them against typed fields, never raw identifier text.
- [ ] Migration order: core identifier → ISO → the rest, per flavor, each
      gated by the flavor's spec suite + the corpus model hashes.

## Why lutaml-model (and not a bespoke schema)

lutaml-model already provides attributes + KV/JSON/YAML/XML mappings with
validations across the metanorma/relaton ecosystem; pubid models are
consumed by relaton. Reusing it means the pubid model definitions, the
conformance model JSON, and relaton's consumption all speak one
serialization dialect with one implementation.

## Acceptance

- [ ] Every identifier class: lutaml-model definitions with KV + (where
      applicable) XML mappings.
- [ ] Model schema JSON exported, checksummed, published with the
      artifacts.
- [ ] pubid-ts materializes models from the extracted schema; TS model
      JSON == Ruby model hash on the full corpus.
