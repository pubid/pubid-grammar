# frozen_string_literal: true

require "spec_helper"

# `pfs capture` — the lossless wizard substrate (issue #152): the intake
# preserves the captured strings verbatim, the draft carries them in the
# REQUIRED format, and the round-trip is verified against the strict
# loader (the compiler's own front door).
RSpec.describe Pubid::Grammar::Pfs::Capture do
  describe "read_inputs" do
    it "captures one identifier per line, order preserved" do
      inputs = described_class.read_inputs(<<~TEXT)
        BS EN ISO 8601:2019

        # a comment
        PAS 003-1:2020
        BS 10125:2014+A1:2016
      TEXT
      expect(inputs).to eq([
        "BS EN ISO 8601:2019", "PAS 003-1:2020", "BS 10125:2014+A1:2016",
      ])
    end

    it "returns an empty list for blank text" do
      expect(described_class.read_inputs("\n\n# only comments\n")).to eq([])
    end
  end

  describe "yaml_string" do
    it "escapes quotes and backslashes losslessly" do
      value = 'weird "quoted" id\\path'
      round = Pubid::Grammar::Pfs::Loader.load_text("key: #{described_class.yaml_string(value)}")
      expect(round["key"]).to eq(value)
    end

    it "preserves UTF-8 verbatim" do
      value = "ÖNORM EN 1987-1"
      round = Pubid::Grammar::Pfs::Loader.load_text("key: #{described_class.yaml_string(value)}")
      expect(round["key"]).to eq(value)
    end

    it "fails closed on control characters" do
      expect { described_class.yaml_string("bad \x01 char") }
        .to raise_error(Pubid::Grammar::Pfs::Error, /control character/)
    end
  end

  describe "the draft" do
    let(:inputs) do
      ["BS EN ISO 8601:2019", 'BS "quoted" 1', "PAS 003-1:2020"]
    end
    let(:draft) do
      described_class.draft(scheme: "bsnl", title: "BS National Line",
                            publisher: "BS", inputs: inputs)
    end

    it "carries the captured rows in the REQUIRED format, lossless" do
      raw = Pubid::Grammar::Pfs::Loader.load_text(draft)
      rows = raw.dig("examples", "positives")
      expect(rows).to eq(inputs.map { |i| { "input" => i, "renders" => i } })
    end

    it "declares the schema draft surface (scheme, org, grammar, templates)" do
      raw = Pubid::Grammar::Pfs::Loader.load_text(draft)
      expect(raw["scheme"]).to eq("bsnl")
      expect(raw.dig("organization", "publisher")).to eq("BS")
      expect(raw["grammar"]).to be_a(Hash)
      expect(raw.dig("templates", "canonical")).to be_a(String)
      expect(raw.dig("examples", "negatives")).not_to be_empty
    end

    it "is clean under the linter (the loop starts from a diagnosable state)" do
      dir = Dir.mktmpdir("pfs-capture")
      path = File.join(dir, "bsnl.pfs")
      File.binwrite(path, draft)
      expect(Pubid::Grammar::Pfs::Linter.run(path)).to be_empty
    end

    it "refuses a quote-bearing title" do
      expect do
        described_class.draft(scheme: "bsnl", title: 'Bad "Title"',
                              publisher: "BS", inputs: inputs)
      end.to raise_error(Pubid::Grammar::Pfs::Error, /quotes/)
    end
  end

  describe "verify_lossless" do
    it "raises when the emitted file loses a row" do
      dir = Dir.mktmpdir("pfs-capture")
      path = File.join(dir, "lossy.pfs")
      File.binwrite(path, described_class.draft(scheme: "bsnl", title: "BSNL",
                                                publisher: "BS",
                                                inputs: ["BS 1", "BS 2"]))
      expect { described_class.verify_lossless(path, ["BS 1", "BS 2", "BS 3"]) }
        .to raise_error(Pubid::Grammar::Pfs::Error, /not lossless/)
    end
  end
end
