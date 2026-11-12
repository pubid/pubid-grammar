# frozen_string_literal: true

require "spec_helper"

# The module library (issue #706 §4): named, versioned, composable
# modules a definition binds through `modules:`. The spec pins the
# library's load surface, the module document validation, the
# composition checks (fail-closed versioning, ambiguity across
# module and definition, identity-base resolution) and the emitted
# MODULES constant.
RSpec.describe Pubid::Grammar::Pfs::ModuleLibrary do
  let(:library) do
    described_class.load(File.join(PFS_REPO_ROOT, "definitions/modules"))
  end

  describe "the committed v1 library" do
    it "loads the six v1 modules" do
      expect(library.keys).to contain_exactly(
        "edition.core", "en.overlay", "iec.inner", "iso.inner",
        "national.prefix", "supplements.core",
      )
    end

    it "carries a version and a grammar map per module" do
      library.each_value do |mod|
        expect(mod.version).to eq(1)
        expect(mod.source_path).to start_with(PFS_REPO_ROOT)
        expect(mod.grammar).to be_a(Hash)
      end
    end

    it "carries the adoption identity on the overlay and inner modules" do
      expect(library["en.overlay"].identity.composition).to eq("wrapper-with-adopted")
      expect(library["en.overlay"].identity.base_module).to eq("iso.inner")
      expect(library["en.overlay"].identity.adopted_field).to eq("adopted")
      expect(library["national.prefix"].parameters.map(&:name)).to eq(["prefixes"])
      expect(library["national.prefix"].parameters.first.required).to be(true)
    end

    it "loads nothing from an absent directory (the composition then fails closed)" do
      expect(described_class.load(File.join(PFS_REPO_ROOT, "nope"))).to eq({})
    end

    it "rejects two module files claiming one name" do
      dir = Dir.mktmpdir("pfs-modules")
      File.write(File.join(dir, "a.pfsmod"), "module: twin\nversion: 1\n")
      File.write(File.join(dir, "b.pfsmod"), "module: twin\nversion: 1\n")

      expect { described_class.load(dir) }
        .to raise_error(Pubid::Grammar::Pfs::InvalidDefinition, /duplicate module name "twin"/)
    end
  end

  describe "module document validation" do
    it "rejects an unknown identity composition (fail-closed)" do
      raw = { "module" => "x", "version" => 1,
              "identity" => { "composition" => "grammar-only" } }
      expect { described_class.validate_module(raw, source_path: "x", source_sha: "s") }
        .to raise_error(Pubid::Grammar::Pfs::InvalidDefinition,
                        /unknown composition "grammar-only" — pfs:1 carries wrapper-with-adopted/)
    end

    it "rejects a reserved token claimed by a module" do
      raw = { "module" => "x", "version" => 1, "tokens" => ["AMD"] }
      expect { described_class.validate_module(raw, source_path: "x", source_sha: "s") }
        .to raise_error(Pubid::Grammar::Pfs::InvalidDefinition, /reserved token "AMD"/)
    end

    it "rejects an unsupported parameter type" do
      raw = { "module" => "x", "version" => 1,
              "parameters" => { "year" => { "type" => "int" } } }
      expect { described_class.validate_module(raw, source_path: "x", source_sha: "s") }
        .to raise_error(Pubid::Grammar::Pfs::InvalidDefinition,
                        /unsupported parameter type "int"/)
    end

    it "rejects a dotted name with a bad segment" do
      raw = { "module" => "X", "version" => 1 }
      expect { described_class.validate_module(raw, source_path: "x", source_sha: "s") }
        .to raise_error(Pubid::Grammar::Pfs::InvalidDefinition, /must be a dotted lower-case name/)
    end
  end

  # A composed definition: the §4 worked example — an NSB adoption of an
  # EN overlay over the ISO inner face, with the NSB token as data.
  def composed_definition_yaml
    <<~YAML
      pfs: 1
      scheme: demo_nsb
      title: "Demo national adoption"
      organization: { name: Demo NSB, publisher: DNS, prefixes: ["BS"] }
      modules:
        - module: iso.inner
          version: 1
        - module: en.overlay
          version: 1
        - module: national.prefix
          version: 1
          parameters: { prefixes: ["BS"] }
      grammar: { digit: "%x30-39" }
      types: { standard: { key: dns } }
      fields:
        number:
          pattern: '1*digit ["-" 1*digit]'
      templates:
        canonical: '"BS" " " {number}'
        alternates:
          - '"BS" " " en_face " " {number}'
      urn:
        namespace: demo_nsb
        schema: { atoms: [], types: [] }
      examples:
        positives:
          - input: "BS 5950-7"
            renders: "BS 5950-7"
          - input: "BS EN 5950-7"
            renders: "BS 5950-7"
        negatives:
          - "BS"
    YAML
  end

  def validate_with_library(yaml, library: nil)
    path = File.join(Dir.mktmpdir("pfs-modspec"), "definition.pfs")
    File.binwrite(path, yaml)
    raw = Pubid::Grammar::Pfs::Loader.load(path)
    Pubid::Grammar::Pfs::Validator.validate(
      raw,
      source_path: "definitions/spec.pfs",
      source_sha: Digest::SHA256.hexdigest(File.binread(path)),
      module_library: library || self.library,
    )
  end

  describe "composing a definition" do
    it "resolves the bindings and merges the fragments into the grammar view" do
      definition = validate_with_library(composed_definition_yaml)
      expect(definition.modules.map(&:name)).to eq(%w[iso.inner en.overlay national.prefix])
      expect(definition.module_bindings.map(&:name)).to eq(%w[iso.inner en.overlay national.prefix])
      # the module's face resolves like the definition's own fragment
      expect(definition.grammar).to include("en_face" => '[en_draft] "EN"')
      expect(definition.grammar).to include("iso_document" => a_string_including('"ISO"'))
    end

    it "compiles end-to-end with the module faces in the generated grammar" do
      result = compile_definition(composed_definition_yaml, flavor_key: "mod_pfs")
      expect(result.grammar_text).to include("# Module: iso.inner v1")
      expect(result.grammar_text).to include("# Module: en.overlay v1")
      expect(result.grammar_text).to include("# Module: national.prefix v1")
      expect(result.grammar_text).to include("en_face = [en_draft] \"EN\"")
    end

    it "carries the resolved composition on the emitted flavor" do
      result = compile_definition(composed_definition_yaml, flavor_key: "mod_pfs")
      module_rb = result.ruby_files.find { |f| f.end_with?("mod_pfs.rb") }
      source = File.read(module_rb)
      expect(source).to include("MODULES = [")
      expect(source).to include(
        '{ name: "iso.inner", version: 1, identity: ' \
        '{ composition: "wrapper-with-adopted", base_module: "iso.inner", adopted_field: :adopted } },',
      )
      expect(source).to include(
        '{ name: "national.prefix", version: 1, identity: ' \
        '{ composition: "wrapper-with-adopted", base_module: "iso.inner", adopted_field: :adopted } },',
      )
    end
  end

  describe "fail-closed composition checks" do
    it "refuses an unknown module (a library this compiler does not have)" do
      yaml = composed_definition_yaml.sub(/- module: iso\.inner\s*\n\s*version: 1/,
                                          "- module: jis.inner\n    version: 1")
      expect { validate_with_library(yaml) }
        .to raise_error(Pubid::Grammar::Pfs::ModuleLibrary::UnknownModuleError,
                        /unknown module "jis.inner"/)
    end

    it "refuses a newer module version than the library ships" do
      yaml = composed_definition_yaml.sub(/- module: iso\.inner\s*\n\s*version: 1/,
                                          "- module: iso.inner\n    version: 2")
      expect { validate_with_library(yaml) }
        .to raise_error(Pubid::Grammar::Pfs::ModuleLibrary::VersionMismatchError,
                        /bound at version 2; the library ships 1/)
    end

    it "refuses a stale module version (no silent downgrade)" do
      yaml = composed_definition_yaml.sub(/- module: iso\.inner\s*\n\s*version: 1/,
                                          "- module: iso.inner\n    version: 0")
      expect { validate_with_library(yaml) }
        .to raise_error(Pubid::Grammar::Pfs::ModuleLibrary::VersionMismatchError,
                        /bound at version 0; the library ships 1/)
    end

    it "refuses a binding without the required parameter" do
      yaml = composed_definition_yaml.sub(
        /    parameters: \{ prefixes: \["BS"\] \}\n/, "",
      )
      expect { validate_with_library(yaml) }
        .to raise_error(Pubid::Grammar::Pfs::InvalidDefinition,
                        /requires parameter "prefixes"/)
    end

    it "refuses an unknown parameter" do
      yaml = composed_definition_yaml.sub(
        'parameters: { prefixes: ["BS"] }',
        'parameters: { prefixes: ["BS"], year: 2024 }',
      )
      expect { validate_with_library(yaml) }
        .to raise_error(Pubid::Grammar::Pfs::InvalidDefinition,
                        /declares no parameter\(s\) "year"/)
    end

    it "refuses a reserved token supplied as a parameter value" do
      yaml = composed_definition_yaml.sub('parameters: { prefixes: ["BS"] }',
                                          'parameters: { prefixes: ["ED"] }')
      expect { validate_with_library(yaml) }
        .to raise_error(Pubid::Grammar::Pfs::InvalidDefinition, /reserved token "ED"/)
    end

    it "cites the module when two bound modules claim the same fragment name" do
      dir = Dir.mktmpdir("pfs-modules")
      File.write(File.join(dir, "a.pfsmod"),
                 "module: a.mod\nversion: 1\ngrammar: { shared: '\"A\"' }")
      File.write(File.join(dir, "b.pfsmod"),
                 "module: b.mod\nversion: 1\ngrammar: { shared: '\"B\"' }")
      # bind ONLY the two colliding modules: a side library replaces the
      # committed one, so the committed bindings would be unknown there
      yaml = composed_definition_yaml.sub(
        /modules:\n(  .*\n)+/,
        "modules:\n  - module: a.mod\n    version: 1\n  - module: b.mod\n    version: 1\n",
      )
      expect { validate_with_library(yaml, library: described_class.load(dir)) }
        .to raise_error(Pubid::Grammar::Pfs::InvalidDefinition,
                        /"shared" is declared by module "a.mod".*and by module "b.mod"/m)
    end

    it "cites the module when the definition re-claims a module fragment name" do
      yaml = composed_definition_yaml.sub(
        'grammar: { digit: "%x30-39" }',
        'grammar: { digit: "%x30-39", en_face: '"'"'"EN"'"'"' }',
      )
      expect { validate_with_library(yaml) }
        .to raise_error(Pubid::Grammar::Pfs::InvalidDefinition,
                        /"en_face" is already declared by module "en.overlay"/)
    end

    it "treats a module token shared with the definition's prefixes as co-ownership, not competition" do
      # the overlay owns EN; the definition dispatching EN as a prefix is
      # the composition working — binding IS the sharing
      yaml = composed_definition_yaml.sub("prefixes: [\"BS\"]", "prefixes: [\"BS\", \"EN\"]")
      expect { validate_with_library(yaml) }.not_to raise_error
    end

    it "cites both modules when two co-bound modules claim the same token" do
      dir = Dir.mktmpdir("pfs-modules")
      File.write(File.join(dir, "a.pfsmod"),
                 "module: a.mod\nversion: 1\ntokens: [\"SHARED\"]")
      File.write(File.join(dir, "b.pfsmod"),
                 "module: b.mod\nversion: 1\ntokens: [\"SHARED\"]")
      yaml = composed_definition_yaml.sub(
        /modules:\n(  .*\n)+/,
        "modules:\n  - module: a.mod\n    version: 1\n  - module: b.mod\n    version: 1\n",
      )
      expect { validate_with_library(yaml, library: described_class.load(dir)) }
        .to raise_error(Pubid::Grammar::Pfs::InvalidDefinition,
                        /modules module "a.mod" \(a.mod\) and "b.mod" \(b.mod\) both claim token "SHARED"/m)
    end

    it "treats a stage abbreviation binding a module token as co-ownership, not competition" do
      # the overlay owns prEN; the definition binding PREN as a stage abbr
      # is the composition working (the module is where the spelling lives)
      yaml = composed_definition_yaml.sub(
        "types: { standard: { key: dns } }",
        "types:\n  standard:\n    key: dns\n    stage: { code: pub, stage_code: published, abbr: [\"PREN\"] }",
      )
      expect { validate_with_library(yaml) }.not_to raise_error
    end

    it "holds the definition to binding the identity base a module declares" do
      yaml = composed_definition_yaml.sub(/  - module: iso\.inner\n    version: 1\n/, "")
      expect { validate_with_library(yaml) }
        .to raise_error(Pubid::Grammar::Pfs::InvalidDefinition,
                        /module "en.overlay" \(en.overlay\) declares the identity base "iso.inner"/)
    end

    it "refuses a module binding without an explicit version" do
      yaml = composed_definition_yaml.sub(/    version: 1\n/, "")
      expect { validate_with_library(yaml) }
        .to raise_error(Pubid::Grammar::Pfs::InvalidDefinition,
                        /modules\[0\]\.version: must be the integer version/)
    end
  end
end
