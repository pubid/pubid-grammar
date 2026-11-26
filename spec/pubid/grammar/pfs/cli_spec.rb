# frozen_string_literal: true

require "spec_helper"
require "open3"
require "json"

# One END-TO-END proof per command (issue #152): the real CLI process,
# against fixture definitions/repos — the receipts.
RSpec.describe "scripts/pfs (end to end)" do
  let(:cli) { File.join(PFS_REPO_ROOT, "scripts/pfs") }
  let(:pin) { ENV.fetch("PARSANOL_VERSION", "1.5.1.0") }

  def run_cli(*args)
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, cli, *args)
    [stdout, stderr, status]
  end

  it "compile: compiles + bakes + verifies the committed doi definition" do
    dir = Dir.mktmpdir("pfs-cli")
    stdout, _stderr, status = run_cli(
      "compile", File.join(PFS_REPO_ROOT, "definitions/doi.pfs"),
      "--as", "spec_e2e_pfs",
      "--grammar-out", File.join(dir, "spec_e2e_pfs.parg"),
      "--artifact-out", File.join(dir, "spec_e2e_pfs.json"),
      "--parsanol-version", pin,
    )
    expect(status).to be_success, stdout
    expect(stdout).to include("compiled")
    expect(stdout).to include("verified against the baked artifact")
    expect(File).to exist(File.join(dir, "spec_e2e_pfs.json"))
  end

  it "new: scaffolds a definition that COMPILES GREEN in the next breath" do
    dir = Dir.mktmpdir("pfs-cli")
    scaffold = File.join(dir, "acme.pfs")
    stdout, _stderr, status = run_cli("new", "Acme Standards",
                                      "--scheme", "acme_e2e",
                                      "--out", scaffold)
    expect(status).to be_success, stdout
    expect(stdout).to include("scaffolded #{scaffold}")

    # the proof: the scaffold the CLI just wrote compiles + verifies green
    stdout, _stderr, status = run_cli(
      "compile", scaffold, "--as", "acme_e2e_pfs",
      "--grammar-out", File.join(dir, "acme_e2e_pfs.parg"),
      "--artifact-out", File.join(dir, "acme_e2e_pfs.json"),
      "--parsanol-version", pin,
    )
    expect(status).to be_success, stdout
    expect(stdout).to include("5 positives, 3 negatives")

    # and never overwrites (fail-closed scaffolding)
    _out, _err, status = run_cli("new", "Acme Standards",
                                 "--scheme", "acme_e2e", "--out", scaffold)
    expect(status).not_to be_success
  end

  it "lint: passes the fleet and names the rule on a dirty definition" do
    stdout, _stderr, status = run_cli(
      "lint", File.join(PFS_REPO_ROOT, "definitions/doi.pfs"),
    )
    expect(status).to be_success
    expect(stdout).to include("no findings")

    dirty = File.join(Dir.mktmpdir("pfs-cli"), "dirty.pfs")
    File.binwrite(dirty, <<~YAML)
      pfs: 2
      scheme: dirty
      title: Dirty
      organization: { name: Dirty, publisher: DIRTY, prefixes: ["DIRTY"] }
      types: { base: { key: dirty } }
      fields: { number: { pattern: "1*digit", kind: string } }
      grammar: { digit: "%x30-39" }
      templates: { canonical: '"DIRTY" {number}' }
      urn: { namespace: dirty, schema: { atoms: [], types: [] } }
      examples: { positives: ["DIRTY 1"] }
    YAML
    stdout, _stderr, status = run_cli("lint", dirty)
    expect(status).not_to be_success
    expect(stdout).to include("[PFS001]")
  end

  it "doctor: all green on a freshly sealed fixture repo" do
    fixture = build_pfs_fixture_repo
    stdout, _stderr, status = run_cli(
      "doctor",
      "--repo-root", fixture[:root],
      "--gem-root", fixture[:gem_root],
      "--testsuite-root", fixture[:testsuite_root],
      "--parsanol-version", pin,
    )
    expect(status).to be_success, stdout
    expect(stdout).to include("doctor: all green")
    expect(stdout).to include("[DRIFT005]")

    # and drift is a failing exit with the named check
    FileUtils.rm_f(File.join(fixture[:gem_root], "data/parg/#{fixture[:flavor]}.json"))
    _stdout, stderr, status = run_cli(
      "doctor",
      "--repo-root", fixture[:root],
      "--gem-root", fixture[:gem_root],
      "--testsuite-root", fixture[:testsuite_root],
      "--parsanol-version", pin,
    )
    expect(status).not_to be_success
    expect(stderr).to include("doctor: drift found")
  end

  it "capture: the lossless intake round-trips into the REQUIRED format" do
    dir = Dir.mktmpdir("pfs-cli")
    specimen = File.join(dir, "specimen.txt")
    File.binwrite(specimen, <<~TEXT)
      # the body's specimen
      BS EN ISO 8601:2019
      BS EN IEC 60747-8

      BS 10125:2014+A1:2016
    TEXT
    draft = File.join(dir, "bsnl.pfs")
    stdout, _stderr, status = run_cli(
      "capture", specimen, "--scheme", "bsnl_e2e",
      "--title", "BS National Line", "--publisher", "BS",
      "--out", draft,
    )
    expect(status).to be_success, stdout
    expect(stdout).to include("captured 3 identifier(s)")
    expect(stdout).to include("round-trip verified")

    # the rows are the captured strings, verbatim
    raw = Pubid::Grammar::Pfs::Loader.load_text(File.read(draft))
    expect(raw.dig("examples", "positives").map { |r| r["input"] }).to eq([
      "BS EN ISO 8601:2019", "BS EN IEC 60747-8", "BS 10125:2014+A1:2016",
    ])

    # the loop: the draft is lintable
    stdout, _stderr, status = run_cli("lint", draft)
    expect(status).to be_success, stdout
  end

  it "cutover: gates RED on an unattested flavor, GREEN on a prepared fixture" do
    # RED against the real siblings (doi_pfs is mid-fleet: the attestation
    # and the gem re-vendor are pending) — the gate is a failing exit.
    fixture = build_pfs_fixture_repo
    key = fixture[:flavor]

    # RED: break the gem parity gate
    File.write(File.join(fixture[:gem_root], "data/parg/#{key}.json"), "{}")
    stdout, stderr, status = run_cli(
      "cutover", key,
      "--repo-root", fixture[:root],
      "--gem-root", fixture[:gem_root],
      "--testsuite-root", fixture[:testsuite_root],
    )
    expect(status).not_to be_success
    expect(stdout).to include("[FAIL] gem parity")
    expect(stderr).to include("readiness gates RED")
    expect(stdout).to include("docs/CUTOVER.md")

    # GREEN: restore parity (the fixture ships byte-identical) — the
    # readiness gates pass and the mechanical plan prints
    FileUtils.cp(File.join(fixture[:root], "artifacts/#{key}.json"),
                 File.join(fixture[:gem_root], "data/parg/#{key}.json"))
    stdout, _stderr, status = run_cli(
      "cutover", key,
      "--repo-root", fixture[:root],
      "--gem-root", fixture[:gem_root],
      "--testsuite-root", fixture[:testsuite_root],
    )
    expect(status).to be_success, stdout
    expect(stdout).to include("readiness gates GREEN")
    expect(stdout).to include("data/parg/#{key}.json -> data/parg/#{key.sub(/_pfs\z/, '')}.json")
  end

  it "resolves the fleet pin when no --parsanol-version is given" do
    dir = Dir.mktmpdir("pfs-cli")
    stdout, _stderr, status = run_cli(
      "compile", File.join(PFS_REPO_ROOT, "definitions/doi.pfs"),
      "--as", "spec_pinless_pfs",
      "--grammar-out", File.join(dir, "x.parg"),
      "--artifact-out", File.join(dir, "x.json"),
    )
    expect(status).to be_success, stdout
    expect(stdout).to include("compiler #{pin}")
  end
end
