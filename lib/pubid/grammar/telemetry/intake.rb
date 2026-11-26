# frozen_string_literal: true

module Pubid
  module Grammar
    module Telemetry
      # Reads a miss-report file (JSONL), validates every line, and
      # deduplicates the valid records.
      #
      # Deduplication key: the EXACT input string. The same unparseable
      # identifier reported again (by any consumer, at any time) folds
      # into one triage row carrying occurrences, the reporting consumers,
      # and the first/last seen timestamps. Nothing is dropped: malformed
      # lines come back as intake errors and surface in the report.
      class Intake
        # One deduplicated miss: the triage pipeline's unit of work.
        class Row
          attr_reader :input, :occurrences, :consumers, :contexts,
                      :first_seen, :last_seen, :lines

          def initialize(input)
            @input = input
            @occurrences = 0
            @consumers = []
            @contexts = []
            @lines = []
            @first_seen = nil
            @last_seen = nil
          end

          # Deterministic spellings: consumers and contexts sorted, the
          # contributing lines in file order.
          def consumers = @consumers.sort

          def contexts = @contexts.sort

          def add(miss)
            @occurrences += 1
            @consumers |= [miss.consumer]
            @contexts |= [miss.context].compact
            @lines << miss.line_number
            time = Time.iso8601(miss.timestamp)
            @first_seen = time if @first_seen.nil? || time < @first_seen
            @last_seen = time if @last_seen.nil? || time > @last_seen
            self
          end
        end

        Result = Struct.new(:rows, :errors, :line_count, keyword_init: true)

        # Read + validate + dedupe a miss file. Blank lines are skipped
        # (JSONL convention); every other line must parse as a miss or it
        # becomes an intake error.
        def self.run(path)
          rows = {}
          errors = []
          line_count = 0

          File.foreach(path, chomp: true).with_index(1) do |text, line_number|
            line_count += 1
            next if text.strip.empty?

            begin
              miss = Miss.parse(text, line_number: line_number)
              rows[miss.input] = (rows[miss.input] || Row.new(miss.input)).add(miss)
            rescue Miss::Invalid => e
              errors << { "line" => line_number, "error" => e.message }
            end
          end

          Result.new(rows: rows.values, errors: errors, line_count: line_count)
        end
      end
    end
  end
end
