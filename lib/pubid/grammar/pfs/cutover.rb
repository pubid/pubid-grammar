# frozen_string_literal: true

require "digest"

module Pubid
  module Grammar
    module Pfs
      # `pfs cutover <key>` — the dev-alias → canonical cutover path
      # (issue #152).
      #
      # A composed flavor ships under the `<org>_pfs` dev-alias slot
      # beside its coded sibling; graduation REPLACES the coded slot. The
      # command is the readiness gate + the mechanical plan:
      #
      #   * the READINESS GATES (fail-closed): the testsuite#130
      #     attestation ledger (`tests/<key>/_status.yaml`, attestation
      #     `pfs-identity`, clean, zero known mismatches), the gem parity
      #     (the vendored artifact byte-identical), the compiled outputs
      #     committed;
      #   * the MECHANICAL PLAN: the gem module, the registry, the
      #     testsuite dir, the site data — the documented recipe is
      #     docs/CUTOVER.md; this command checks the gates and prints the
      #     plan with the concrete paths. It MUTATES NOTHING: the cutover
      #     crosses four repos and stays a human-reviewed operation
      #     (branch + PR in each).
      module Cutover
        Step = Struct.new(:gate, :status, :detail, keyword_init: true)

        module_function

        # @param key [String] the compiled flavor key ("acme_pfs")
        # @param repo_root [String] the grammar repo root
        # @param gem_root [String, nil] the pubid gem checkout
        # @param testsuite_root [String, nil] the pubid-testsuite checkout
        # @return [Hash] { steps: [Step], ready: bool }
        def plan(key:, repo_root:, gem_root: nil, testsuite_root: nil)
          raise Error, "cutover key must be a compiled flavor key " \
                       "(<org>_pfs), got #{key.inspect}" unless key.match?(/\A[a-z][a-z0-9_]*_pfs\z/)

          gem_root ||= File.expand_path("../pubid", repo_root)
          testsuite_root ||= File.expand_path("../pubid-testsuite", repo_root)
          org = key.sub(/_pfs\z/, "")
          steps = []

          steps << attestation_gate(key, testsuite_root)
          steps << parity_gate(key, repo_root, gem_root)
          steps << compiled_outputs_gate(key, repo_root)
          steps << gem_module_gate(org, gem_root)
          steps << registry_gate(org, gem_root)
          steps << testsuite_dir_gate(org, testsuite_root)

          { steps: steps, ready: steps.select(&:gate).all? { |s| s.status == :ok } }
        end

        # --- gates -----------------------------------------------------------

        # Gate 1 (the readiness gate per the recipe): the attestation
        # ledger, testsuite#130.
        def attestation_gate(key, testsuite_root)
          ledger = File.join(testsuite_root, "tests", key, "_status.yaml")
          unless File.file?(ledger)
            return Step.new(gate: true, status: :FAIL,
                            detail: "readiness gate: no attestation ledger at " \
                                    "pubid-testsuite tests/#{key}/_status.yaml — run the " \
                                    "corpus round (testsuite#130) first")
          end

          text = File.read(ledger)
          attestation = text.match(/^attestation:\s*(\S+)/)&.[](1)
          clean = text.match(/^clean:\s*(\S+)/)&.[](1)
          mismatches = text.match(/^known_mismatches:\s*(\d+)/)&.[](1)

          if attestation != "pfs-identity" || clean != "true" || mismatches != "0"
            return Step.new(
              gate: true, status: :FAIL,
              detail: "readiness gate: ledger #{ledger} is attestation=#{attestation.inspect} " \
                      "clean=#{clean.inspect} known_mismatches=#{mismatches.inspect} — the " \
                      "cutover gate requires pfs-identity, clean, zero mismatches",
            )
          end

          Step.new(gate: true, status: :ok,
                   detail: "readiness gate: attested (pfs-identity, clean, " \
                           "zero known mismatches) at tests/#{key}/_status.yaml")
        end

        # Gate 2: gem parity — the vendored artifact byte-identical.
        def parity_gate(key, repo_root, gem_root)
          artifact = File.join(repo_root, "artifacts", "#{key}.json")
          vendored = File.join(gem_root, "data/parg/#{key}.json")
          unless File.file?(artifact) && File.file?(vendored)
            return Step.new(gate: true, status: :FAIL,
                            detail: "gem parity: artifacts/#{key}.json or gem " \
                                    "data/parg/#{key}.json missing — compile and vendor first")
          end

          if File.binread(vendored) == File.binread(artifact)
            Step.new(gate: true, status: :ok,
                     detail: "gem parity: the vendored artifact is byte-identical")
          else
            Step.new(gate: true, status: :FAIL,
                     detail: "gem parity: data/parg/#{key}.json differs from " \
                             "artifacts/#{key}.json — vendor the artifact first")
          end
        end

        # Gate 3: the compiled outputs committed in the grammar repo.
        def compiled_outputs_gate(key, repo_root)
          paths = ["grammars/#{key}.parg", "artifacts/#{key}.json",
                   "schemas/#{key}.schema.json", "corpora/#{key}/corpus.json"]
          missing = paths.reject { |p| File.file?(File.join(repo_root, p)) }
          if missing.empty?
            Step.new(gate: true, status: :ok,
                     detail: "compiled outputs: #{paths.join(', ')} all present")
          else
            Step.new(gate: true, status: :FAIL,
                     detail: "compiled outputs: missing #{missing.join(', ')} — " \
                             "compile + rake contracts:regen and commit")
          end
        end

        # Gate 4: the gem module slot — the coded flavor the alias sits beside.
        def gem_module_gate(org, gem_root)
          if Dir.exist?(File.join(gem_root, "lib/pubid/#{org}"))
            Step.new(gate: false, status: :ok,
                     detail: "gem module: lib/pubid/#{org}/ present (the coded slot " \
                             "the compiled flavor replaces)")
          else
            Step.new(gate: false, status: :WARN,
                     detail: "gem module: lib/pubid/#{org}/ absent — a NEW flavor " \
                             "(no coded sibling): the cutover creates the module from " \
                             "the generated emission (--ruby-out)")
          end
        end

        # Gate 5: the registry — each flavor registers itself at the end of
        # its module file (lib/pubid/<org>.rb: Registry.register(:<org>, …)).
        def registry_gate(org, gem_root)
          module_file = File.join(gem_root, "lib/pubid/#{org}.rb")
          unless File.file?(module_file)
            return Step.new(gate: false, status: :WARN,
                            detail: "registry: lib/pubid/#{org}.rb absent — the cutover " \
                                    "registers the canonical key there " \
                                    "(Registry.register(:#{org}, Pubid::#{camelize(org)}))")
          end

          if File.read(module_file).match?(/Registry\.register\(:#{org}/)
            Step.new(gate: false, status: :ok,
                     detail: "registry: Registry.register(:#{org}, ...) present")
          else
            Step.new(gate: false, status: :WARN,
                     detail: "registry: no Registry.register(:#{org}) in lib/pubid/#{org}.rb — " \
                             "the cutover registers the canonical key (the registry sorts " \
                             "the coded key first, so Pubid.parse routes it)")
          end
        end

        # Gate 6: the testsuite canonical dir.
        def testsuite_dir_gate(org, testsuite_root)
          if Dir.exist?(File.join(testsuite_root, "tests", org))
            Step.new(gate: false, status: :ok,
                     detail: "testsuite dir: tests/#{org}/ present")
          else
            Step.new(gate: false, status: :WARN,
                     detail: "testsuite dir: tests/#{org}/ absent — the cutover re-keys " \
                             "tests/#{org}_pfs/ to the canonical slot (rows re-attest " \
                             "against the coded slot)")
          end
        end

        # The mechanical plan, printed after the gates. The recipe itself is
        # docs/CUTOVER.md; the plan instantiates it for this key.
        # @return [String]
        def recipe(key:, org:, gem_root:, testsuite_root:)
          <<~PLAN
            The mechanical cutover plan for #{key} -> #{org} (docs/CUTOVER.md has the
            full recipe; every step below is a branch + PR, never a direct push):

              grammar repo (pubid-grammar):
                1. definitions/#{org}.pfs stays the SSOT; the compiled outputs move
                   to the canonical key: grammars/#{org}.parg, artifacts/#{org}.json,
                   schemas/#{org}.schema.json, corpora/#{org}/corpus.json
                   (ruby scripts/pfs compile definitions/#{org}.pfs --as #{org}).
                2. The dev-alias key #{key} retires when the consumers are re-pinned.

              gem (pubid):
                3. The module: lib/pubid/#{key}/ -> lib/pubid/#{org}/ (or, for a new
                   flavor, vendor the generated emission: ruby scripts/pfs compile
                   definitions/#{org}.pfs --as #{org} --ruby-out lib/).
                4. Registry: lib/pubid.rb registers :#{org} -> Pubid::#{camelize(org)}
                   (Pubid::Registry.register; the registry sorts the coded key first).
                5. The vendored artifact: data/parg/#{key}.json -> data/parg/#{org}.json.
                6. The parity harness retires: spec/pubid/#{key}/ moves to
                   spec/pubid/#{org}/ and flips from "compiled == coded" to the coded
                   flavor's own contract specs.

              testsuite (pubid-testsuite):
                7. tests/#{key}/ -> tests/#{org}/ (rows re-attest against the coded
                   slot; the ledger's source_flavor/source_note update; the
                   attestation stays pfs-identity — testsuite#130 mechanics).
                8. reference-docs/#{key}/ (rawCopy twin) moves with it.

              site (pubid.github.io):
                9. The flavor's docs page + the identifier-patterns entry re-key to
                   #{org}; the dev-alias cross-links drop.

              consumers:
               10. relaton (and every consumer Gemfile) re-pins the released gem;
                   the registry now routes Pubid.parse to the canonical slot.
          PLAN
        end

        def camelize(key)
          key.split("_").map(&:capitalize).join
        end

        # @return [String] the one-line report for a step
        def format(step)
          "[#{step.status.to_s.upcase.ljust(4)}] #{step.detail}"
        end
      end
    end
  end
end
