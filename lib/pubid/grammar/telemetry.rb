# frozen_string_literal: true

# The grammar-miss telemetry intake (pubid/pubid-grammar#150).
#
# Consumer systems (relaton-api-js first) report identifiers their runtime
# could not resolve as JSON lines ({input, consumer, context, timestamp}).
# This intake deduplicates those misses, classifies each one against the
# grammar inventory (new flavor / grammar gap / parse bug / consumer bug),
# and emits the classified report plus candidate test rows shaped like
# corpus cases so the round pipeline can pick them up — closing
# relaton#604's invariant ("every unparseable id = a grammar round") from
# the consumer side.
#
# Contract doc: docs/TELEMETRY-INTAKE.md (the consumer-facing spelling).
module Pubid
  module Grammar
    module Telemetry
      # The miss-report wire format this intake reads (the value of each
      # miss line's "format"-side contract; consumers pin this spelling).
      MISS_FORMAT = "pubid-grammar-miss/v1"

      # The triage report wire format this intake writes.
      TRIAGE_FORMAT = "pubid-grammar-telemetry-triage/v1"

      autoload :Miss, "#{__dir__}/telemetry/miss"
      autoload :Intake, "#{__dir__}/telemetry/intake"
      autoload :Detector, "#{__dir__}/telemetry/detector"
      autoload :Normalizer, "#{__dir__}/telemetry/normalizer"
      autoload :Runtime, "#{__dir__}/telemetry/runtime"
      autoload :Classifier, "#{__dir__}/telemetry/classifier"
      autoload :Report, "#{__dir__}/telemetry/report"
      autoload :Candidates, "#{__dir__}/telemetry/candidates"
      autoload :Triage, "#{__dir__}/telemetry/triage"
    end
  end
end
