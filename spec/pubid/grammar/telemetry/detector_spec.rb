# frozen_string_literal: true

require "spec_helper"

require "pubid/grammar/telemetry"

RSpec.describe Pubid::Grammar::Telemetry::Detector do
  describe ".lead_token" do
    it "matches the leading publisher token" do
      expect(described_class.lead_token("IEEE Std 1003.1")).to eq("IEEE")
      expect(described_class.lead_token("ISO/IEC 17025:2017")).to eq("ISO/IEC")
      expect(described_class.lead_token("WMO/TD-No. 123")).to eq("WMO/TD-No.")
    end

    it "refuses a non-letter leading character (mangled inputs stay unknown)" do
      expect(described_class.lead_token(" ISO 8601-1:2019")).to be_nil
      expect(described_class.lead_token("12345")).to be_nil
    end
  end

  describe ".detect" do
    let(:index) do
      {
        "iso" => ["ISO 8601-1:2019", "ISO/IEC WD TS 25025", "ISO Guide 51:1999"],
        "iec" => ["IEC 60027:2007", "ISO/IEC 17025:2017"],
        "ieee" => ["IEEE Std 1003.1"],
      }
    end

    it "ranks primary-token matches first, deterministically" do
      expect(described_class.detect("ISO 99999:2999", index)).to eq(["iso", "iec"])
    end

    it "matches the joint token for slash-joined publishers" do
      expect(described_class.detect("ISO/IEC 17025:2017", index)).to eq(%w[iec iso])
    end

    it "matches a sibling by slash-part" do
      expect(described_class.detect("IEC 60027:2007", index)).to eq(%w[iec iso])
    end

    it "finds no candidate for an unknown publisher family" do
      expect(described_class.detect("XYZZY 12:2020", index)).to be_empty
      expect(described_class.detect("12345", index)).to be_empty
    end

    it "keeps ties alphabetical" do
      tied = { "zeta" => ["ISO 9001"], "alpha" => ["ISO 14001"] }
      expect(described_class.detect("ISO 99999", tied)).to eq(%w[alpha zeta])
    end
  end

  it "excludes the data-language grammars from the identifier inventory" do
    index = described_class.build_index(File.join(PFS_REPO_ROOT, "corpora"))
    expect(index.keys).not_to include("csv", "json", "toml", "ini", "lua", "parg")
    expect(index.keys).to include("iso", "iec", "ieee")
    expect(index["iso"]).to include("ISO 8601-1:2019")
  end
end
