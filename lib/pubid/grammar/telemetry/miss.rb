# frozen_string_literal: true

require "json"
require "time"

module Pubid
  module Grammar
    module Telemetry
      # One consumer miss: one JSON line of the miss-report format
      # ({input, consumer, context, timestamp} — docs/TELEMETRY-INTAKE.md).
      #
      # The input is stored EXACTLY as the consumer reported it: the
      # whitespace and control characters are often the finding.
      class Miss
        # A line that is not a valid miss record. The intake never drops
        # these silently — they surface in the report's intake_errors.
        class Invalid < StandardError
          attr_reader :line_number

          def initialize(message, line_number:)
            @line_number = line_number
            super("line #{line_number}: #{message}")
          end
        end

        attr_reader :input, :consumer, :context, :timestamp, :line_number

        def initialize(input:, consumer:, context: nil, timestamp:, line_number:)
          @input = input
          @consumer = consumer
          @context = context
          @timestamp = timestamp
          @line_number = line_number
        end

        # Parse one JSONL line into a Miss or raise Miss::Invalid.
        def self.parse(text, line_number:)
          obj =
            begin
              JSON.parse(text)
            rescue JSON::ParserError => e
              raise Invalid.new("not valid JSON (#{e.message[0, 60]})",
                                line_number: line_number)
            end
          unless obj.is_a?(Hash)
            raise Invalid.new("not a JSON object (#{obj.class})",
                              line_number: line_number)
          end

          input = require_string(obj, "input", line_number)
          consumer = require_string(obj, "consumer", line_number)
          context = opt_string(obj, "context", line_number)
          timestamp = require_timestamp(obj, line_number)

          new(input: input, consumer: consumer, context: context,
              timestamp: timestamp, line_number: line_number)
        end

        # Unknown keys are tolerated (forward compatibility): a consumer
        # may attach extra fields; the intake classifies on the contract
        # fields only.
        def self.require_string(obj, key, line_number)
          value = obj[key]
          unless value.is_a?(String) && !value.empty?
            raise Invalid.new(
              "#{key.inspect} must be a non-empty string " \
              "(got #{value.inspect[0, 40]})", line_number: line_number
            )
          end
          value
        end

        def self.opt_string(obj, key, line_number)
          value = obj[key]
          return nil if value.nil?
          unless value.is_a?(String)
            raise Invalid.new("#{key.inspect} must be a string (got #{value.class})",
                              line_number: line_number)
          end
          value
        end

        def self.require_timestamp(obj, line_number)
          raw = obj["timestamp"]
          unless raw.is_a?(String) && !raw.empty?
            raise Invalid.new("timestamp must be an ISO8601 string",
                              line_number: line_number)
          end
          begin
            Time.iso8601(raw)
          rescue ArgumentError
            raise Invalid.new("timestamp #{raw.inspect[0, 40]} is not ISO8601",
                              line_number: line_number)
          end
          raw
        end
      end
    end
  end
end
