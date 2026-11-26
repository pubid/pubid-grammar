# frozen_string_literal: true

require "spec_helper"

# `pfs new` — the scaffold (issue #152). The contract: the generated
# definition compiles + verifies GREEN immediately, binds the six module
# library modules, carries the REQUIRED stub examples and the wiring in
# its header. Scaffolding that does not run is debt — the green proof
# below runs the REAL pipeline.
RSpec.describe Pubid::Grammar::Pfs::Scaffold do
  let(:names) do
    { org: "Acme Standards", scheme: "acme", title: "Acme Standards",
      publisher: "ACME", prefixes: ["ACME"] }
  end

  describe "derive_names" do
    it "snake_cases the scheme and uppercases the publisher" do
      derived = described_class.derive_names("Dot Org Test")
      expect(derived[:scheme]).to eq("dot_org_test")
      expect(derived[:publisher]).to eq("DOTORGTEST")
      expect(derived[:title]).to eq("Dot Org Test")
    end

    it "refuses an organization that yields no valid scheme key" do
      expect { described_class.derive_names("123") }
        .to raise_error(Pubid::Grammar::Pfs::Error, /no valid scheme key/)
      expect { described_class.derive_names("---") }
        .to raise_error(Pubid::Grammar::Pfs::Error, /no valid scheme key/)
    end
  end

  describe "generate" do
    let(:text) do
      described_class.generate(**names)
    end

    it "binds all six module library modules at the library version" do
      raw = Pubid::Grammar::Pfs::Loader.load_text(text)
      bound = raw["modules"].map { |m| m["module"] }
      expect(bound).to contain_exactly(
        "iso.inner", "iec.inner", "en.overlay", "national.prefix",
        "supplements.core", "edition.core",
      )
      national = raw["modules"].find { |m| m["module"] == "national.prefix" }
      expect(national["parameters"]["prefixes"]).to eq(["ACME"])
      expect(national["version"]).to eq(described_class::LIBRARY_VERSION)
    end

    it "carries the REQUIRED examples (positives with renders + negatives)" do
      raw = Pubid::Grammar::Pfs::Loader.load_text(text)
      positives = raw.dig("examples", "positives")
      negatives = raw.dig("examples", "negatives")
      expect(positives.size).to be >= 3
      expect(positives).to all(include("input", "renders"))
      expect(negatives).not_to be_empty
    end

    it "documents the wiring in the header (compile, round, doctor, cutover)" do
      expect(text).to include("scripts/pfs compile")
      expect(text).to include("rake contracts:regen")
      expect(text).to include("scripts/pfs doctor")
      expect(text).to include("docs/CUTOVER.md")
    end

    it "supplies edition_space (the edition.core demand)" do
      raw = Pubid::Grammar::Pfs::Loader.load_text(text)
      expect(raw.dig("grammar", "edition_space")).to eq('" "')
    end

    it "refuses a reserved publisher token" do
      expect do
        described_class.generate(**names, publisher: "ED", prefixes: ["ED"])
      end.to raise_error(Pubid::Grammar::Pfs::InvalidDefinition, /reserved token/)
    end

    it "refuses a publisher colliding with a module's claimed token" do
      expect do
        described_class.generate(**names, publisher: "ISO", prefixes: ["ISO"])
      end.to raise_error(Pubid::Grammar::Pfs::InvalidDefinition, /iso\.inner.*claimed token/)
    end

    it "refuses quote-bearing titles (the emission is plain YAML scalars)" do
      expect do
        described_class.generate(**names, title: 'Acme "Std"')
      end.to raise_error(Pubid::Grammar::Pfs::Error, /quotes/)
    end
  end

  # THE green proof: the generated definition compiles + verifies through
  # the real pipeline — scaffold, not sketch.
  it "compiles and verifies green, immediately" do
    dir = Dir.mktmpdir("pfs-scaffold")
    path = File.join(dir, "acme.pfs")
    File.binwrite(path, described_class.generate(**names))

    result = Pubid::Grammar::Pfs::Compiler.compile(
      path,
      source_rel: "definitions/acme.pfs",
      flavor_key: "acme_pfs",
      grammar_out: File.join(dir, "acme_pfs.parg"),
      artifact_out: File.join(dir, "acme_pfs.json"),
      repo_root: PFS_REPO_ROOT,
      parsanol_version: ENV.fetch("PARSANOL_VERSION", "1.5.1.0"),
    )

    # The stub examples verified against the baked artifact (compile
    # raises ExampleFailure on any miss — reaching here IS the proof).
    expect(result.definition.examples[:positives].size).to eq(5)
    expect(result.envelope["compiler_version"])
      .to eq(ENV.fetch("PARSANOL_VERSION", "1.5.1.0"))
  end

  it "compiles green with multiple head tokens (the parameterized NSB form)" do
    dir = Dir.mktmpdir("pfs-scaffold")
    path = File.join(dir, "acme.pfs")
    File.binwrite(path, described_class.generate(
                          **names.merge(prefixes: %w[ACME ACSI])
                        ))

    expect do
      Pubid::Grammar::Pfs::Compiler.compile(
        path,
        source_rel: "definitions/acme.pfs",
        flavor_key: "acme_pfs",
        grammar_out: File.join(dir, "acme_pfs.parg"),
        artifact_out: File.join(dir, "acme_pfs.json"),
        repo_root: PFS_REPO_ROOT,
        parsanol_version: ENV.fetch("PARSANOL_VERSION", "1.5.1.0"),
      )
    end.not_to raise_error
  end

  it "is clean under the linter (the scaffold is its own first lint subject)" do
    dir = Dir.mktmpdir("pfs-scaffold")
    path = File.join(dir, "acme.pfs")
    File.binwrite(path, described_class.generate(**names))

    expect(Pubid::Grammar::Pfs::Linter.run(path)).to be_empty
  end
end
