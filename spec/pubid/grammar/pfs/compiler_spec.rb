# frozen_string_literal: true

require "spec_helper"


RSpec.describe Pubid::Grammar::Pfs::Compiler do
  let(:doi_definition_path) do
    File.join(PFS_REPO_ROOT, "definitions/doi.pfs")
  end

  describe "the committed doi_pfs outputs" do
    it "recompiles definitions/doi.pfs byte-identically (generation is deterministic)" do
      dir = Dir.mktmpdir("pfs-golden")
      result = described_class.compile(
        doi_definition_path,
        source_rel: "definitions/doi.pfs",
        flavor_key: "doi_pfs",
        grammar_out: File.join(dir, "doi_pfs.parg"),
        artifact_out: File.join(dir, "doi_pfs.json"),
        repo_root: PFS_REPO_ROOT,
        parsanol_version: ENV.fetch("PARSANOL_VERSION", "1.3.126"),
      )

      committed = File.read(File.join(PFS_REPO_ROOT, "grammars/doi_pfs.parg"))
      expect(result.grammar_text).to eq(committed)
      expect(File.read(result.artifact_path))
        .to eq(File.read(File.join(PFS_REPO_ROOT, "artifacts/doi_pfs.json")))
    end
  end

  describe "validation demos — one rejection per rule, each cited" do
    it "rejects a definition from a newer dialect (fail-closed pfs versioning)" do
      yaml = <<~YAML
        pfs: 2
        scheme: demo
        organization: { name: Demo, publisher: DEMO, prefixes: ["DEMO "] }
        types: { base: { key: demo } }
        fields: { number: { pattern: "1*digit", kind: string } }
        grammar: { digit: "%x30-39" }
        templates: { canonical: "DEMO {number}" }
        urn: { namespace: demo, schema: { atoms: [], types: [] } }
        examples: { positives: ["DEMO 1"] }
      YAML

      expect { validate_definition(yaml) }
        .to raise_error(Pubid::Grammar::Pfs::InvalidDefinition,
                        /pfs: definition declares pfs: 2; this compiler speaks pfs: 1/)
    end

    it "rejects a reserved token claimed as a type key" do
      yaml = File.read(doi_definition_path).sub(/key: doi$/, "key: amd")

      expect { validate_definition(yaml) }
        .to raise_error(
          Pubid::Grammar::Pfs::InvalidDefinition,
          %r{types\.resource\.key: reserved token "amd" — `ed`, `amd` and `cor` belong},
        )
    end

    it "rejects a reserved token claimed as a stage abbreviation" do
      yaml = File.read(doi_definition_path).sub('abbr: ["DOI"]', 'abbr: ["ED"]')

      expect { validate_definition(yaml) }
        .to raise_error(Pubid::Grammar::Pfs::InvalidDefinition, /types\.resource\.stage\.abbr\[0\]: reserved token "ED"/)
    end

    it "rejects overlapping alternates (a structurally identical accept form)" do
      yaml = File.read(doi_definition_path)
        .sub(/  alternates:\n    - '\[url_prefix\].*'\n/m,
             "  alternates:\n    - '\"doi:\" {prefix} \"/\" {suffix}'\n")

      expect { validate_definition(yaml) }
        .to raise_error(
          Pubid::Grammar::Pfs::InvalidDefinition,
          /templates\.alternates\[0\]: ambiguity: alternate is structurally identical to the canonical/,
        )
    end

    it "rejects two types with identical token sets (same key)" do
      yaml = File.read(doi_definition_path)
        .sub(/^  resource:\n    key: doi\n    title: "DOI"\n    short: "DOI"\n    tag: "pubid:doi:resource"\n    stage:\n      code: pubdoi\n      stage_code: published\n      abbr: \["DOI"\]\n/m, "")
        .sub(/^types:\n/m, <<~YAML)
          types:
            resource:
              key: doi
              title: "DOI"
              short: "DOI"
              tag: "pubid:doi:resource"
            twin:
              key: doi
              title: "DOI twin"
        YAML

      expect { validate_definition(yaml) }
        .to raise_error(
          Pubid::Grammar::Pfs::InvalidDefinition,
          /types\.twin\.key: ambiguity: type key "doi" is already claimed by type "resource"/,
        )
    end

    it "rejects duplicate field names (the strict loader never lets YAML's " \
       "last-key-wins hide a copy-paste)" do
      yaml = <<~YAML
        pfs: 1
        scheme: demo
        organization: { name: Demo, publisher: DEMO, prefixes: ["DEMO "] }
        types: { base: { key: demo } }
        fields:
          number:
            pattern: "1*digit"
            kind: string
          number:
            pattern: "2*digit"
            kind: string
        grammar: { digit: "%x30-39" }
        templates: { canonical: "DEMO {number}" }
        urn: { namespace: demo, schema: { atoms: [], types: [] } }
        examples: { positives: ["DEMO 1"] }
      YAML

      expect { validate_definition(yaml) }
        .to raise_error(Pubid::Grammar::Pfs::Loader::DuplicateKeyError, /duplicate key "number"/)
    end

    it "rejects an unknown top-level key (a key this compiler does not know " \
       "means a dialect newer than pfs:1)" do
      yaml = File.read(doi_definition_path).sub(/^scheme: doi\n/, "scheme: doi\nupdate_codes: {}\n")

      expect { validate_definition(yaml) }
        .to raise_error(Pubid::Grammar::Pfs::InvalidDefinition, /unknown key\(s\) "update_codes"/)
    end

    it "rejects a positive example that does not parse, citing the row" do
      yaml = File.read(doi_definition_path)
        .sub('- input: "doi:10.1000/182"', '- input: "doi:10.X/182"')

      expect { compile_definition(yaml) }
        .to raise_error(
          Pubid::Grammar::Pfs::ExampleFailure,
          /examples\.positives\[0\]: input "doi:10.X\/182" does not parse/,
        )
    end

    it "rejects a negative example that parses, citing the row" do
      yaml = File.read(doi_definition_path).sub('    - "doi:"', '    - "doi:10.1000/x"')

      expect { compile_definition(yaml) }
        .to raise_error(
          Pubid::Grammar::Pfs::ExampleFailure,
          /examples\.negatives\[0\]: negative input "doi:10.1000\/x" parses/,
        )
    end

    it "rejects a declared render the canonical template does not produce" do
      yaml = File.read(doi_definition_path)
        .sub('      renders: "doi:10.1000/182"', '      renders: "doi:10.1000/183"')

      expect { compile_definition(yaml) }
        .to raise_error(
          Pubid::Grammar::Pfs::ExampleFailure,
          /renders "doi:10.1000\/182" under the canonical template, not the declared/,
        )
    end
  end
end
