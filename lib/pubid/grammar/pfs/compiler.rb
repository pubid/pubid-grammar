# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"

module Pubid
  module Grammar
    module Pfs
      # The compiler pipeline: load → validate → generate the PARG body →
      # verify the REQUIRED examples against the in-memory compiled grammar
      # → emit the full grammar (test block included, capture expectations
      # derived from the verification) → bake the artifact through the
      # existing parsanol pipeline → re-verify against the BAKED artifact
      # (the runtime parser of record) → optionally emit the Ruby flavor.
      #
      # Requires parsanol to be ACTIVATED at the pinned version before this
      # file loads (the CLI does `gem "parsanol", version` first — the
      # bake-pinning rule of scripts/bake-one.rb).
      class Compiler
        Result = Struct.new(
          :definition, :grammar_path, :grammar_text, :artifact_path,
          :envelope, :captures, :ruby_files, keyword_init: true,
        )

        ENTRY = PargGenerator::ENTRY

        class BakeError < Error; end

        class << self

        # @param definition_path [String] the .pfs file
        # @param source_rel [String] the path AS WRITTEN IN THE HEADER
        #   (relative to the repo root — no machine-local paths in outputs)
        # @param flavor_key [String] the compiled flavor key ("doi_pfs")
        # @param grammar_out [String] target .parg path
        # @param artifact_out [String] target baked-artifact path
        # @param repo_root [String] the grammar repo root (grammars/ + tables/)
        # @param parsanol_version [String] the pinned compiler version
        # @param ruby_out [String, nil] when given, emit the Ruby flavor
        #   module files under this directory
        # @return [Result]
        def compile(definition_path, source_rel:, flavor_key:, grammar_out:,
                    artifact_out:, repo_root:, parsanol_version:, ruby_out: nil)
          require "parsanol"
          require "parsanol/parg"

          raise Error, "flavor key must be snake_case" unless flavor_key.match?(Validator::NAME)

          raw_bytes = File.binread(definition_path)
          raw = Loader.load(definition_path)
          definition = Validator.validate(
            raw,
            source_path: source_rel,
            source_sha: Digest::SHA256.hexdigest(raw_bytes),
            module_library: ModuleLibrary.load(
              File.join(repo_root, "definitions", "modules"),
            ),
          )

          generator = PargGenerator.new(definition, flavor_key: flavor_key)
          grammars_dir = File.join(repo_root, "grammars")
          tables_dir = File.join(repo_root, "tables")

          # 1. Body-only verification: parse, bind, render every example
          #    and derive the capture expectations.
          body_text = generator.generate(body_only: true)
          captures = verify_examples(definition, body_text,
                                     grammars_dir: grammars_dir, tables_dir: tables_dir)

          # 2. Full grammar: body + test block with the derived captures.
          full_generator = PargGenerator.new(definition, flavor_key: flavor_key,
                                             captures: captures)
          grammar_text = full_generator.generate
          FileUtils.mkdir_p(File.dirname(grammar_out))
          File.binwrite(grammar_out, grammar_text)

          # 3. Bake the artifact (the existing pipeline's compile step).
          envelope = bake(grammar_out, grammars_dir: grammars_dir,
                          tables_dir: tables_dir, parsanol_version: parsanol_version)
          FileUtils.mkdir_p(File.dirname(artifact_out))
          File.binwrite(artifact_out, JSON.generate(envelope))

          # 4. Re-verify against the BAKED artifact — what actually ships.
          baked = Parsanol::PARG::Artifact.new(envelope, nil, tables_dir,
                                               imports_dir: grammars_dir)
          verify_against_baked(definition, baked, captures)

          # 5. Optional Ruby flavor emission.
          ruby_files = ruby_out && RubyGenerator.emit(
            definition, flavor_key: flavor_key, dir: ruby_out,
            parsanol_version: parsanol_version,
          )

          Result.new(
            definition: definition,
            grammar_path: grammar_out,
            grammar_text: grammar_text,
            artifact_path: artifact_out,
            envelope: envelope,
            captures: captures,
            ruby_files: ruby_files || [],
          )
        end

        # Parse, bind and render every declared example against a compiled
        # document. Failures cite the example row.
        # @return [Hash{String => Hash{String => String}}] input → captures
        def verify_examples(definition, grammar_text, grammars_dir:, tables_dir:)
          document = Parsanol::PARG::Parser.new(grammar_text).parse
          Parsanol::PARG::Imports.merge!(document, [grammars_dir])
          envelope = Parsanol::PARG::Compiler.compile(document, tables_dir: tables_dir).envelope
          artifact = Parsanol::PARG::Artifact.new(envelope, nil, tables_dir,
                                                  imports_dir: grammars_dir)

          canonical = definition.templates[:canonical].sequences.first
          captures = {}
          definition.examples[:positives].each_with_index do |row, i|
            rule = "examples.positives[#{i}]"
            bound = parse_positive(artifact, row.input, rule)
            captures[row.input] = bound

            render = Template.render_sequence(
              canonical, bound.transform_keys(&:to_s), rule: "templates.canonical"
            )
            if row.renders && row.renders != render
              raise ExampleFailure.new(
                rule,
                "input #{row.input.inspect} renders #{render.inspect} under the " \
                "canonical template, not the declared #{row.renders.inspect}",
              )
            end
          end

          definition.examples[:negatives].each_with_index do |input, i|
            rule = "examples.negatives[#{i}]"
            begin
              artifact.parse(ENTRY, input)
            rescue Parsanol::ParseFailed
              next # the expected outcome
            rescue Parsanol::PARG::Error
              raise ExampleFailure.new(rule,
                                       "input #{input.inspect} parses but fails to " \
                                       "bind — an accept/reject mismatch, not a reject")
            else
              raise ExampleFailure.new(rule,
                                       "negative input #{input.inspect} parses — " \
                                       "the grammar accepts what the definition rejects")
            end
          end

          captures
        end

        def parse_positive(artifact, input, rule)
          shape = artifact.parse(ENTRY, input)
          artifact.apply_bindings(ENTRY, shape)
        rescue Parsanol::PARG::Error, Parsanol::ParseFailed => e
          raise ExampleFailure.new(rule,
                                   "input #{input.inspect} does not parse: " \
                                   "#{e.message[0, 120]}")
        end

        def bake(grammar_path, grammars_dir:, tables_dir:, parsanol_version:)
          document = Parsanol::PARG::Parser.new(File.read(grammar_path)).parse
          Parsanol::PARG::Imports.merge!(document, [grammars_dir])
          envelope = Parsanol::PARG::Compiler.compile(document, tables_dir: tables_dir).envelope

          stamp = envelope["compiler_version"]
          unless stamp == parsanol_version
            raise BakeError,
                  "compiler stamp #{stamp.inspect} != pinned #{parsanol_version.inspect} " \
                  "— activate the pinned engine (gem \"parsanol\", #{parsanol_version.inspect})"
          end

          failures = Parsanol::PARG::Artifact.new(envelope, nil, tables_dir,
                                                  imports_dir: grammars_dir).run_tests
          unless failures.empty?
            raise BakeError,
                  "embedded tests failed after bake: #{failures.first(3).join(' | ')}"
          end

          envelope
        end

        def verify_against_baked(definition, baked, captures)
          definition.examples[:positives].each_with_index do |row, i|
            rule = "examples.positives[#{i}]"
            bound = parse_positive(baked, row.input, rule)
            next if bound == captures[row.input]

            raise ExampleFailure.new(rule,
                                     "the baked artifact binds #{bound.inspect} for " \
                                     "#{row.input.inspect}, but the compile-time " \
                                     "verification recorded #{captures[row.input].inspect}")
          end
        end
        end
      end
    end
  end
end
