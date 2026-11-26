# frozen_string_literal: true

require "spec_helper"

require "pubid/grammar/telemetry"
require "tempfile"

RSpec.describe Pubid::Grammar::Telemetry::Intake do
  subject(:result) { described_class.run(path) }

  let(:path) do
    file = Tempfile.new(["intake", ".jsonl"])
    file.write(text)
    file.close
    file.path
  end

  let(:text) do
    <<~JSONL
      {"input":"ISO 8601-1:2019","consumer":"relaton-api-js","context":"resolve","timestamp":"2026-11-20T10:00:00Z"}
      {"input":"ISO 8601-1:2019","consumer":"mn-api","context":"export","timestamp":"2026-11-21T08:30:00Z"}
      {"input":"ISO 8601-1:2019","consumer":"mn-api","context":"export","timestamp":"2026-11-19T00:00:00Z"}

      {"input":"IEEE Std 1003.1","consumer":"relaton-api-js","timestamp":"2026-11-20T10:00:00Z"}
      not valid json
      {"consumer":"c","timestamp":"2026-11-20T10:00:00Z"}
    JSONL
  end

  it "deduplicates by the exact input, folding occurrences" do
    row = result.rows.find { |r| r.input == "ISO 8601-1:2019" }
    expect(row.occurrences).to eq(3)
    expect(result.rows.size).to eq(2)
  end

  it "folds the reporting consumers, sorted and unique" do
    row = result.rows.find { |r| r.input == "ISO 8601-1:2019" }
    expect(row.consumers).to eq(%w[mn-api relaton-api-js])
  end

  it "folds the contexts" do
    row = result.rows.find { |r| r.input == "ISO 8601-1:2019" }
    expect(row.contexts).to eq(%w[export resolve])
  end

  it "spans the first and last seen timestamps across duplicates" do
    row = result.rows.find { |r| r.input == "ISO 8601-1:2019" }
    expect(row.first_seen).to eq(Time.iso8601("2026-11-19T00:00:00Z"))
    expect(row.last_seen).to eq(Time.iso8601("2026-11-21T08:30:00Z"))
  end

  it "records the contributing line numbers" do
    row = result.rows.find { |r| r.input == "ISO 8601-1:2019" }
    expect(row.lines).to eq([1, 2, 3])
  end

  it "skips blank lines" do
    expect(result.line_count).to eq(7)
  end

  it "surfaces malformed lines as intake errors, never drops them" do
    expect(result.errors).to contain_exactly(
      { "line" => 6, "error" => a_string_including("not valid JSON") },
      { "line" => 7, "error" => a_string_including('"input" must be') }
    )
  end

  it "keeps single-record rows intact" do
    row = result.rows.find { |r| r.input == "IEEE Std 1003.1" }
    expect(row.occurrences).to eq(1)
    expect(row.consumers).to eq(["relaton-api-js"])
  end
end
