# frozen_string_literal: true

require "spec_helper"

require "json"
require "time"
require "pubid/grammar/telemetry"
require "tempfile"

# The intake exercised END-TO-END over the committed fixture miss file:
# the real grammar inventory, the real artifacts, the real pipeline —
# miss file in, classified report + candidate rows out.
RSpec.describe "the telemetry intake end-to-end" do
  let(:miss_file) do
    File.join(PFS_REPO_ROOT, "spec/fixtures/telemetry/misses.jsonl")
  end

  let(:report_path) do
    File.join(Dir.mktmpdir("telemetry-e2e"), "misses.report.json")
  end

  let(:candidates_path) do
    File.join(File.dirname(report_path), "misses.candidates.jsonl")
  end

  let(:engine) { Pubid::Grammar::Telemetry::Runtime.new(repo_root: PFS_REPO_ROOT) }

  let(:result) do
    Pubid::Grammar::Telemetry::Triage.run(
      miss_file, engine: engine, generated_at: Time.iso8601("2026-11-26T00:00:00Z"),
                 report_out: report_path, candidates_out: candidates_path
    )
  end

  let(:report) { JSON.parse(File.read(result.report_path)) }
  let(:candidates) do
    File.readlines(result.candidates_path, chomp: true).map { |l| JSON.parse(l) }
  end

  it "writes the triage-format report" do
    expect(report["format"]).to eq("pubid-grammar-telemetry-triage/v1")
    expect(report["generated_at"]).to eq("2026-11-26T00:00:00Z")
  end

  it "accounts for every line: records, misses, intake errors" do
    expect(report["source"]).to eq(
      "file" => miss_file, "lines" => 8, "records" => 6,
      "misses" => 5, "intake_errors" => 2
    )
    expect(report["intake_errors"].map { |e| e["line"] }).to eq([7, 8])
  end

  it "deduplicates the repeated miss across consumers" do
    row = report["rows"].find { |r| r["input"] == "ISO 8601-1:2019" }
    expect(row["occurrences"]).to eq(2)
    expect(row["consumers"]).to eq(%w[mn-api relaton-api-js])
    expect(row["first_seen"]).to eq("2026-11-20T10:00:00Z")
    expect(row["last_seen"]).to eq("2026-11-21T08:30:00Z")
  end

  it "classifies the reference-accepted miss as a consumer bug" do
    row = report["rows"].find { |r| r["input"] == "ISO 8601-1:2019" }
    expect(row["classification"]).to eq("consumer_bug")
    expect(row["flavor"]).to eq("iso")
  end

  it "classifies the mangled miss through normalization" do
    row = report["rows"].find { |r| r["input"] == " ISO 8601-1:2019" }
    expect(row["classification"]).to eq("consumer_bug")
    expect(row["flavor"]).to eq("iso")
    expect(row["normalized"]).to eq("ISO 8601-1:2019")
  end

  it "classifies the joint-publisher miss through the iec grammar" do
    row = report["rows"].find { |r| r["input"] == "ISO/IEC 17025:2017/PAS 1" }
    expect(row["classification"]).to eq("consumer_bug")
    expect(row["flavor"]).to eq("iec")
  end

  it "classifies the uncovered iso shape as a grammar gap" do
    row = report["rows"].find { |r| r["input"] == "ISO 99999:2999 (withdrawn)" }
    expect(row["classification"]).to eq("grammar_gap")
    expect(row["flavor"]).to eq("iso")
    expect(row["parse_error"]).to include("Failed to match")
  end

  it "surfaces the unknown shape fail-closed as a new flavor" do
    row = report["rows"].find { |r| r["input"] == "XYZZY 12:2020" }
    expect(row["classification"]).to eq("new_flavor")
    expect(row["flavor"]).to eq("unknown")
  end

  it "summarizes by classification and flavor" do
    expect(report["summary"]["by_classification"]).to eq(
      "parse_bug" => 0, "consumer_bug" => 3, "grammar_gap" => 1, "new_flavor" => 1
    )
    expect(report["summary"]["by_flavor"]).to eq(
      "iec" => 1, "iso" => 3, "unknown" => 1
    )
  end

  it "emits candidate test rows in the corpus-case core shape" do
    expect(candidates.size).to eq(5)
    row = candidates.find { |r| r["input"] == "ISO 99999:2999 (withdrawn)" }
    expect(row).to eq(
      "input" => "ISO 99999:2999 (withdrawn)", "kind" => "accept",
      "flavor" => "iso", "classification" => "grammar_gap",
      "consumers" => ["mn-api"], "occurrences" => 1,
      "first_seen" => "2026-11-21T00:30:00Z"
    )
  end

  it "keeps the unknown flavor in the candidate queue (fail-closed)" do
    row = candidates.find { |r| r["input"] == "XYZZY 12:2020" }
    expect(row["flavor"]).to eq("unknown")
    expect(row["kind"]).to eq("accept")
  end

  it "orders candidate rows by the taxonomy, regressions first" do
    expect(candidates.map { |r| r["classification"] })
      .to eq(%w[consumer_bug consumer_bug consumer_bug grammar_gap new_flavor])
  end
end
