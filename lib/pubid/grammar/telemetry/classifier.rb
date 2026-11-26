# frozen_string_literal: true

require "set"

module Pubid
  module Grammar
    module Telemetry
      # The miss classifier.
      # A MECE hierarchy over the evidence, first match wins:
      #
      #   1. consumer_bug   the reference grammar ACCEPTS the raw input —
      #                     the consumer's runtime is stale or its resolve
      #                     path mangled a parseable identifier;
      #   2. consumer_bug   the reference grammar accepts the input after
      #                     consumer-mangling normalization (whitespace,
      #                     entities, control chars) — the consumer broke
      #                     the string before handing it over;
      #   3. new_flavor     no inventory candidate exists — no grammar's
      #                     publisher family matches this identifier's
      #                     shape; a new flavor is needed;
      #   4. parse_bug      the input is a FROZEN accept case of a
      #                     candidate flavor's corpus but its current
      #                     artifact rejects it — a regression;
      #   5. grammar_gap    a candidate flavor recognizes the publisher
      #                     family but covers no such shape — a grammar
      #                     round is needed.
      #
      # Fail-closed: an unknown shape is classified and reported (and
      # queued), never silently dropped.
      module Classifier
        EMPTY_SET = Set.new.freeze

        # The report/queue order: regressions first, then consumer-side
        # fixes, then grammar work, then scoping work.
        ORDER = %i[parse_bug consumer_bug grammar_gap new_flavor].freeze

        # The classification verdict for one miss.
        Verdict = Data.define(:classification, :flavor, :reason,
                              :normalized, :known_good, :parse_error) do
          def flavor_name
            flavor || "unknown"
          end
        end

        # The parse evidence assembled for one miss (all real values):
        # raw is the primary candidate's failure outcome (the reported
        # parse error).
        Evidence = Data.define(:candidates, :raw, :normalized_input)

        # Classify one miss from its evidence.
        #
        # probe: a callable (flavor, input) → Runtime::Outcome — injected
        # so unit tests drive real outcomes against real grammars without
        # loading the whole inventory.
        def self.classify(input:, evidence:, known_good:, probe:)
          candidates = evidence.candidates
          normalized = evidence.normalized_input

          if candidates.any? && (hit = parse_hit(candidates, input, probe))
            return Verdict.new(
              classification: :consumer_bug, flavor: hit,
              reason: "the reference grammar accepts this input — the " \
                      "consumer's runtime is stale or its resolve path " \
                      "mangled a parseable identifier",
              normalized: nil, known_good: nil, parse_error: nil
            )
          end

          if normalized && normalized != input && candidates.any? &&
             (hit = parse_hit(candidates, normalized, probe))
            return Verdict.new(
              classification: :consumer_bug, flavor: hit,
              reason: "parses after consumer-mangling normalization " \
                      "(whitespace/entities/control characters) — the " \
                      "consumer broke the string before handing it over",
              normalized: normalized, known_good: nil, parse_error: nil
            )
          end

          if candidates.empty?
            return Verdict.new(
              classification: :new_flavor, flavor: nil,
              reason: "no grammar in the inventory matches this " \
                      "identifier's shape — a new flavor is needed",
              normalized: nil, known_good: nil, parse_error: nil
            )
          end

          if (owner = known_good_owner(candidates, input, known_good))
            return Verdict.new(
              classification: :parse_bug, flavor: owner,
              reason: "a frozen accept case of the #{owner} corpus but " \
                      "the current artifact rejects it — regression",
              normalized: nil, known_good: true, parse_error: evidence.raw&.error
            )
          end

          primary = candidates.first
          Verdict.new(
            classification: :grammar_gap, flavor: primary,
            reason: "the #{primary} grammar recognizes this publisher " \
                    "family but does not cover this shape — grammar " \
                    "round needed",
            normalized: nil, known_good: nil, parse_error: evidence.raw&.error
          )
        end

        def self.parse_hit(candidates, input, probe)
          candidates.find { |flavor| probe.call(flavor, input).ok }
        end

        def self.known_good_owner(candidates, input, known_good)
          candidates.find do |flavor|
            known_good.fetch(flavor, EMPTY_SET).include?(input)
          end
        end
      end
    end
  end
end
