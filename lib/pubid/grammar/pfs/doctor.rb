# frozen_string_literal: true

require "digest"
require "json"

module Pubid
  module Grammar
    module Pfs
      # `pfs doctor` — the drift checks (issue #152).
      #
      # One named check per failure mode, over every compiled flavor
      # (`artifacts/*_pfs.json`):
      #
      #   DRIFT001  engine-pin       the artifact's compiler stamp vs the
      #                              FLEET pin (.github/workflows/
      #                              parg-conformance.yml, PARSANOL_VERSION)
      #   DRIFT002  artifact-freshness  the .parg still compiles (at the pin)
      #                              to the committed checksum, and the
      #                              embedded source still hashes to
      #                              source_hash — the compiler's own
      #                              checksum/seal machinery (Compiler.bake)
      #   DRIFT003  contracts-round  the F3 schema and F4 corpus pin the same
      #                              artifact checksum (the round state)
      #   DRIFT004  gem-parity       the gem's vendored data/parg/<key>.json is
      #                              byte-identical with the artifact
      #   DRIFT005  attestation      the testsuite ledger (testsuite#130):
      #                              tests/<key>/_status.yaml carries the
      #                              pfs-identity attestation, clean
      #
      # Exit status: 0 = all green, 1 = any FAIL.
      module Doctor
        Check = Struct.new(:id, :status, :detail, keyword_init: true)

        # The workflow file carrying the fleet pin.
        FLEET_PIN_FILE = ".github/workflows/parg-conformance.yml"

        module_function

        # The fleet's engine pin, read from the conformance workflow.
        # @return [String, nil] the pinned version (nil = unreadable)
        def fleet_pin(repo_root)
          workflow(repo_root)&.match(/^\s*PARSANOL_VERSION:\s*(\S+)/) && Regexp.last_match(1)
        end

        # The ruby toolchain the fleet seals at (the envelope checksum is
        # toolchain-sensitive: re-sealing under a different ruby produces a
        # different artifact — 4623913's lesson).
        # @return [String, nil]
        def fleet_toolchain(repo_root)
          workflow(repo_root)&.match(/^\s*ruby-version:\s*'?([^\s']+)/) && Regexp.last_match(1)
        end

        def workflow(repo_root)
          path = File.join(repo_root, FLEET_PIN_FILE)
          File.read(path) if File.file?(path)
        end

        # @param repo_root [String] the grammar repo root
        # @param pin [String] the engine pin (defaults to the fleet pin)
        # @param gem_root [String, nil] the pubid gem checkout (default: the
        #   sibling ../pubid)
        # @param testsuite_root [String, nil] the pubid-testsuite checkout
        #   (default: the sibling ../pubid-testsuite)
        # @param reseal [Boolean] recompile the .parg at the pin (needs the
        #   pinned engine active); false checks envelope-internal freshness only
        # @return [Array<Check>]
        def run(repo_root:, pin: nil, gem_root: nil, testsuite_root: nil,
                reseal: true)
          pin ||= fleet_pin(repo_root)
          gem_root ||= File.expand_path("../pubid", repo_root)
          testsuite_root ||= File.expand_path("../pubid-testsuite", repo_root)
          checks = []
          checks << pin_check(pin, repo_root)

          Dir[File.join(repo_root, "artifacts", "*_pfs.json")].sort.each do |path|
            key = File.basename(path, ".json")
            checks.concat(check_flavor(key: key, path: path, repo_root: repo_root,
                                       pin: pin, gem_root: gem_root,
                                       testsuite_root: testsuite_root,
                                       reseal: reseal))
          end
          checks
        end

        def pin_check(pin, repo_root)
          if pin.nil?
            Check.new(id: "DRIFT001", status: :FAIL,
                      detail: "no fleet pin found (#{FLEET_PIN_FILE} carries no " \
                              "PARSANOL_VERSION) — pass --parsanol-version")
          else
            Check.new(id: "DRIFT001", status: :ok,
                      detail: "fleet pin #{pin}#{toolchain_note(repo_root)} " \
                              "(#{FLEET_PIN_FILE})")
          end
        end

        def toolchain_note(repo_root)
          toolchain = fleet_toolchain(repo_root)
          toolchain ? ", ruby #{toolchain}" : ""
        end

        def check_flavor(key:, path:, repo_root:, pin:, gem_root:, testsuite_root:, reseal:)
          checks = []
          envelope = begin
            JSON.parse(File.read(path))
          rescue JSON::ParserError => e
            return [Check.new(id: "DRIFT002", status: :FAIL,
                              detail: "#{key}: artifact is not valid JSON (#{e.message[0, 60]})")]
          end

          checks.concat(check_freshness(key, repo_root, pin, envelope, reseal))
          checks.concat(check_contracts(key, repo_root, envelope))
          checks << check_gem_parity(key, path, gem_root, envelope)
          checks << check_attestation(key, testsuite_root)
          checks
        end

        # DRIFT001+DRIFT002 for one flavor.
        def check_freshness(key, repo_root, pin, envelope, reseal)
          checks = []
          stamp = envelope["compiler_version"]
          if stamp.nil?
            checks << Check.new(id: "DRIFT001", status: :FAIL,
                                detail: "#{key}: artifact carries no compiler stamp")
          elsif !pin.nil? && stamp != pin
            checks << Check.new(
              id: "DRIFT001", status: :FAIL,
              detail: "#{key}: baked at compiler #{stamp}, fleet pin is #{pin} — " \
                      "re-seal at the CI toolchain#{toolchain_note(repo_root)}: " \
                      "ruby scripts/pfs compile definitions/#{key.sub(/_pfs\z/, '')}.pfs " \
                      "--as #{key} --parsanol-version #{pin}",
            )
          end

          source = envelope["source"]
          source_hash = envelope["source_hash"]
          if source.nil? || source_hash.nil?
            checks << Check.new(id: "DRIFT002", status: :FAIL,
                                detail: "#{key}: artifact carries no freshness envelope " \
                                        "(source/source_hash)")
          elsif Digest::SHA256.hexdigest(source) != source_hash
            checks << Check.new(id: "DRIFT002", status: :FAIL,
                                detail: "#{key}: embedded source does not hash to source_hash")
          end

          grammar_path = File.join(repo_root, "grammars", "#{key}.parg")
          unless File.file?(grammar_path)
            checks << Check.new(id: "DRIFT002", status: :FAIL,
                                detail: "#{key}: grammars/#{key}.parg is missing")
            return checks
          end
          if File.read(grammar_path) != source.to_s
            checks << Check.new(
              id: "DRIFT002", status: :FAIL,
              detail: "#{key}: grammars/#{key}.parg differs from the artifact's " \
                      "embedded source — re-bake (the artifact is the parser of record)",
            )
          end

          return checks unless reseal && !pin.nil?

          begin
            resealed = Compiler.bake(
              grammar_path,
              grammars_dir: File.join(repo_root, "grammars"),
              tables_dir: File.join(repo_root, "tables"),
              parsanol_version: pin,
            )
            if resealed["checksum"] != envelope["checksum"]
              checks << Check.new(
                id: "DRIFT002", status: :FAIL,
                detail: "#{key}: re-sealing at the pin yields checksum " \
                        "#{resealed["checksum"][0, 16]}... but the artifact pins " \
                        "#{envelope["checksum"][0, 16]}... — re-seal at the CI " \
                        "toolchain#{toolchain_note(repo_root)} (the seal is " \
                        "toolchain-sensitive), then re-bake and re-commit",
              )
            else
              checks << Check.new(id: "DRIFT002", status: :ok,
                                  detail: "#{key}: re-seals to the committed checksum at #{pin}")
            end
          rescue StandardError => e
            checks << Check.new(id: "DRIFT002", status: :FAIL,
                                detail: "#{key}: re-seal failed at the pin — #{e.message[0, 140]}")
          end
          checks
        end

        # DRIFT003: the derived contracts pin the same checksum.
        def check_contracts(key, repo_root, envelope)
          checksum = envelope["checksum"]
          checks = []

          schema_path = File.join(repo_root, "schemas", "#{key}.schema.json")
          corpus_path = File.join(repo_root, "corpora", key, "corpus.json")

          {
            "schemas/#{key}.schema.json" => schema_path,
            "corpora/#{key}/corpus.json" => corpus_path,
          }.each do |label, path|
            if !File.file?(path)
              checks << Check.new(id: "DRIFT003", status: :FAIL,
                                  detail: "#{key}: #{label} missing — run rake contracts:regen")
            else
              pinned = JSON.parse(File.read(path))["artifact_checksum"]
              if pinned == checksum
                checks << Check.new(id: "DRIFT003", status: :ok,
                                    detail: "#{key}: #{label} pins the committed checksum")
              else
                checks << Check.new(
                  id: "DRIFT003", status: :FAIL,
                  detail: "#{key}: #{label} pins #{pinned.to_s[0, 16]} but the artifact " \
                          "checksum is #{checksum.to_s[0, 16]} — the contracts round is " \
                          "stale: rake contracts:regen",
                )
              end
            end
          end
          checks
        end

        # DRIFT004: the gem's vendored artifact is byte-identical.
        def check_gem_parity(key, artifact_path, gem_root, envelope)
          vendored = File.join(gem_root, "data/parg/#{key}.json")
          unless File.file?(vendored)
            return Check.new(id: "DRIFT004", status: :FAIL,
                             detail: "#{key}: gem carries no vendored artifact " \
                                     "(#{gem_root}/data/parg/#{key}.json) — the gem's " \
                                     "compiled flavor will not parse")
          end

          if File.binread(vendored) == File.binread(artifact_path)
            Check.new(id: "DRIFT004", status: :ok,
                      detail: "#{key}: gem parity (vendored artifact byte-identical, " \
                              "#{envelope["checksum"][0, 16]}...)")
          else
            Check.new(
              id: "DRIFT004", status: :FAIL,
              detail: "#{key}: gem drift — data/parg/#{key}.json differs from " \
                      "artifacts/#{key}.json; copy the artifact into the gem and " \
                      "release (the artifact is the parser of record)",
            )
          end
        end

        # DRIFT005: the testsuite attestation ledger (testsuite#130).
        def check_attestation(key, testsuite_root)
          ledger = File.join(testsuite_root, "tests", key, "_status.yaml")
          unless File.file?(ledger)
            return Check.new(id: "DRIFT005", status: :FAIL,
                             detail: "#{key}: no testsuite attestation ledger " \
                                     "(#{testsuite_root}/tests/#{key}/_status.yaml) — " \
                                     "the flavor is not attested (testsuite#130)")
          end

          text = File.read(ledger)
          attestation = text.match(/^attestation:\s*(\S+)/)&.[](1)
          clean = text.match(/^clean:\s*(\S+)/)&.[](1)
          debt = text.match(/^unabsorbed_debt:\s*(\d+)/)&.[](1)

          if attestation != "pfs-identity"
            return Check.new(id: "DRIFT005", status: :FAIL,
                             detail: "#{key}: ledger attestation is #{attestation.inspect}, " \
                                     "expected pfs-identity")
          end
          if clean != "true"
            return Check.new(id: "DRIFT005", status: :FAIL,
                             detail: "#{key}: ledger is not clean (clean: #{clean}) — " \
                                     "re-run the corpus round")
          end

          Check.new(id: "DRIFT005", status: :ok,
                    detail: "#{key}: attested (pfs-identity, clean" \
                            "#{debt ? ", unabsorbed_debt #{debt}" : ""})")
        end

        # @return [Boolean] true when every check is ok
        def green?(checks)
          checks.all? { |c| c.status == :ok }
        end

        # @return [String] the one-line report for a check
        def format(check)
          "[#{check.id}] #{check.status.to_s.upcase.ljust(4)} #{check.detail}"
        end
      end
    end
  end
end
