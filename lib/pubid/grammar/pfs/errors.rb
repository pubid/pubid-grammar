# frozen_string_literal: true

module Pubid
  module Grammar
    module Pfs
      # Base class for PFS compiler failures.
      class Error < StandardError; end

      # A definition the compiler refuses. Every rejection cites the rule
      # it failed — the PFS section path (or the example row) is carried in
      # #rule and prefixed into the message, so a wizard (or a human) can
      # jump straight to the offending declaration.
      class InvalidDefinition < Error
        attr_reader :rule

        def initialize(rule, message = nil)
          @rule = rule
          super(message ? "#{rule}: #{message}" : rule.to_s)
        end
      end

      # A REQUIRED example row failed at compile time (a positive that does
      # not parse, a negative that parses, or a `renders:` that the
      # canonical template does not produce). The rule is the row
      # ("examples.positives[2]"), and the message carries the input.
      class ExampleFailure < InvalidDefinition; end
    end
  end
end
