# The grammar-miss telemetry intake

*The consumer miss format + the triage pipeline* — pubid/pubid-grammar#150.
Coordination: relaton-api-js#183 (the consumer side), relaton#604 (the
invariant: every unparseable id = a grammar round).

Consumer systems (relaton-api-js first) feed their unparseable
identifiers into the grammar-round workflow. The loop:

```
miss → triage → round → corpus row → release → consumer re-verdict
```

## The miss-report format (`pubid-grammar-miss/v1`)

One JSON object per line (JSONL, UTF-8). Consumers emit one line per
unresolved identifier, as close to resolution time as possible:

```json
{"input":"ISO/IEC 17025:2017/PAS 1","consumer":"relaton-api-js","context":"resolve","timestamp":"2026-11-22T12:00:00Z"}
```

| field        | required | type   | semantics |
|--------------|----------|--------|-----------|
| `input`      | yes      | string | The identifier EXACTLY as received — untouched. Whitespace, HTML entities and control characters are often the finding; never clean up before reporting. |
| `consumer`   | yes      | string | The emitting system, e.g. `relaton-api-js`. |
| `context`    | no       | string | Where the miss happened (endpoint, job name, request id). |
| `timestamp`  | yes      | string | ISO8601, with offset or `Z`. |

Rules:

- Unknown extra keys are tolerated (forward compatibility); the intake
  classifies on the contract fields only.
- Blank lines are skipped. A line that is not a valid miss record does
  not abort the intake — it surfaces in the report's `intake_errors`.
  Nothing is silently dropped.

## The triage pipeline

```
rake telemetry:triage[<misses.jsonl>]
# or: ruby scripts/telemetry-triage.rb <misses.jsonl> [--report P] [--candidates P]
```

The run deduplicates (key: the exact `input`; `occurrences`, the
reporting consumers and the first/last timestamps fold into one row) and
classifies each miss against the grammar inventory — flavor detection
over the committed corpora, then parse attempts through the committed
artifacts (the artifacts are the only parsing input). Outputs land next
to the input file: `<name>.report.json` and `<name>.candidates.jsonl`
(override with `--report` / `--candidates`).

### The classification taxonomy

First match wins, in this order:

| class          | meaning | action |
|----------------|---------|--------|
| `consumer_bug` | The reference grammar accepts the input as-is (stale consumer runtime), or accepts it after consumer-mangling normalization (whitespace runs, HTML entities, NBSP/zero-width/bidi controls, CR/LF) — the consumer broke the string before handing it over. | Fix or update the consumer; no grammar work. |
| `parse_bug`    | The input is a frozen accept case of a candidate flavor's corpus but its current artifact rejects it — a regression. | Fleet-breaking: a grammar round immediately. |
| `grammar_gap`  | A candidate flavor recognizes the publisher family but covers no such shape. | A grammar round for that flavor. |
| `new_flavor`   | No grammar in the inventory matches the identifier's shape (flavor `unknown`). | Scope a new flavor. |

Fail-closed: an unknown shape is classified, reported AND queued — it is
never silently dropped.

### The report (`pubid-grammar-telemetry-triage/v1`)

```json
{
  "format": "pubid-grammar-telemetry-triage/v1",
  "generated_at": "2026-11-26T20:52:00Z",
  "source": {"file": "...", "lines": 8, "records": 6, "misses": 5, "intake_errors": 2},
  "summary": {"by_classification": {"parse_bug": 0, "consumer_bug": 3, "grammar_gap": 1, "new_flavor": 1},
              "by_flavor": {"iso": 3, "iec": 1, "unknown": 1}},
  "rows": [{"input": "...", "flavor": "iso", "classification": "consumer_bug",
            "reason": "...", "consumers": ["relaton-api-js"], "contexts": ["resolve"],
            "occurrences": 2, "first_seen": "...", "last_seen": "..."}],
  "intake_errors": [{"line": 7, "error": "..."}]
}
```

Each row names its flavor, or `"unknown"` when no grammar matches. Rows
are ordered `parse_bug`, `consumer_bug`, `grammar_gap`, `new_flavor`
(regressions first), then by input. `normalized` (the string that
parses), `known_good` and `parse_error` appear on the rows they apply to.

### The candidate rows

One JSON object per line, the corpus-case core (`input` + `kind`) plus
the telemetry provenance — the round pipeline and the attestation
pipeline consume them directly:

```json
{"input":"ISO 99999:2999 (withdrawn)","kind":"accept","flavor":"iso","classification":"grammar_gap","consumers":["mn-api"],"occurrences":1,"first_seen":"..."}
```

`kind` is `accept` for every row: the loop's intent is make-it-parse.
`flavor: "unknown"` rows stay in the queue until a grammar round scopes
them.
