# 2 — Grammar port (pubid flavors → parsanol DSL)

Move each flavor's rules from `Parslet::Parser` (parslet) to the parsanol
Ruby DSL. Sources land in this repo (`grammars/<flavor>.rb`); the pubid
monorepo keeps models only.

## Port order (small → large, each gates the next)

- [ ] `api` (smallest, pure combinators — the canary)
- [ ] `ccsds`, `adobe`, `ashrae`, `calconnect` (small flavors)
- [ ] `bsi`, `cen_cenelec`, `etsi`, `gb`, `ieee`
- [ ] `nist` (data-driven: series/stages YAML feeds the rules)
- [ ] `iec`, `itu`
- [ ] `iso` (largest: TYPED_STAGES composition, supplement keys, unicode
      dash variants, rendering styles)

## Mechanics

- The grammars are *computed Ruby*: keep TYPED_STAGES discovery, length
  sorting, dash-char lists as Ruby code — the exported JSON bakes the
  computed result. TS never re-implements composition.
- The `GrammarError` lint (empty-matchable non-final alternative branches)
  is ON during the port: every raise is a real ordered-choice shadow in the
  parslet grammar — triage each as grammar-bug-fix or intentional
  (reorder/anchor), never silence.
- Unicode variants (DASH_CHARS = ["-", "‑", "‐"]) become explicit
  alternatives in parsanol syntax; note them in rule comments as
  load-bearing orderings.
- Per-flavor entry points: `identifier`, plus typed roots (each identifier
  type key) for dispatch — the artifact carries named roots.

## Fidelity gates (per flavor)

- [ ] pubid-testsuite fixtures parse identically (parslet reference vs
      parsanol) — tree-level, before models are involved.
- [ ] GrammarError triage log committed (each finding: fix or justify).
- [ ] Exported JSON parses identically to the DSL (artifact fidelity gate,
      see 3).

## Acceptance

- [ ] All flavors: testsuite green through the parsanol grammar.
- [ ] Artifacts exported, checksummed, committed here.
