# frozen_string_literal: true

# The compiler pins the engine before anything requires parsanol (the
# bake-one.rb rule). CI installs exactly PARSANOL_VERSION; locally the
# env var overrides.
gem "parsanol", ENV.fetch("PARSANOL_VERSION", "1.5.1.0")

# The grammar-repo root, resolved at spec_helper load (top-level lexical
# context, so it is stable under rspec's instance_eval).
PFS_REPO_ROOT = File.expand_path("..", __dir__).freeze
require "parsanol"
require "pubid/grammar/pfs"

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.order = :random

  # Compile a definition string through the real pipeline into a temp dir.
  def compile_definition(yaml, flavor_key: "spec_pfs")
    dir = Dir.mktmpdir("pfs-spec")
    path = File.join(dir, "definition.pfs")
    File.binwrite(path, yaml)

    Pubid::Grammar::Pfs::Compiler.compile(
      path,
      source_rel: "definitions/spec.pfs",
      flavor_key: flavor_key,
      grammar_out: File.join(dir, "#{flavor_key}.parg"),
      artifact_out: File.join(dir, "#{flavor_key}.json"),
      repo_root: PFS_REPO_ROOT,
      parsanol_version: ENV.fetch("PARSANOL_VERSION", "1.5.1.0"),
      ruby_out: File.join(dir, "ruby"),
    )
  end

  # Compile only up to validation (no bake): for rejection demos.
  def validate_definition(yaml)
    path = File.join(Dir.mktmpdir("pfs-spec"), "definition.pfs")
    File.binwrite(path, yaml)
    raw = Pubid::Grammar::Pfs::Loader.load(path)
    Pubid::Grammar::Pfs::Validator.validate(
      raw,
      source_path: "definitions/spec.pfs",
      source_sha: Digest::SHA256.hexdigest(File.binread(path)),
    )
  end

  # A minimal grammar-repo fixture for the doctor/cutover tooling specs:
  # grammars/ + tables/ + one flavor's compiled outputs SEALED IN THIS
  # PROCESS (so the envelope checksum matches whatever toolchain runs the
  # spec — the seal is toolchain-sensitive, 4623913's lesson), plus the
  # sibling stubs (gem_root, testsuite_root) the doctor and the cutover
  # read. Returns the paths hash.
  def build_pfs_fixture_repo(flavor: "doi_pfs")
    require "fileutils"
    root = Dir.mktmpdir("pfs-fixture")
    FileUtils.mkdir_p([File.join(root, "grammars"), File.join(root, "artifacts")])
    FileUtils.cp_r(File.join(PFS_REPO_ROOT, "tables"), File.join(root, "tables"))
    FileUtils.cp(
      File.join(PFS_REPO_ROOT, "grammars/#{flavor}.parg"),
      File.join(root, "grammars/#{flavor}.parg"),
    )

    pin = ENV.fetch("PARSANOL_VERSION", "1.5.1.0")
    envelope = Pubid::Grammar::Pfs::Compiler.bake(
      File.join(root, "grammars/#{flavor}.parg"),
      grammars_dir: File.join(root, "grammars"),
      tables_dir: File.join(root, "tables"),
      parsanol_version: pin,
    )
    require "json"
    File.binwrite(File.join(root, "artifacts/#{flavor}.json"), JSON.generate(envelope))

    # The derived contracts pin the freshly sealed checksum (the round is
    # fresh by construction).
    require "fileutils"
    FileUtils.mkdir_p([File.join(root, "schemas"), File.join(root, "corpora", flavor)])
    File.binwrite(File.join(root, "schemas/#{flavor}.schema.json"), JSON.generate({
      "grammar" => flavor, "artifact_checksum" => envelope["checksum"], "schema" => {},
    }))
    File.binwrite(File.join(root, "corpora/#{flavor}/corpus.json"), JSON.generate({
      "grammar" => flavor, "artifact_checksum" => envelope["checksum"], "cases" => [],
    }))

    # The sibling stubs: gem_root with the vendored artifact, testsuite_root
    # with the attestation ledger (testsuite#130's shape).
    gem_root = File.join(root, "gem")
    testsuite_root = File.join(root, "testsuite")
    FileUtils.mkdir_p([File.join(gem_root, "data/parg"), File.join(testsuite_root, "tests", flavor)])
    FileUtils.cp(File.join(root, "artifacts/#{flavor}.json"),
                 File.join(gem_root, "data/parg/#{flavor}.json"))
    File.binwrite(File.join(testsuite_root, "tests/#{flavor}/_status.yaml"), <<~YAML)
      clean: true
      known_mismatches: 0
      attestation: pfs-identity
      source_flavor: #{flavor.sub(/_pfs\z/, "")}
      unabsorbed_debt: 0
    YAML

    {
      root: root, flavor: flavor, envelope: envelope,
      gem_root: gem_root, testsuite_root: testsuite_root,
    }
  end
end

require "tmpdir"
require "digest"
