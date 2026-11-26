# frozen_string_literal: true

require "parsanol/parg"

module Pubid
  module Grammar
    module Telemetry
      # The reference parsing runtime: the committed artifacts are the
      # ONLY parsing input (the repo contract). One artifact per flavor,
      # loaded lazily and memoized; parses report an outcome instead of
      # raising so the classifier stays a pure decision function.
      class Runtime
        # The outcome of one parse attempt (a real value object, so tests
        # inject real outcomes rather than mocks).
        Outcome = Data.define(:ok, :error) do
          def self.success = new(ok: true, error: nil)

          def self.failure(error) = new(ok: false, error: error)
        end

        attr_reader :repo_root

        def initialize(repo_root:)
          @repo_root = repo_root
          @artifacts = {}
        end

        # Every identifier flavor in the inventory, deterministic order —
        # the data-language grammars are not identifier verdicts.
        def flavors
          @flavors ||= Dir.glob(File.join(repo_root, "artifacts", "*.json"))
                          .map { |path| File.basename(path, ".json") }
                          .reject { |flavor| Detector::NON_IDENTIFIER_FLAVORS.include?(flavor) }
                          .sort
        end

        def artifact(flavor)
          @artifacts[flavor] ||= Parsanol::PARG::Artifact.load(
            File.join(repo_root, "artifacts", "#{flavor}.json"),
            tables_dir: File.join(repo_root, "tables"),
            imports_dir: File.join(repo_root, "grammars"),
          )
        end

        def entry(flavor)
          a = artifact(flavor)
          a.envelope["default_entry"] || a.entries.first
        end

        def parse(flavor, input)
          artifact(flavor).parse(entry(flavor), input)
          Outcome.success
        rescue Parsanol::ParseFailed => e
          Outcome.failure(e.message)
        end
      end
    end
  end
end
