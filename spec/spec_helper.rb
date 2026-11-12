# frozen_string_literal: true

# The compiler pins the engine before anything requires parsanol (the
# bake-one.rb rule). CI installs exactly PARSANOL_VERSION; locally the
# env var overrides.
gem "parsanol", ENV.fetch("PARSANOL_VERSION", "1.3.126")

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
      parsanol_version: ENV.fetch("PARSANOL_VERSION", "1.3.126"),
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
end

require "tmpdir"
require "digest"
