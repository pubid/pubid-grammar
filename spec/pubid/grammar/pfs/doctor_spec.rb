# frozen_string_literal: true

require "spec_helper"
require "json"

# `pfs doctor` — the drift checks (issue #152). The fixture repo is
# SEALED IN-PROCESS (build_pfs_fixture_repo), so the re-seal compares
# checksums produced by the same toolchain the spec runs under; the
# committed fleet is NOT touched.
RSpec.describe Pubid::Grammar::Pfs::Doctor do
  let(:fixture) { build_pfs_fixture_repo }
  let(:flavor) { fixture[:flavor] }

  def run_doctor(**overrides)
    described_class.run(
      repo_root: fixture[:root],
      gem_root: fixture[:gem_root],
      testsuite_root: fixture[:testsuite_root],
      **overrides,
    )
  end

  def status_for(checks, id)
    checks.select { |c| c.id == id }
  end

  describe "the fresh fixture" do
    it "is all green (re-seal included)" do
      checks = run_doctor(pin: ENV.fetch("PARSANOL_VERSION", "1.5.1.0"))
      failed = checks.reject { |c| c.status == :ok }
      expect(failed).to eq([]), failed.map { |c| described_class.format(c) }.join("\n")
    end

    it "reports the fleet pin with the toolchain note" do
      checks = run_doctor(pin: "1.5.1.0")
      pin_check = checks.first
      expect(pin_check.id).to eq("DRIFT001")
      expect(pin_check.detail).to include("fleet pin 1.5.1.0")
    end

    it "attests each compiled flavor (DRIFT005)" do
      checks = run_doctor(pin: "1.5.1.0")
      attestation = status_for(checks, "DRIFT005").first
      expect(attestation.status).to eq(:ok)
      expect(attestation.detail).to include("pfs-identity")
    end
  end

  describe "DRIFT002: artifact freshness" do
    it "flags a tampered .parg (no longer the artifact's embedded source)" do
      File.write(File.join(fixture[:root], "grammars/#{flavor}.parg"),
                 File.read(File.join(fixture[:root], "grammars/#{flavor}.parg")) +
                 "\n# tampered")
      checks = run_doctor(pin: "1.5.1.0", reseal: false)
      drift = status_for(checks, "DRIFT002")
      expect(drift.map(&:status)).to include(:FAIL)
      expect(drift.map(&:detail).join).to include("differs from the artifact's")
    end

    it "flags a checksum drift on re-seal (a stale artifact)" do
      # Tamper the ARTIFACT's pinned checksum: the re-seal then disagrees.
      path = File.join(fixture[:root], "artifacts/#{flavor}.json")
      envelope = JSON.parse(File.read(path))
      envelope["checksum"] = "sha256:#{'0' * 64}"
      File.binwrite(path, JSON.generate(envelope))

      checks = run_doctor(pin: ENV.fetch("PARSANOL_VERSION", "1.5.1.0"))
      drift = status_for(checks, "DRIFT002").map(&:detail).join
      expect(drift).to include("re-sealing at the pin yields checksum")
    end

    it "flags a missing compiler stamp (DRIFT001)" do
      path = File.join(fixture[:root], "artifacts/#{flavor}.json")
      envelope = JSON.parse(File.read(path))
      envelope.delete("compiler_version")
      File.binwrite(path, JSON.generate(envelope))

      checks = run_doctor(pin: "1.5.1.0", reseal: false)
      expect(status_for(checks, "DRIFT001").map(&:status)).to include(:FAIL)
    end

    it "flags a stamp older than the pin (DRIFT001)" do
      path = File.join(fixture[:root], "artifacts/#{flavor}.json")
      envelope = JSON.parse(File.read(path))
      envelope["compiler_version"] = "0.9.9"
      File.binwrite(path, JSON.generate(envelope))

      checks = run_doctor(pin: "1.5.1.0", reseal: false)
      stale = status_for(checks, "DRIFT001").find { |c| c.detail.include?(flavor) }
      expect(stale.status).to eq(:FAIL)
      expect(stale.detail).to include("fleet pin is 1.5.1.0")
    end
  end

  describe "DRIFT003: the contracts round" do
    it "flags a stale schema pin" do
      path = File.join(fixture[:root], "schemas/#{flavor}.schema.json")
      doc = JSON.parse(File.read(path))
      doc["artifact_checksum"] = "sha256:#{'1' * 64}"
      File.binwrite(path, JSON.generate(doc))

      checks = run_doctor(pin: "1.5.1.0", reseal: false)
      stale = status_for(checks, "DRIFT003").find { |c| c.detail.include?("schema") }
      expect(stale.status).to eq(:FAIL)
      expect(stale.detail).to include("contracts round is stale")
    end

    it "flags a missing corpus" do
      FileUtils.rm_f(File.join(fixture[:root], "corpora/#{flavor}/corpus.json"))

      checks = run_doctor(pin: "1.5.1.0", reseal: false)
      missing = status_for(checks, "DRIFT003").find { |c| c.detail.include?("missing") }
      expect(missing.status).to eq(:FAIL)
      expect(missing.detail).to include("rake contracts:regen")
    end
  end

  describe "DRIFT004: gem parity" do
    it "flags vendored drift (a byte-different gem artifact)" do
      File.write(File.join(fixture[:gem_root], "data/parg/#{flavor}.json"),
                 File.read(File.join(fixture[:root], "artifacts/#{flavor}.json")) + "\n")

      checks = run_doctor(pin: "1.5.1.0", reseal: false)
      drift = status_for(checks, "DRIFT004").first
      expect(drift.status).to eq(:FAIL)
      expect(drift.detail).to include("gem drift")
    end

    it "flags a missing vendored artifact" do
      FileUtils.rm_f(File.join(fixture[:gem_root], "data/parg/#{flavor}.json"))

      checks = run_doctor(pin: "1.5.1.0", reseal: false)
      missing = status_for(checks, "DRIFT004").first
      expect(missing.status).to eq(:FAIL)
      expect(missing.detail).to include("the gem's compiled flavor will not parse")
    end
  end

  describe "DRIFT005: the testsuite attestation" do
    it "flags a dirty ledger" do
      path = File.join(fixture[:testsuite_root], "tests/#{flavor}/_status.yaml")
      File.write(path, File.read(path).sub("clean: true", "clean: false"))

      checks = run_doctor(pin: "1.5.1.0", reseal: false)
      dirty = status_for(checks, "DRIFT005").first
      expect(dirty.status).to eq(:FAIL)
      expect(dirty.detail).to include("corpus round")
    end

    it "flags a non-pfs attestation" do
      path = File.join(fixture[:testsuite_root], "tests/#{flavor}/_status.yaml")
      File.write(path, File.read(path).sub("attestation: pfs-identity",
                                           "attestation: none"))

      checks = run_doctor(pin: "1.5.1.0", reseal: false)
      expect(status_for(checks, "DRIFT005").first.status).to eq(:FAIL)
    end

    it "flags a missing ledger (the flavor is not attested)" do
      FileUtils.rm_rf(File.join(fixture[:testsuite_root], "tests/#{flavor}"))

      checks = run_doctor(pin: "1.5.1.0", reseal: false)
      missing = status_for(checks, "DRIFT005").first
      expect(missing.status).to eq(:FAIL)
      expect(missing.detail).to include("testsuite#130")
    end
  end

  describe "the fleet pin source" do
    it "reads the pin and the toolchain from the conformance workflow" do
      expect(described_class.fleet_pin(PFS_REPO_ROOT)).to eq("1.5.1.0")
      expect(described_class.fleet_toolchain(PFS_REPO_ROOT)).to match(/\A3\.4\./)
    end
  end
end
