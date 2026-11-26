# frozen_string_literal: true

require "json"

module Pubid
  module Grammar
    module Telemetry
      # The triage pipeline: miss file → intake → detect → parse →
      # classify → report + candidates.
      #
      # Output paths are explicit and derived from the consumer's input
      # path (never written into the repo): for `<name>.jsonl` the run
      # writes `<name>.report.json` and `<name>.candidates.jsonl` in the
      # same directory, unless overridden.
      class Triage
        Result = Struct.new(:report, :report_path, :candidates_path,
                            keyword_init: true)

        # Run the pipeline over a miss file. engine: a Runtime; the
        # injectable pair (engine, index) keeps the end-to-end suite on
        # the real inventory while unit tests can scope it down.
        def self.run(path, engine:, index: nil, generated_at: Time.now,
                     report_out: nil, candidates_out: nil)
          index ||= Detector.build_index(File.join(engine.repo_root, "corpora"))
          # The same inventory doubles as the regression evidence: a miss
          # that is a frozen accept case of a candidate's corpus but its
          # artifact now rejects is a parse bug.
          known_good = index.to_h { |flavor, inputs| [flavor, inputs.to_set] }

          intake = Intake.run(path)
          rows = intake.rows.map do |miss|
            { miss: miss, verdict: classify_miss(miss, engine, index, known_good) }
          end

          report = Report.build(rows: rows, intake: intake,
                                source: path, generated_at: generated_at.utc.iso8601)
          candidate_rows = Candidates.rows(rows)

          report_path = report_out ||
                        path.sub(/\.[^.]+\z/, "").concat(".report.json")
          candidates_path = candidates_out ||
                            path.sub(/\.[^.]+\z/, "").concat(".candidates.jsonl")
          File.binwrite(report_path, JSON.pretty_generate(report) << "\n")
          File.binwrite(candidates_path, Candidates.generate(candidate_rows) << "\n")

          Result.new(report: report, report_path: report_path,
                     candidates_path: candidates_path)
        end

        # Assemble the classifier evidence for one miss against the
        # reference runtime.
        def self.classify_miss(miss, engine, index, known_good)
          candidates = Detector.detect(miss.input, index)
          normalized = Normalizer.normalize(miss.input)
          # A mangled input can defeat the anchored lead-token match
          # (a leading NBSP hides the publisher). Detect the normalized
          # form too, so mangled misses reach the normalization verdict
          # instead of being called unknown.
          if candidates.empty? && Normalizer.mangled?(miss.input)
            candidates = Detector.detect(normalized, index)
          end
          raw = candidates.empty? ? nil : engine.parse(candidates.first, miss.input)

          evidence = Classifier::Evidence.new(candidates: candidates, raw: raw,
                                              normalized_input: normalized)
          probe = ->(flavor, input) { engine.parse(flavor, input) }
          Classifier.classify(input: miss.input, evidence: evidence,
                              known_good: known_good, probe: probe)
        end
      end
    end
  end
end
