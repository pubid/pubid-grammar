# pubid-grammar

The language-independent grammar home for **pubid**: formal grammars in
parsanol syntax, exported artifacts, capture schemas, conformance corpora,
and binding specs.

One grammar. One engine (parsanol). N language models.

```
pubid-grammar (this repo — the CONTRACT)
├── grammars/<flavor>.pg         PG sources — the contract (see TODO/9)
├── grammars/<flavor>.json       exported artifacts (versioned, checksummed)
├── tables/                      data tables referenced by alt from_table
├── schemas/<flavor>.schema.json capture schema (derived)
├── corpora/<flavor>/            inputs + expected parsanol trees + model JSON
├── bindings/<flavor>/           per-language binding specs
└── TODO.parsanol-grammar/       the work plan, milestone by milestone
```

Consumers:

| consumer | language | engine | reads |
|---|---|---|---|
| `pubid` (monorepo gem) | Ruby | parsanol-ruby walker | artifacts + binding specs |
| `pubid-ts` | TypeScript | @parsanol/wasm | artifacts + binding specs |
| `pubid-rs` (later) | Rust | parsanol-rs | artifacts + binding specs |

## The contract

- A grammar change = a PR here = a versioned artifact release. Consumer
  binding specs are validated against the capture schema in their own CI.
- The artifact is the ONLY parsing input: consumers never re-transcribe
  rules. The Ruby DSL sources exist so rules may be *computed* at build
  time (stage lists, dash variants, longest-first orderings); the export
  bakes the computed result.
- String semantics: see TODO.parsanol-grammar/6 — composition that must
  agree across languages (KV/XML/URN/render) is data or engine-owned;
  only object lifecycle and API ergonomics are language-specific.

## Milestones

See `TODO.parsanol-grammar/0-scope-repositories.md` through
`9-pg-language.md`, in order. The engine prerequisites (milestone 1)
are tracked partly in parsanol-rs/parsanol-ruby.
