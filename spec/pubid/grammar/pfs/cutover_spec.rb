# frozen_string_literal: true

require "spec_helper"

# `pfs cutover` — the dev-alias -> canonical graduation (issue #152): the
# readiness gates (testsuite#130 attestation, gem parity, committed
# outputs) and the mechanical plan. The command mutates nothing.
RSpec.describe Pubid::Grammar::Pfs::Cutover do
  let(:fixture) { build_pfs_fixture_repo }
  let(:key) { fixture[:flavor] } # doi_pfs — a compiled flavor key
  let(:org) { key.sub(/_pfs\z/, "") }

  def plan
    described_class.plan(
      key: key, repo_root: fixture[:root],
      gem_root: fixture[:gem_root], testsuite_root: fixture[:testsuite_root],
    )
  end

  it "refuses a key that is not a compiled flavor key" do
    expect do
      described_class.plan(key: "doi", repo_root: fixture[:root])
    end.to raise_error(Pubid::Grammar::Pfs::Error, /<org>_pfs/)
  end

  describe "the green fixture" do
    it "passes every readiness gate" do
      expect(plan[:ready]).to be(true)
      gates = plan[:steps].select(&:gate)
      expect(gates).not_to be_empty
      expect(gates).to all(have_attributes(status: :ok))
    end

    it "gates on the attestation ledger first (testsuite#130)" do
      first_gate = plan[:steps].select(&:gate).first
      expect(first_gate.detail).to include("readiness gate")
      expect(first_gate.detail).to include("pfs-identity")
    end
  end

  describe "the gates fail closed" do
    it "fails on a non-clean attestation ledger" do
      path = File.join(fixture[:testsuite_root], "tests/#{key}/_status.yaml")
      File.write(path, File.read(path).sub("known_mismatches: 0", "known_mismatches: 3"))

      expect(plan[:ready]).to be(false)
      failed = plan[:steps].select(&:gate).find { |s| s.status == :FAIL }
      expect(failed.detail).to include('known_mismatches="3"')
    end

    it "fails on gem parity drift" do
      File.write(File.join(fixture[:gem_root], "data/parg/#{key}.json"), "{}")

      expect(plan[:ready]).to be(false)
      failed = plan[:steps].select(&:gate).find { |s| s.status == :FAIL }
      expect(failed.detail).to include("gem parity")
    end

    it "fails on missing compiled outputs" do
      FileUtils.rm_f(File.join(fixture[:root], "corpora/#{key}/corpus.json"))

      expect(plan[:ready]).to be(false)
      failed = plan[:steps].select(&:gate).find { |s| s.status == :FAIL }
      expect(failed.detail).to include("corpora/#{key}/corpus.json")
    end
  end

  describe "the advisory steps (not gates)" do
    it "warn when the coded slot is absent (a NEW flavor)" do
      # The fixture gem carries no lib/pubid/doi/ — the cutover creates it
      # from the generated emission; that is a WARN, never a gate FAIL.
      steps = plan[:steps].reject(&:gate)
      module_step = steps.find { |s| s.detail.include?("gem module") }
      expect(module_step.status).to eq(:WARN)
      expect(plan[:ready]).to be(true)
    end
  end

  describe "the recipe" do
    it "instantiates the mechanical plan for the key" do
      recipe = described_class.recipe(key: key, org: org,
                                      gem_root: fixture[:gem_root],
                                      testsuite_root: fixture[:testsuite_root])
      expect(recipe).to include("lib/pubid/#{org}/")
      expect(recipe).to include("data/parg/#{key}.json -> data/parg/#{org}.json")
      expect(recipe).to include("tests/#{key}/ -> tests/#{org}/")
      expect(recipe).to include("branch + PR")
    end

    it "points at the documented recipe" do
      recipe = described_class.recipe(key: key, org: org,
                                      gem_root: fixture[:gem_root],
                                      testsuite_root: fixture[:testsuite_root])
      expect(recipe).to include("docs/CUTOVER.md")
    end
  end
end
