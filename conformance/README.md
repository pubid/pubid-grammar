# Conformance ledger (PN 7)

- `pending.yaml` — the migrated pending ledger (from pubid-ts
  conformance/pending.yaml, PN 7/P3): every case any engine cannot yet
  reproduce, with reason + ref. A pending case that passes raises the
  pending-satisfied alarm and MUST be unmarked.
- Release rule (PN 7): a corpus case pending in any engine blocks
  release of the affected flavor.
