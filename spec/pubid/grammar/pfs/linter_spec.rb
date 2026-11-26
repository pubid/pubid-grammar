# frozen_string_literal: true

require "spec_helper"

# `pfs lint` — the compile-time guarantees as pre-compile diagnostics
# (issue #152). Every rule is demonstrated once, with the actionable
# message the finding carries.
RSpec.describe Pubid::Grammar::Pfs::Linter do
  let(:library) do
    Pubid::Grammar::ModuleLibraryLess ||= nil
    Pubid::Grammar::Pfs::ModuleLibrary.load(
      File.join(PFS_REPO_ROOT, "definitions/modules"),
    )
  end

  def lint(yaml, library: self.library)
    path = File.join(Dir.mktmpdir("pfs-lint"), "definition.pfs")
    File.binwrite(path, yaml)
    described_class.run(path, module_library: library)
  end

  def finding_for(yaml, id, library: self.library)
    findings = lint(yaml, library: library)
    expect(findings).not_to be_empty
    finding = findings.find { |f| f.id == id }
    expect(finding).to be_a(described_class::Finding),
                       "expected a #{id} finding, got #{findings.map(&:id).inspect}"
    finding
  end

  describe "the fleet's own definitions are clean" do
    Dir[File.join(PFS_REPO_ROOT, "definitions", "*.pfs")].sort.each do |path|
      it "lints #{File.basename(path)} clean" do
        expect(described_class.run(path)).to be_empty
      end
    end
  end

  it "PFS001: pins the schema major (a newer dialect fails closed)" do
    yaml = File.read(File.join(PFS_REPO_ROOT, "definitions/doi.pfs"))
      .sub("pfs: 1", "pfs: 2")
    finding = finding_for(yaml, "PFS001")
    expect(finding.rule).to eq("pfs")
    expect(finding.message).to include("upgrade the compiler")
  end

  it "PFS002: pins module versions (stale binding)" do
    yaml = <<~YAML
      pfs: 1
      scheme: demo
      title: Demo
      organization: { name: Demo, publisher: DEMO, prefixes: ["DEMO"] }
      modules:
        - { module: iso.inner, version: 2 }
      types: { base: { key: demo } }
      fields: { number: { pattern: "1*digit", kind: string } }
      grammar: { digit: "%x30-39" }
      templates: { canonical: "DEMO {number}" }
      urn: { namespace: demo, schema: { atoms: [], types: [] } }
      examples: { positives: ["DEMO 1"] }
    YAML
    finding = finding_for(yaml, "PFS002")
    expect(finding.message).to include("the library ships 1")
  end

  it "PFS002: names an unknown module with the known set" do
    yaml = <<~YAML
      pfs: 1
      scheme: demo
      title: Demo
      organization: { name: Demo, publisher: DEMO, prefixes: ["DEMO"] }
      modules:
        - { module: no.such, version: 1 }
      types: { base: { key: demo } }
      fields: { number: { pattern: "1*digit", kind: string } }
      grammar: { digit: "%x30-39" }
      templates: { canonical: "DEMO {number}" }
      urn: { namespace: demo, schema: { atoms: [], types: [] } }
      examples: { positives: ["DEMO 1"] }
    YAML
    finding = finding_for(yaml, "PFS002")
    expect(finding.message).to include("unknown module")
  end

  it "PFS003: cites a fragment collision across two co-bound modules" do
    # Two synthetic modules claiming the same grammar fragment name.
    make = lambda do |name, token|
      Pubid::Grammar::Pfs::ModuleLibrary.validate_module(
        {
          "module" => name, "version" => 1, "title" => name,
          "grammar" => { "shared_face" => '"x"' }, "tokens" => [token],
        },
        source_path: "spec/#{name}", source_sha: "x",
      )
    end
    synthetic = {
      "one.inner" => make.call("one.inner", "ONE"),
      "two.inner" => make.call("two.inner", "TWO"),
    }

    yaml = <<~YAML
      pfs: 1
      scheme: demo
      title: Demo
      organization: { name: Demo, publisher: DEMO, prefixes: ["DEMO"] }
      modules:
        - { module: one.inner, version: 1 }
        - { module: two.inner, version: 1 }
      types: { base: { key: demo } }
      fields: { number: { pattern: "1*digit", kind: string } }
      grammar: { digit: "%x30-39" }
      templates: { canonical: "DEMO {number}" }
      urn: { namespace: demo, schema: { atoms: [], types: [] } }
      examples: { positives: ["DEMO 1"] }
    YAML
    finding = finding_for(yaml, "PFS003", library: synthetic)
    expect(finding.message).to include("silent rebinding")
  end

  it "PFS004: cites co-bound modules competing for a token" do
    make = lambda do |name, token|
      Pubid::Grammar::Pfs::ModuleLibrary.validate_module(
        {
          "module" => name, "version" => 1, "title" => name,
          "grammar" => { "#{name.tr('.', '_')}_face" => '"x"' },
          "tokens" => [token],
        },
        source_path: "spec/#{name}", source_sha: "x",
      )
    end
    synthetic = {
      "one.inner" => make.call("one.inner", "SHARED"),
      "two.inner" => make.call("two.inner", "SHARED"),
    }

    yaml = <<~YAML
      pfs: 1
      scheme: demo
      title: Demo
      organization: { name: Demo, publisher: DEMO, prefixes: ["DEMO"] }
      modules:
        - { module: one.inner, version: 1 }
        - { module: two.inner, version: 1 }
      types: { base: { key: demo } }
      fields: { number: { pattern: "1*digit", kind: string } }
      grammar: { digit: "%x30-39" }
      templates: { canonical: "DEMO {number}" }
      urn: { namespace: demo, schema: { atoms: [], types: [] } }
      examples: { positives: ["DEMO 1"] }
    YAML
    finding = finding_for(yaml, "PFS004", library: synthetic)
    expect(finding.message).to include("both claim token")
  end

  it "PFS005: refuses a reserved token claimed as a prefix" do
    yaml = <<~YAML
      pfs: 1
      scheme: demo
      title: Demo
      organization: { name: Demo, publisher: ED, prefixes: ["ED"] }
      types: { base: { key: demo } }
      fields: { number: { pattern: "1*digit", kind: string } }
      grammar: { digit: "%x30-39" }
      templates: { canonical: "ED {number}" }
      urn: { namespace: demo, schema: { atoms: [], types: [] } }
      examples: { positives: ["ED 1"] }
    YAML
    finding = finding_for(yaml, "PFS005")
    expect(finding.message).to include("edition/supplement machinery")
  end

  it "PFS006: names a citation error (a {reference} to no declared field)" do
    yaml = <<~YAML
      pfs: 1
      scheme: demo
      title: Demo
      organization: { name: Demo, publisher: DEMO, prefixes: ["DEMO"] }
      types: { base: { key: demo } }
      fields: { number: { pattern: "1*digit", kind: string } }
      grammar: { digit: "%x30-39" }
      templates: { canonical: "DEMO {number} {nosuch}" }
      urn: { namespace: demo, schema: { atoms: [], types: [] } }
      examples: { positives: ["DEMO 1"] }
    YAML
    finding = finding_for(yaml, "PFS006")
    expect(finding.message).to include("{nosuch}")
  end

  it "PFS007: flags a numeric-kind mismatch (int core over a string field)" do
    yaml = <<~YAML
      pfs: 1
      scheme: demo
      title: Demo
      organization: { name: Demo, publisher: DEMO, prefixes: ["DEMO"] }
      types: { base: { key: demo } }
      fields: { number: { pattern: "1*digit", kind: string } }
      grammar: { digit: "%x30-39" }
      templates: { canonical: "DEMO {number}" }
      urn:
        namespace: demo
        schema:
          atoms: []
          types:
            - { type: "pubid:demo:base", token: id, core: [["number", "int"]] }
      examples: { positives: ["DEMO 1"] }
    YAML
    finding = finding_for(yaml, "PFS007")
    expect(finding.message).to include("kind: integer")
  end

  it "PFS007: accepts the wrapper ordinal namespace (number_kind over a " \
     "same-named document field)" do
    # The etsi shape: a string `number` DOCUMENT field and a wrapper row
    # whose core [[number, int]] is the WRAPPER ordinal — not a mismatch.
    yaml = File.read(File.join(PFS_REPO_ROOT, "definitions/etsi.pfs"))
    expect(lint(yaml)).to be_empty
  end

  it "PFS008: flags {supplements} without a declared supplements section" do
    yaml = <<~YAML
      pfs: 1
      scheme: demo
      title: Demo
      organization: { name: Demo, publisher: DEMO, prefixes: ["DEMO"] }
      types: { base: { key: demo } }
      fields: { number: { pattern: "1*digit", kind: string } }
      grammar: { digit: "%x30-39" }
      templates: { canonical: "DEMO {number} [{supplements}]" }
      urn: { namespace: demo, schema: { atoms: [], types: [] } }
      examples: { positives: ["DEMO 1"] }
    YAML
    finding = finding_for(yaml, "PFS008")
    expect(finding.message).to include("no supplements: section")
  end

  it "PFS009: requires the examples panel" do
    yaml = <<~YAML
      pfs: 1
      scheme: demo
      title: Demo
      organization: { name: Demo, publisher: DEMO, prefixes: ["DEMO"] }
      types: { base: { key: demo } }
      fields: { number: { pattern: "1*digit", kind: string } }
      grammar: { digit: "%x30-39" }
      templates: { canonical: "DEMO {number}" }
      urn: { namespace: demo, schema: { atoms: [], types: [] } }
    YAML
    finding = finding_for(yaml, "PFS009")
    expect(finding.message).to include("live test panel")
  end

  it "PFS010: names a key outside the dialect" do
    yaml = <<~YAML
      pfs: 1
      scheme: demo
      title: Demo
      widget: { new: true }
      organization: { name: Demo, publisher: DEMO, prefixes: ["DEMO"] }
      types: { base: { key: demo } }
      fields: { number: { pattern: "1*digit", kind: string } }
      grammar: { digit: "%x30-39" }
      templates: { canonical: "DEMO {number}" }
      urn: { namespace: demo, schema: { atoms: [], types: [] } }
      examples: { positives: ["DEMO 1"] }
    YAML
    finding = finding_for(yaml, "PFS010")
    expect(finding.message).to include("newer dialect")
  end

  it "PFS999: carries the validator's own refusal when no named rule fires" do
    # A deep structural error the fast scans do not model: the date
    # binding referencing an undeclared field.
    yaml = <<~YAML
      pfs: 1
      scheme: demo
      title: Demo
      organization: { name: Demo, publisher: DEMO, prefixes: ["DEMO"] }
      types: { base: { key: demo } }
      fields: { number: { pattern: "1*digit", kind: string } }
      grammar: { digit: "%x30-39" }
      date: { fields: [nosuch] }
      templates: { canonical: '"DEMO" {number}' }
      urn: { namespace: demo, schema: { atoms: [], types: [] } }
      examples: { positives: ["DEMO 1"] }
    YAML
    finding = finding_for(yaml, "PFS999")
    expect(finding.rule).to start_with("date")
  end
end
