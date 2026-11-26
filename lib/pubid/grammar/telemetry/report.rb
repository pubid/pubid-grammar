# frozen_string_literal: true

module Pubid
  module Grammar
    module Telemetry
      # The classified triage report: machine-readable, deterministic,
      # every miss and every intake error accounted for (fail-closed).
      module Report
        module_function

        # Build the report hash from the intake result and the classified
        # rows (row = {miss:, verdict:} pairs, sorted by the classifier
        # order then by input).
        def build(rows:, intake:, source:, generated_at:)
          sorted = rows.sort_by { |row| [Classifier::ORDER.index(row[:verdict].classification), row[:miss].input] }
          by_classification = Classifier::ORDER.to_h do |klass|
            [klass.to_s, sorted.count { |r| r[:verdict].classification == klass }]
          end
          by_flavor = sorted.map { |r| r[:verdict].flavor_name }
                            .tally.sort.to_h

          {
            "format" => TRIAGE_FORMAT,
            "generated_at" => generated_at,
            "source" => {
              "file" => source,
              "lines" => intake.line_count,
              "records" => intake.rows.sum(&:occurrences),
              "misses" => intake.rows.size,
              "intake_errors" => intake.errors.size,
            },
            "summary" => {
              "by_classification" => by_classification,
              "by_flavor" => by_flavor,
            },
            "rows" => sorted.map { |row| row_hash(row) },
            "intake_errors" => intake.errors,
          }
        end

        def row_hash(row)
          miss = row[:miss]
          verdict = row[:verdict]
          {
            "input" => miss.input,
            "flavor" => verdict.flavor_name,
            "classification" => verdict.classification.to_s,
            "reason" => verdict.reason,
            "consumers" => miss.consumers,
            "contexts" => miss.contexts,
            "occurrences" => miss.occurrences,
            "first_seen" => miss.first_seen&.utc&.iso8601,
            "last_seen" => miss.last_seen&.utc&.iso8601,
          }.merge(optional(verdict)).compact
        end

        def optional(verdict)
          {
            "normalized" => verdict.normalized,
            "known_good" => verdict.known_good,
            "parse_error" => verdict.parse_error&.slice(0, 160),
          }
        end
      end
    end
  end
end
