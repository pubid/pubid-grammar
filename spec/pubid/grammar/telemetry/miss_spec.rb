# frozen_string_literal: true

require "spec_helper"

require "pubid/grammar/telemetry"

RSpec.describe Pubid::Grammar::Telemetry::Miss do
  subject(:miss) do
    described_class.parse(line, line_number: 3)
  end

  let(:line) do
    '{"input":"ISO 8601-1:2019","consumer":"relaton-api-js",' \
      '"context":"resolve","timestamp":"2026-11-20T10:00:00Z"}'
  end

  it "parses the contract fields" do
    expect(miss.input).to eq("ISO 8601-1:2019")
    expect(miss.consumer).to eq("relaton-api-js")
    expect(miss.context).to eq("resolve")
    expect(miss.timestamp).to eq("2026-11-20T10:00:00Z")
    expect(miss.line_number).to eq(3)
  end

  it "keeps the input exactly as reported (mangles are evidence)" do
    parsed = described_class.parse(
      '{"input":"  ISO&nbsp;8601 ","consumer":"c","timestamp":"2026-11-20T10:00:00Z"}',
      line_number: 1
    )
    expect(parsed.input).to eq("  ISO&nbsp;8601 ")
  end

  it "allows a missing context" do
    parsed = described_class.parse(
      '{"input":"x","consumer":"c","timestamp":"2026-11-20T10:00:00Z"}',
      line_number: 1
    )
    expect(parsed.context).to be_nil
  end

  it "tolerates unknown extra keys (forward compatibility)" do
    parsed = described_class.parse(
      '{"input":"x","consumer":"c","timestamp":"2026-11-20T10:00:00Z",' \
        '"extra":{"depth":2}}',
      line_number: 1
    )
    expect(parsed.input).to eq("x")
  end

  it "accepts ISO8601 offsets and fractional seconds" do
    parsed = described_class.parse(
      '{"input":"x","consumer":"c","timestamp":"2026-11-20T10:00:00.500+02:00"}',
      line_number: 1
    )
    expect(Time.iso8601(parsed.timestamp).utc_offset).to eq(7200)
  end

  describe "rejections" do
    def parse(text)
      described_class.parse(text, line_number: 7)
    rescue described_class::Invalid => e
      e
    end

    it "rejects a non-JSON line, carrying the line number" do
      error = parse("not json")
      expect(error).to be_a(described_class::Invalid)
      expect(error.line_number).to eq(7)
    end

    it "rejects a JSON array (not an object)" do
      expect(parse("[1,2]").message).to include("not a JSON object")
    end

    it "rejects a missing input" do
      expect(parse('{"consumer":"c","timestamp":"2026-11-20T10:00:00Z"}').message)
        .to include('"input" must be')
    end

    it "rejects an empty input" do
      expect(parse('{"input":"","consumer":"c","timestamp":"2026-11-20T10:00:00Z"}').message)
        .to include('"input" must be')
    end

    it "rejects a missing consumer" do
      expect(parse('{"input":"x","timestamp":"2026-11-20T10:00:00Z"}').message)
        .to include('"consumer" must be')
    end

    it "rejects a missing timestamp" do
      expect(parse('{"input":"x","consumer":"c"}').message)
        .to include("timestamp must be")
    end

    it "rejects a non-ISO8601 timestamp" do
      expect(parse('{"input":"x","consumer":"c","timestamp":"yesterday"}').message)
        .to include("not ISO8601")
    end

    it "rejects a non-string context" do
      expect(parse('{"input":"x","consumer":"c","context":4,' \
                     '"timestamp":"2026-11-20T10:00:00Z"}').message)
        .to include('"context" must be')
    end
  end
end
