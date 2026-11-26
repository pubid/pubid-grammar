# frozen_string_literal: true

require "json"

module Pubid
  module Grammar
    module Telemetry
      # Candidate test rows for the attestation pipeline: every classified
      # miss becomes a row shaped like the corpus cases the round pipeline
      # consumes ("input" + "kind" are the corpus-case core; the extra
      # keys carry the telemetry provenance), one JSON object per line.
      #
      # kind is "accept" for every row: the loop's intent is make-it-parse
      # (miss → round → corpus row → release → consumer re-verdict). Rows
      # for unknown flavors carry flavor "unknown" and stay in the queue
      # until a grammar round scopes them — they are never dropped.
      module Candidates
        module_function

        def rows(rows)
          sorted = rows.sort_by do |row|
            [Classifier::ORDER.index(row[:verdict].classification),
             row[:verdict].flavor_name, row[:miss].input]
          end
          sorted.map do |row|
            miss = row[:miss]
            verdict = row[:verdict]
            {
              "input" => miss.input,
              "kind" => "accept",
              "flavor" => verdict.flavor_name,
              "classification" => verdict.classification.to_s,
              "consumers" => miss.consumers,
              "occurrences" => miss.occurrences,
              "first_seen" => miss.first_seen&.utc&.iso8601,
            }
          end
        end

        def generate(rows)
          rows.map { |row| JSON.generate(row) }.join("\n")
        end
      end
    end
  end
end
