# frozen_string_literal: true

require "spec_helper"


RSpec.describe Pubid::Grammar::Pfs::Compiler do
  let(:doi_definition_path) do
    File.join(PFS_REPO_ROOT, "definitions/doi.pfs")
  end

  let(:etsi_definition_path) do
    File.join(PFS_REPO_ROOT, "definitions/etsi.pfs")
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

  describe "the committed etsi_pfs outputs (pubid#706 phase 2)" do
    it "recompiles definitions/etsi.pfs byte-identically (generation is deterministic)" do
      dir = Dir.mktmpdir("pfs-golden")
      result = described_class.compile(
        etsi_definition_path,
        source_rel: "definitions/etsi.pfs",
        flavor_key: "etsi_pfs",
        grammar_out: File.join(dir, "etsi_pfs.parg"),
        artifact_out: File.join(dir, "etsi_pfs.json"),
        repo_root: PFS_REPO_ROOT,
        parsanol_version: ENV.fetch("PARSANOL_VERSION", "1.3.126"),
      )

      committed = File.read(File.join(PFS_REPO_ROOT, "grammars/etsi_pfs.parg"))
      expect(result.grammar_text).to eq(committed)
      expect(File.read(result.artifact_path))
        .to eq(File.read(File.join(PFS_REPO_ROOT, "artifacts/etsi_pfs.json")))
    end

    it "bakes the embedded test panel into the artifact (accepts, rejects, captures)" do
      artifact = Parsanol::PARG::Artifact.new(
        JSON.parse(File.read(File.join(PFS_REPO_ROOT, "artifacts/etsi_pfs.json"))),
        nil, File.join(PFS_REPO_ROOT, "tables"),
        imports_dir: File.join(PFS_REPO_ROOT, "grammars"),
      )
      expect(artifact.run_tests).to be_empty
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

  describe "etsi-specific rejection demos (pubid#706 phase 2)" do
    it "rejects a negative that the etsi grammar accepts (accept/reject mismatch)" do
      yaml = File.read(etsi_definition_path)
        .sub('    - "ETSI EN"', '    - "ETSI EN 300 175"')

      expect { compile_definition(yaml) }
        .to raise_error(
          Pubid::Grammar::Pfs::ExampleFailure,
          /examples\.negatives\[2\]: negative input "ETSI EN 300 175" parses/,
        )
    end

    it "rejects an int-kind field (int patterns are a later extension) — " \
       "the gap that keeps the supplement ordinal out of pfs:1" do
      yaml = File.read(etsi_definition_path)
        .sub(%r{^  year:\n    pattern: "4digit"\n    kind: string$},
             "  year:\n    pattern: \"4digit\"\n    kind: integer")

      expect { validate_definition(yaml) }
        .to raise_error(
          Pubid::Grammar::Pfs::InvalidDefinition,
          /fields\.year\.kind: unsupported field kind "integer" — pfs:1 carries `string`/,
        )
    end

    it "accepts the int-kind URN core (phase 3 gap d) and emits the coded " \
       "schema's `core: [[\"number\", :int]]` shape" do
      result = compile_definition(File.read(etsi_definition_path), flavor_key: "etsi_pfs")

      schema = result.ruby_files
        .find { |path| path.end_with?("etsi_pfs/pubid_urn_schema.rb") }
        .then { |path| File.read(path) }
      expect(schema).to include('type "pubid:etsi:amendment", "amd", core: [["number", :int]]')
      expect(schema).to include('type "pubid:etsi:corrigendum", "cor", core: [["number", :int]]')
      expect(schema).to include('type "pubid:etsi:etsi-standard", "es", core: []')
    end

    it "rejects an unknown core kind (fail-closed: only string and int exist)" do
      yaml = File.read(etsi_definition_path)
        .sub("- { type: \"pubid:etsi:amendment\", token: amd, core: [[number, int]] }",
             "- { type: \"pubid:etsi:amendment\", token: amd, core: [[number, float]] }")

      expect { validate_definition(yaml) }
        .to raise_error(
          Pubid::Grammar::Pfs::InvalidDefinition,
          /urn\.schema\.types\[1\]: unsupported core kind "float"/,
        )
    end

    it "rejects a render face that claims a tail the input did not carry " \
       "(the render verification pins every conditional segment, cited on the row)" do
      yaml = File.read(etsi_definition_path)
        .sub(%{- input: "ETSI EN 300 175"
      renders: "ETSI EN 300 175"},
             %{- input: "ETSI EN 300 175"
      renders: "ETSI EN 300 175 V1.5.1"})

      expect { compile_definition(yaml) }
        .to raise_error(
          Pubid::Grammar::Pfs::ExampleFailure,
          /renders "ETSI EN 300 175" under the canonical template, not the declared/,
        )
    end

    it "rejects a template referencing an undeclared grammar rule" do
      yaml = File.read(etsi_definition_path)
        .sub(' [{supplements}] [" V" {version} / " ed." {edition}] [" (" {year} "-" {month} ")"]\'',
             ' [{supplements}] [" V" {version} / " ed." {edition}] [" (" {year} "-" letter "-" {month} ")"]\'')

      expect { validate_definition(yaml) }
        .to raise_error(
          Pubid::Grammar::Pfs::InvalidDefinition,
          %r{templates\.alternates\[0\]: unknown grammar rule letter},
        )
    end

    it "rejects a grammar fragment carrying an unnamed capture (the " \
       "named-segments rule: every segment carries a semantic name)" do
      yaml = File.read(doi_definition_path)
        .sub(%q{suffix_char: "%x30-39 / %x41-5A / %x61-7A / %x2E / %x5F / %x2D / %x2F / %x28 / %x29"},
             %q{suffix_char: '("%x30-39" / "%x41-5A")'})

      expect { validate_definition(yaml) }
        .to raise_error(
          Pubid::Grammar::Pfs::InvalidDefinition,
          /grammar\.suffix_char: unnamed capture: every grammar segment must carry a semantic/,
        )
    end

    it "accepts a fragment whose captures are all named, and names every " \
       "generated rule semantically (number, part, supplement_kind, ...)" do
      result = compile_definition(File.read(etsi_definition_path), flavor_key: "etsi_pfs")
      grammar = File.read(result.grammar_path)

      # The compiler-generated rules all carry the scheme-prefixed
      # semantic names; the definition's own fragments carry theirs.
      grammar.scan(/^\s{2}(etsi_\w+)\s*=/).flatten.each do |rule|
        expect(rule).to match(/\Aetsi_[a-z0-9_]+\z/),
          "generated rule #{rule.inspect} carries no semantic name"
      end
      %w[etsi_type etsi_number etsi_part etsi_parts etsi_supplement
         etsi_supplement_kind etsi_supplement_number etsi_supplements].each do |rule|
        expect(grammar).to match(/^\s{2}#{rule} = /),
          "the grammar carries no #{rule} rule"
      end
      expect(grammar).to include("etsi_part = (1*alnum_char) as part")
      expect(grammar).to include("etsi_supplements = (1*etsi_supplement) as supplements")
    end

    it "rejects a list field whose item names no declared field" do
      yaml = File.read(etsi_definition_path)
        .sub("    item: part\n", "    item: phantom\n")

      expect { validate_definition(yaml) }
        .to raise_error(
          Pubid::Grammar::Pfs::InvalidDefinition,
          /fields\.parts\.item: must name a declared field/,
        )
    end

    it "rejects a fold whose flag collides with a declared field" do
      yaml = File.read(etsi_definition_path)
        .sub("    fold: { into: version, flag: is_edition }",
             "    fold: { into: version, flag: year }")

      expect { validate_definition(yaml) }
        .to raise_error(
          Pubid::Grammar::Pfs::InvalidDefinition,
          /fields\.edition\.fold\.flag: the boolean flag "year" must not collide/,
        )
    end

    it "rejects a supplements face claimed by two wrapper kinds" do
      yaml = File.read(etsi_definition_path)
        .sub('      face: "C"', '      face: "A"')

      expect { validate_definition(yaml) }
        .to raise_error(
          Pubid::Grammar::Pfs::InvalidDefinition,
          /supplements\.wrappers\.corrigendum\.face: ambiguity: face "A" is already claimed/,
        )
    end

    it "rejects an mr hook on a segment the shared renderer does not expose" do
      yaml = File.read(etsi_definition_path)
        .sub("  edition: { field: version }\n", "  edition: { field: version }\n  volume: { field: type }\n")

      expect { validate_definition(yaml) }
        .to raise_error(
          Pubid::Grammar::Pfs::InvalidDefinition,
          /mr\.volume: unknown MR segment/,
        )
    end

    it "rejects an edition affix on a segment that carries no fold" do
      yaml = File.read(etsi_definition_path)
        .sub("- { field: version, affix: \"v\", edition_affix: \"ed.\", lower: true }",
             "- { field: type, affix: \"v\", edition_affix: \"ed.\", lower: true }")

      expect { validate_definition(yaml) }
        .to raise_error(
          Pubid::Grammar::Pfs::InvalidDefinition,
          /urn\.official\[\d+\]\.edition_affix: the segment field "type" carries no fold/,
        )
    end

    it "rejects a field pattern spanning multiple lines (edition-2 line " \
       "discipline is the compiler's job, never the definition's)" do
      yaml = File.read(etsi_definition_path)
        .sub("    pattern: \"1*digit\"",
             "    pattern: \"1*digit\\\\n  2*digit\"")

      expect { validate_definition(yaml) }
        .to raise_error(
          Pubid::Grammar::Pfs::InvalidDefinition,
          /fields\.minor\.pattern: pattern spans multiple lines/,
        )
    end
  end

  describe "the committed cen_pfs outputs (pubid-grammar#121, the six " \
           "declared-emission features)" do
    let(:cen_definition_path) do
      File.join(PFS_REPO_ROOT, "definitions/cen.pfs")
    end

    it "recompiles definitions/cen.pfs byte-identically (generation is deterministic)" do
      dir = Dir.mktmpdir("pfs-golden")
      result = described_class.compile(
        cen_definition_path,
        source_rel: "definitions/cen.pfs",
        flavor_key: "cen_pfs",
        grammar_out: File.join(dir, "cen_pfs.parg"),
        artifact_out: File.join(dir, "cen_pfs.json"),
        repo_root: PFS_REPO_ROOT,
        parsanol_version: ENV.fetch("PARSANOL_VERSION", "1.3.126"),
      )

      committed = File.read(File.join(PFS_REPO_ROOT, "grammars/cen_pfs.parg"))
      expect(result.grammar_text).to eq(committed)
      expect(File.read(result.artifact_path))
        .to eq(File.read(File.join(PFS_REPO_ROOT, "artifacts/cen_pfs.json")))
    end
  end

  describe "the #121 feature surfaces, per feature" do
    let(:cen_definition_path) do
      File.join(PFS_REPO_ROOT, "definitions/cen.pfs")
    end

    # feature 1 — multi-type declared emission
    it "emits one class per declared type with its scheme-canonical wire tag" do
      result = compile_definition(File.read(cen_definition_path), flavor_key: "cen_pfs")

      identifiers = result.ruby_files
        .find { |path| path.end_with?("cen_pfs/identifiers.rb") }
        .then { |path| File.read(path) }
      %w[EuropeanNorm TechnicalReport TechnicalSpecification Guide CenReport
         CenWorkshopAgreement EuropeanSpecification EuropeanPrestandard
         HarmonizationDocument AdoptedEuropeanNorm].each do |klass|
        expect(identifiers).to include("autoload :#{klass},")
      end

      tr = result.ruby_files
        .find { |path| path.end_with?("cen_pfs/identifiers/technical_report.rb") }
        .then { |path| File.read(path) }
      expect(tr).to include("def self.polymorphic_name")
      expect(tr).to include('"pubid:cencenelec:technical-report"')
    end

    it "rejects a token claimed by two types (one spelling selects one class)" do
      yaml = File.read(cen_definition_path)
        .sub('    tokens: ["TS"]', '    tokens: ["TR"]')

      expect { validate_definition(yaml) }
        .to raise_error(
          Pubid::Grammar::Pfs::InvalidDefinition,
          /types\.technical_specification\.tokens\[0\]: ambiguity: token "TR" already selects/,
        )
    end

    # feature 2 — draft-stage serialization
    it "emits the stage value maps and compacts the typed-stage trio to its code" do
      result = compile_definition(File.read(cen_definition_path), flavor_key: "cen_pfs")

      identifier = result.ruby_files
        .find { |path| path.end_with?("cen_pfs/identifier.rb") }
        .then { |path| File.read(path) }
      expect(identifier).to include('"pren" => { stage_code: :proposal }')
      expect(identifier).to include('"fpren" => { stage_code: :final_proposal }')
      expect(identifier).to include('hash["stage"] = stage.code.to_s')
    end

    it "rejects a stage spelling claimed by two stages" do
      yaml = File.read(cen_definition_path)
        .sub("  fpren:\n    tokens: [\"FprEN\"]", "  fpren:\n    tokens: [\"FprEN\", \"prEN\"]")

      expect { validate_definition(yaml) }
        .to raise_error(
          Pubid::Grammar::Pfs::InvalidDefinition,
          /stages\.fpren\.tokens\[1\]: ambiguity: spelling "prEN" already claimed/,
        )
    end

    # feature 3 — cen's wrapper shapes
    it "generates the extended run: separator capture, per-wrapper items, " \
       "the optional ordinal and the date columns, faces longest-first" do
      result = compile_definition(File.read(cen_definition_path), flavor_key: "cen_pfs")
      grammar = File.read(result.grammar_path)

      expect(grammar).to include('("/" as supplements_slash / "+" as supplements_plus)')
      expect(grammar).to include("cen_cenelec_supplement_corrigendum = {")
      expect(grammar).to include('"AC" as supplement_kind [cen_cenelec_supplement_number]')
      # the face-length order: the corrigendum item rule precedes the amendment's
      expect(grammar).to match(
        /cen_cenelec_supplement = \( cen_cenelec_supplement_corrigendum \/ cen_cenelec_supplement_amendment \)/,
      )
    end

    it "rejects a wrapper word face in the extended shape when it is not a face word" do
      yaml = File.read(cen_definition_path).sub('face: "AC"', 'face: "amd"')

      expect { validate_definition(yaml) }
        .to raise_error(
          Pubid::Grammar::Pfs::InvalidDefinition,
          /supplements\.wrappers\.corrigendum\.face: must be a single upper-case kind face letter/,
        )
    end

    # feature 4 — adopted-base dispatch
    it "emits the two explicit hook call points, never an implicit adoption" do
      result = compile_definition(File.read(cen_definition_path), flavor_key: "cen_pfs")

      builder = result.ruby_files
        .find { |path| path.end_with?("cen_pfs/builder.rb") }
        .then { |path| File.read(path) }
      expect(builder).to include("return AdoptedBase.build(self, data) if data[:adopted]")
      expect(builder).to include("implicit = AdoptedBase.implicit(self, data)")
    end

    it "rejects an adopted dispatch on a non-builder-only capture" do
      yaml = File.read(cen_definition_path).sub("  field: adopted\n  hook: coded",
                                                "  field: number\n  hook: coded")

      expect { validate_definition(yaml) }
        .to raise_error(
          Pubid::Grammar::Pfs::InvalidDefinition,
          /adopted\.field: must name a declared builder-only string capture/,
        )
    end

    it "rejects an adopted hook other than `coded` (the escape hatch is the " \
       "only mechanism, and it is explicit)" do
      yaml = File.read(cen_definition_path).sub("hook: coded", "hook: magic")

      expect { validate_definition(yaml) }
        .to raise_error(
          Pubid::Grammar::Pfs::InvalidDefinition,
          /adopted\.hook: must be `coded`/,
        )
    end

    # feature 5 — publisher-type defaults
    it "emits the per-type publisher default (the designation types carry it)" do
      result = compile_definition(File.read(cen_definition_path), flavor_key: "cen_pfs")

      cr = result.ruby_files
        .find { |path| path.end_with?("cen_pfs/identifiers/cen_report.rb") }
        .then { |path| File.read(path) }
      expect(cr).to include('Publisher.new(body: "CR")')

      tr = result.ruby_files
        .find { |path| path.end_with?("cen_pfs/identifiers/technical_report.rb") }
        .then { |path| File.read(path) }
      expect(tr).to include('Publisher.new(body: "EN")')
    end

    it "rejects a publisher default claimed by two types" do
      yaml = File.read(cen_definition_path)
        .gsub('    publisher_default: "CWA"', '    publisher_default: "CR"')

      expect { validate_definition(yaml) }
        .to raise_error(
          Pubid::Grammar::Pfs::InvalidDefinition,
          /types\.cen_workshop_agreement\.publisher_default: ambiguity: publisher default "CR"/,
        )
    end

    # feature 6 — fused URN segments
    it "generates the fused segments: the publisher group, the adopted MR " \
       "face and the stage code" do
      result = compile_definition(File.read(cen_definition_path), flavor_key: "cen_pfs")

      urn = result.ruby_files
        .find { |path| path.end_with?("cen_pfs/urn_generator.rb") }
        .then { |path| File.read(path) }
      expect(urn).to include('group.map(&:downcase).join("-")')
      expect(urn).to include('mr.tr("._", "::")')
      expect(urn).to include('segments << "stage." + code.to_s')
      expect(urn).to include('["amd", id.number, id.year]')
      expect(urn).to include('"plus"')
    end

    it "rejects an adopted face with no declared dispatch (the face renders " \
       "the hook-provided adoption — removing the section is a compile error)" do
      yaml = File.read(cen_definition_path)
        .gsub("adopted:\n  field: adopted\n  hook: coded\n\n", "")

      expect { validate_definition(yaml) }
        .to raise_error(
          Pubid::Grammar::Pfs::InvalidDefinition,
          /templates\.canonical: \{adopted\} is a compiler-generated supplement-run capture/,
        )
    end

    it "rejects a fused adopted-MR segment without the adopted dispatch" do
      yaml = File.read(cen_definition_path)
        .gsub("adopted:\n  field: adopted\n  hook: coded\n\n", "")
        .gsub(" {adopted}", "")

      expect { validate_definition(yaml) }
        .to raise_error(
          Pubid::Grammar::Pfs::InvalidDefinition,
          /urn\.official\[\d+\]\.adopted_mr: the definition declares no `adopted:` dispatch/,
        )
    end
  end
end
