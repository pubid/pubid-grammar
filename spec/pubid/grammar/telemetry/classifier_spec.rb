# frozen_string_literal: true

require "spec_helper"

require "pubid/grammar/telemetry"

RSpec.describe Pubid::Grammar::Telemetry::Classifier do
  # The parse outcomes are real Runtime::Outcome values, injected through
  # the probe — no engine needed for the decision rules.
  def accepts = Pubid::Grammar::Telemetry::Runtime::Outcome.success

  def rejects(message = "Failed to match") =
    Pubid::Grammar::Telemetry::Runtime::Outcome.failure(message)

  def evidence(candidates:, input:, raw: nil)
    Pubid::Grammar::Telemetry::Classifier::Evidence.new(
      candidates: candidates, raw: raw,
      normalized_input: Pubid::Grammar::Telemetry::Normalizer.normalize(input)
    )
  end

  def classify(input:, candidates:, parses: {}, known_good: {}, raw: nil)
    probe = ->(flavor, string) do
      outcome = parses.fetch([flavor, string], nil)
      outcome || (parses.key?(flavor) ? parses[flavor] : rejects)
    end
    described_class.classify(
      input: input,
      evidence: evidence(candidates: candidates, input: input, raw: raw),
      known_good: known_good, probe: probe
    )
  end

  it "classifies a reference-accepted miss as a consumer bug" do
    verdict = classify(input: "ISO 8601-1:2019", candidates: %w[iso iec],
                       parses: { "iso" => accepts })
    expect(verdict.classification).to eq(:consumer_bug)
    expect(verdict.flavor).to eq("iso")
    expect(verdict.reason).to include("stale")
  end

  it "classifies a normalization-recovered miss as a consumer bug" do
    verdict = classify(input: " ISO 8601-1:2019 ", candidates: ["iso"],
                       parses: { ["iso", "ISO 8601-1:2019"] => accepts })
    expect(verdict.classification).to eq(:consumer_bug)
    expect(verdict.normalized).to eq("ISO 8601-1:2019")
    expect(verdict.reason).to include("normalization")
  end

  it "classifies an unmatched miss as a new flavor need" do
    verdict = classify(input: "XYZZY 12:2020", candidates: [])
    expect(verdict.classification).to eq(:new_flavor)
    expect(verdict.flavor).to be_nil
    expect(verdict.flavor_name).to eq("unknown")
  end

  it "classifies a frozen accept case the artifact now rejects as a parse bug" do
    verdict = classify(input: "ISO 8601-1:2019", candidates: ["iso"],
                       parses: { "iso" => rejects },
                       known_good: { "iso" => ["ISO 8601-1:2019"].to_set })
    expect(verdict.classification).to eq(:parse_bug)
    expect(verdict.flavor).to eq("iso")
    expect(verdict.known_good).to be(true)
    expect(verdict.reason).to include("regression")
  end

  it "classifies a covered-family miss as a grammar gap" do
    verdict = classify(input: "ISO 99999:2999 (withdrawn)", candidates: ["iso"],
                       parses: { "iso" => rejects },
                       known_good: { "iso" => ["ISO 8601-1:2019"].to_set })
    expect(verdict.classification).to eq(:grammar_gap)
    expect(verdict.flavor).to eq("iso")
    expect(verdict.reason).to include("grammar round")
  end

  it "carries the primary candidate's parse error into the verdict" do
    verdict = classify(input: "ISO 99999:2999 (withdrawn)", candidates: ["iso"],
                       parses: { "iso" => rejects },
                       known_good: {},
                       raw: rejects("Failed to match at char 11"))
    expect(verdict.parse_error).to include("char 11")
  end

  it "prefers the consumer-bug verdict over the parse-bug verdict" do
    # reference accepts (consumer bug wins) even though the input is
    # also a frozen accept case
    verdict = classify(input: "ISO 8601-1:2019", candidates: ["iso"],
                       parses: { "iso" => accepts },
                       known_good: { "iso" => ["ISO 8601-1:2019"].to_set })
    expect(verdict.classification).to eq(:consumer_bug)
  end

  it "checks the known-good evidence per candidate flavor" do
    verdict = classify(input: "IEEE Std 1003.1", candidates: %w[iso ieee],
                       parses: { "iso" => rejects, "ieee" => rejects },
                       known_good: { "ieee" => ["IEEE Std 1003.1"].to_set })
    expect(verdict.classification).to eq(:parse_bug)
    expect(verdict.flavor).to eq("ieee")
  end

  it "orders the taxonomy regressions first" do
    expect(described_class::ORDER.first).to eq(:parse_bug)
    expect(described_class::ORDER.last).to eq(:new_flavor)
  end
end
