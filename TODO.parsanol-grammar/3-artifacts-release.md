# 3 — Artifacts, versioning, release

## Artifact envelope

```json
{
  "version": "1.0.0",
  "shape": "parsanol-tree/v2",
  "grammar_schema": "<checksum>",
  "entry_points": { "identifier": "...", "iso_typed": "...", "...": 0 },
  "checksum": "sha256:...",
  "atoms": { "...": "grammar body" }
}
```

## Tasks

- [ ] Export rake task in the pubid monorepo writes artifacts here (or
      opens the PR here) on every grammar change; checksums verified in CI.
- [ ] Publish `pubid-grammar` gem + `@pubid/grammar` npm from the same tag,
      byte-identical contents.
- [ ] pubid monorepo release-order.json: insert this repo ahead of
      `pubid-core` (it is a dependency of the parser swap).
- [ ] Verify API: consumers validate checksums before parse (fails loudly
      on mismatch — never silently falls back).
- [ ] Semver policy: capture renames/removals = major; new alternatives =
      minor; literal fixes = patch. Binding specs pin artifact versions.
- [ ] Downstream tests: `downstream-tests.json` consumers run against the
      new artifact before release.

## Acceptance

- [ ] A grammar PR → artifact release → consumer dependency bump is a fully
      automated pipeline (release-plz or equivalent).
- [ ] Checksum verification tested in all three consumer languages.
