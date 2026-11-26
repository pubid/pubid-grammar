# The dev-alias → canonical cutover

A composed flavor ships in the gem under the `<org>_pfs` **dev-alias
slot** — registered beside its coded sibling (`Pubid::DoiPfs` beside
`Pubid::Doi`), with the registry sorting the coded key first so
`Pubid.parse` keeps routing the coded flavors. Graduation REPLACES the
coded slot: the compiled flavor becomes THE `<org>` flavor. This is the
cutover.

The rule behind the path is the same one ADD-A-FLAVOR.md states for the
hand-coded route: **the artifact is the only parsing input**. A cutover
that stops before the consumers re-pin has not happened.

## When to cut over

A dev alias is a coexistence state, not a parking lot. Cut over when the
flavor meets ALL of the readiness gates:

1. **The attestation ledger is clean** (the readiness gate,
   pubid/pubid-testsuite#130): `pubid-testsuite`'s
   `tests/<org>_pfs/_status.yaml` carries `attestation: pfs-identity`,
   `clean: true`, `known_mismatches: 0` — every recorded identity
   surface is the compiled flavor's own parse and its URNs are
   byte-identical with the coded parent's. Unabsorbed rows sit in
   `_debt.yaml` as the fail-closed rejection ledger; they do not block,
   but the cutover PR must state what happens to each family (absorbed,
   documented-outside-the-surface, or coded-hook-bound).
2. **Gem parity**: the vendored `data/parg/<org>_pfs.json` is
   byte-identical with the grammar repo's `artifacts/<org>_pfs.json`.
3. **The compiled outputs are committed** in the grammar repo:
   `grammars/<org>_pfs.parg`, `artifacts/<org>_pfs.json`,
   `schemas/<org>_pfs.schema.json`, `corpora/<org>_pfs/corpus.json`.

`pfs cutover <org>_pfs` checks the gates and prints the plan:

```bash
cd pubid-grammar
ruby scripts/pfs cutover doi_pfs        # exit 0 = gates GREEN
```

The command mutates nothing. The cutover crosses four repos and stays a
human-reviewed operation: a branch + a PR in each, reviewed and
rebase-merged on green — never a direct push, never a batch.

## The mechanical steps

Run them in this order. Each numbered step is one PR (except where two
repos move together — steps 3+4 are one PR in the gem).

### 1. Grammar repo: the canonical key

The definition file (`definitions/<org>.pfs`) is the SSOT and does not
move. The compiled outputs take the canonical key:

```bash
ruby scripts/pfs lint definitions/<org>.pfs
ruby scripts/pfs compile definitions/<org>.pfs --as <org> \
  --parsanol-version <fleet pin>
rake contracts:regen
git add grammars/<org>.parg artifacts/<org>.json \
        schemas/<org>.schema.json corpora/<org>/corpus.json
```

`git mv` the `_pfs`-keyed files away in the same PR (or delete them when
the consumers re-pin — the dev-alias key retires only after step 8; keep
both sets until then if any consumer still pins the alias).

### 2. Gem: the module

For a flavor replacing a coded sibling:

```bash
git mv lib/pubid/<org>_pfs lib/pubid/<org>
git mv lib/pubid/<org>_pfs.rb lib/pubid/<org>.rb   # if present
```

then re-key the module namespace (`Pubid::<Org>Pfs` → `Pubid::<Org>`)
inside the moved files. The generated files carry a
`DO NOT EDIT BY HAND` header naming the source definition — after the
move, regenerate rather than hand-edit:

```bash
cd pubid-grammar
ruby scripts/pfs compile definitions/<org>.pfs --as <org> \
  --parsanol-version <fleet pin> --ruby-out <pubid-repo>/lib
```

For a NEW flavor (no coded sibling — the composed flavor IS the first
implementation): the cutover creates the module from the generated
emission (the `--ruby-out` command above) and steps 5–6 become "add"
instead of "replace".

### 3. Gem: the vendored artifact

```bash
git mv data/parg/<org>_pfs.json data/parg/<org>.json
```

(or copy `artifacts/<org>.json` from step 1 — byte-identical by
construction). `spec/pubid/parg/freshness_spec.rb` requires the
freshness envelope of every shipped artifact.

### 4. Gem: the registry

The flavor's module file registers itself
(`lib/pubid/<org>.rb` ends with
`Pubid::Registry.register(:<org>, Pubid::<Org>)`); `lib/pubid.rb`
carries the autoload. Re-key both:

```ruby
autoload :<Org>, "pubid/<org>"          # was :<Org>Pfs, "pubid/<org>_pfs"
Pubid::Registry.register(:<org>, Pubid::<Org>)
```

Drop the dev-alias autoload + registration. The registry sorts the coded
key first, so `Pubid.parse` now routes the canonical key.

### 5. Gem: the parity harness retires

The dev alias carried `spec/pubid/<org>_pfs/parity_spec.rb` — the
harness that proved compiled == coded row by row. After the cutover
there is nothing to compare: the compiled flavor IS the flavor. Move the
harness's corpus tables into the flavor's own contract specs and delete
the parity wrapper:

```bash
git mv spec/pubid/<org>_pfs spec/pubid/<org>
```

then re-shape the specs from "byte-identical with the coded flavor" to
the flavor's own contracts (the cross-flavor gates every flavor
satisfies: prefixes, parse interface, partial refs, parse errors,
roundtrip, annotated rendering).

### 6. Gem: release

Dispatch `release.yml` (the gem's release workflow) with the version
the owner states — never a locally chosen number. The release job runs
the full suite before publishing.

### 7. Testsuite: the canonical dir

```bash
cd pubid-testsuite
git mv tests/<org>_pfs tests/<org>
git mv reference-docs/<org>_pfs reference-docs/<org>   # the rawCopy twin
```

then re-run the round mechanics so the rows attest against the coded
slot:

```bash
FLAVOR=<org> rake corpus:regen
FLAVOR=<org> rake corpus:check
```

The ledger keeps `attestation: pfs-identity` (testsuite#130) and
updates `source_flavor`/`source_note` for the canonical key. The case
counts in the testsuite README change in the same PR.

### 8. Site + consumers

- pubid.github.io: the flavor's docs page and the identifier-patterns
  entry re-key to `<org>`; the `_pfs` cross-links drop.
- relaton (and every consumer Gemfile) re-pins the released gem; the
  registry now routes `Pubid.parse` to the canonical slot.

## What the gates catch

| Mistake | Gate |
|---|---|
| Cutting over on an unattested corpus | DRIFT005 / the cutover gate (testsuite#130 ledger) |
| Graduating with gem drift (the artifact never vendored) | DRIFT004 / the cutover gate |
| The compiled outputs never committed | the compiled-outputs gate; CI's `git diff --exit-code -- schemas corpora` |
| Hand-editing the generated module after the move | regenerate via `--ruby-out`; the DO-NOT-EDIT header names the definition |
| The dev-alias key retired before consumers re-pin | keep both sets until step 8 |
| Re-sealing on a foreign toolchain | DRIFT001's toolchain note — the seal is toolchain-sensitive (ruby-version in the workflow) |

## The doctor's part

`ruby scripts/pfs doctor` is the standing drift check across the whole
path — run it after every step. All green from the grammar repo means
the fleet pin holds, every artifact re-seals, the contracts round is
fresh, the gem's vendored artifacts are byte-identical and every
compiled flavor is attested.
