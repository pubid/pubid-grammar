# frozen_string_literal: true

require "json"

module Pubid
  module Grammar
    module Telemetry
      # Flavor detection against the grammar inventory: every committed
      # identifier corpus (corpora/<flavor>/corpus.json) contributes the
      # accept inputs of its flavor, and a miss's leading publisher token
      # is matched against that index.
      #
      # The detector names CANDIDATE flavors, never a verdict — the
      # classifier decides by parsing the candidates through their
      # artifacts. Multiple candidates are fine: a slash-joined publisher
      # ("ISO/IEC") matches the joint grammar and the sibling ones, and
      # the ranking puts flavors that publish identifiers starting with
      # the miss's exact leading token first.
      #
      # A miss with no candidate is exactly the new-flavor signal — it is
      # classified and queued, never dropped (fail-closed).
      class Detector
        # The data-language grammars (document/text formats, not
        # identifier schemes). Their artifacts accept arbitrary text, so
        # they must never act as identifier verdicts or contribute
        # publisher tokens to the index.
        NON_IDENTIFIER_FLAVORS = %w[csv ini json lua parg toml].freeze

        # The leading publisher token of an identifier string: the first
        # run of letters (with . / - joins), e.g. "ISO", "IEEE Std",
        # "ISO/IEC", "WMO/TD-No."
        def self.lead_token(input)
          match = /\A[A-Za-z][A-Za-z.\/-]*/.match(input)
          match && match[0]
        end

        # The candidate flavors for an input over the inventory index
        # (flavor → accept inputs), most specific first:
        #   1. flavors whose corpus publishes identifiers starting with
        #      the miss's exact leading token (primary-token hits),
        #   2. flavors whose token set contains the whole leading token,
        #   3. flavors matching a slash-part of it ("ISO" of "ISO/IEC"),
        # alphabetical within a tier so the ranking is deterministic.
        def self.detect(input, index)
          token = lead_token(input)
          return [] if token.nil?

          parts = token.split("/")
          scored = index.filter_map do |flavor, inputs|
            primary = inputs.count { |row| lead_token(row) == token }
            tokens = tokens_of(inputs)
            exact = tokens.include?(token)
            shared = parts.any? { |part| tokens.include?(part) }
            next nil unless primary.positive? || exact || shared

            [flavor, primary, exact ? 1 : 0]
          end
          scored.sort_by { |flavor, primary, exact| [-primary, -exact, flavor] }
                .map(&:first)
        end

        # Build the inventory index: flavor → sorted accept inputs, over
        # the identifier flavors only.
        def self.build_index(corpus_dir)
          Dir.glob(File.join(corpus_dir, "*", "corpus.json"))
             .sort
             .reject { |path| NON_IDENTIFIER_FLAVORS.include?(File.basename(File.dirname(path))) }
             .to_h do |path|
              flavor = File.basename(File.dirname(path))
              corpus = JSON.parse(File.read(path))
              inputs = corpus.fetch("cases", [])
                             .filter_map { |row| row["input"] if row.is_a?(Hash) && row["kind"] == "accept" }
                             .sort
              [flavor, inputs]
            end
        end

        def self.tokens_of(inputs)
          inputs.flat_map { |row| lead_token(row)&.split("/") }
                .compact.uniq
        end
      end
    end
  end
end
