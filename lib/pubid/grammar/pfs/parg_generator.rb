# frozen_string_literal: true

require "json"

module Pubid
  module Grammar
    module Pfs
      # Emits the PARG edition-2 grammar source from a validated definition.
      #
      # Edition-2 formatting discipline is the COMPILER's job (issue #706
      # §3): brace bodies for multi-alternative rules, one alternative per
      # line, comments above constructs, single-line terms everywhere else.
      # The body never writes a rule.
      class PargGenerator
        ENTRY = "identifier"

        # @param definition [Definition::Root]
        # @param flavor_key [String] e.g. "doi_pfs"
        # @param captures [Hash{String => String}] positive-example capture
        #   values (filled by the compiler after verification; drive the
        #   `example` rows of the test block)
        def initialize(definition, flavor_key:, captures: {})
          @definition = definition
          @flavor_key = flavor_key
          @module_name = self.class.module_name(flavor_key)
          @captures = captures
        end

        def self.module_name(flavor_key)
          flavor_key.split("_").map(&:capitalize).join
        end

        # @param body_only [Boolean] skip the test block (the compiler
        #   verifies against a body-only document first, because the
        #   example rows are DERIVED from that verification)
        def generate(body_only: false)
          lines = []
          lines.concat(header)
          lines << ""
          lines << "grammar Pubid#{@module_name} version \"0.1.0\" edition 2 {"
          lines.concat(fragments)
          lines.concat(field_rules)
          lines.concat(identifier_rule)
          lines.concat(bindings)
          lines.concat(test_block) unless body_only
          lines << "}"
          lines.join("\n") << "\n"
        end

        private

        def header
          [
            "# PFS-generated grammar — DO NOT EDIT BY HAND.",
            "# Source: #{@definition.source_path} (pfs:#{Pfs::SCHEMA_VERSION}) " \
            "sha256:#{@definition.source_sha}",
            "# Compiler: pubid/grammar/pfs #{Pfs::VERSION}",
            "# Flavor key: #{@flavor_key} (grammar Pubid#{@module_name})",
            "# Regenerate: ruby scripts/pfs compile #{@definition.source_path} --as #{@flavor_key}",
          ]
        end

        def fragments
          return [] if @definition.grammar.empty?

          lines = ["", "  # Grammar fragments: named lexical terms declared under `grammar:`."]
          @definition.grammar.each do |name, term|
            lines << "  #{name} = #{term}"
          end
          lines
        end

        def field_rules
          lines = ["", "  # Fields: one capture rule per declared field; the whole pattern", "  # is the capture."]
          @definition.fields.each do |field|
            lines << "  #{@definition.scheme}_#{field.name} = (#{field.pattern}) as #{field.name}"
          end
          lines
        end

        def identifier_rule
          namer = ->(name) { "#{@definition.scheme}_#{name}" }
          alternatives = Template.emit_alternatives(@definition.templates[:canonical], field_namer: namer) +
            @definition.templates[:alternates].flat_map do |alt|
              Template.emit_alternatives(alt, field_namer: namer)
            end
          lines = [
            "",
            "  # Identifier rule: the canonical template first, then the",
            "  # declared alternates (parse-in spellings; they normalize to the",
            "  # canonical render face).",
          ]
          if alternatives.size == 1
            lines << "  #{ENTRY} = #{alternatives.first}"
          else
            lines << "  #{ENTRY} = {"
            alternatives.each_with_index do |term, i|
              lines << (i.zero? ? "    #{term}" : "    / #{term}")
            end
            lines << "  }"
          end
          lines << "  entry #{ENTRY}: #{ENTRY}"
          lines
        end

        def bindings
          lines = [
            "",
            "  # Typed model bindings: every bound capture lands on the",
            "  # consumer model's field of the same name.",
            "  bindings #{ENTRY} {",
          ]
          @definition.fields.each do |field|
            lines << "    #{field.name} -> #{field.name} (#{field.kind})"
          end
          lines << "  }"
          lines
        end

        def test_block
          lines = [
            "",
            "  # REQUIRED examples from the definition — accepts, rejects, and",
            "  # the capture expectations the compiler replayed at compile time.",
            "  test {",
          ]
          @definition.examples[:positives].each do |row|
            lines << "    accept #{quote(row.input)}"
          end
          @definition.examples[:negatives].each do |input|
            lines << "    reject #{quote(input)}"
          end
          @definition.examples[:positives].each do |row|
            captures = @captures[row.input]
            next unless captures

            body = captures.map { |k, v| "#{k}: #{JSON.generate(v)}" }.join(" ")
            lines << "    example #{quote(row.input)} { #{body} }"
          end
          lines << "  }"
          lines
        end

        def quote(string)
          JSON.generate(string)
        end
      end
    end
  end
end
