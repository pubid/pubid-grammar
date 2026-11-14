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
          lines = [
            "# PFS-generated grammar — DO NOT EDIT BY HAND.",
            "# Source: #{@definition.source_path} (pfs:#{Pfs::SCHEMA_VERSION}) " \
            "sha256:#{@definition.source_sha}",
            "# Compiler: pubid/grammar/pfs #{Pfs::VERSION}",
            "# Flavor key: #{@flavor_key} (grammar Pubid#{@module_name})",
            "# Regenerate: ruby scripts/pfs compile #{@definition.source_path} --as #{@flavor_key}",
          ]
          @definition.modules.each do |mod|
            lines << "# Module: #{mod.name} v#{mod.version} " \
                     "(sha256:#{mod.source_sha[0, 12]}...)"
          end
          lines
        end

        def fragments
          return [] if @definition.grammar.empty?

          lines = ["", "  # Grammar fragments: named lexical terms declared under `grammar:`."]
          @definition.grammar.each do |name, term|
            lines << "  #{name} = #{term}"
          end
          lines
        end

        # The supplement-run fields the compiler generated (run, item,
        # kind, number, and the declared date columns): their rules come
        # from the supplements section, not from the (partial) field
        # patterns.
        def supplements_generated?(field)
          supplements = @definition.supplements
          return false unless supplements

          ([supplements.run, supplements.item, supplements.kind,
            supplements.number] +
            supplements.date.map { |column| generated_date_name(supplements, column) })
            .include?(field.name)
        end

        def field_rules
          lines = ["", "  # Fields: one capture rule per declared field; the whole pattern", "  # is the capture."]
          claimed_items = @definition.fields
            .select { |f| f.kind == "list" && f.item }.map(&:item)
          @definition.fields.each do |field|
            next if supplements_generated?(field)
            # A list's item capture emits with its list (one rule, then the
            # repetition that binds it per match).
            next if claimed_items.include?(field.name)

            if field.kind == "list" && field.item
              # A list field binds its item capture per repetition: the
              # item rule first (the list's pattern references it), then
              # the list rule — both carry semantic names (the
              # named-segments rule).
              item = @definition.fields.find { |f| f.name == field.item }
              lines << "  #{@definition.scheme}_#{item.name} = (#{item.pattern}) as #{item.name}"
              lines << "  #{@definition.scheme}_#{field.name} = (#{field.pattern}) as #{field.name}"
            else
              lines << "  #{@definition.scheme}_#{field.name} = (#{field.pattern}) as #{field.name}"
            end
          end
          lines.concat(supplement_run_rules)
          lines
        end

        # The supplement run's rules, generated whole from the
        # supplements declaration (the declaration IS the run's shape —
        # the grammar and the fold can never drift apart). Every rule
        # carries its semantic name.
        #
        # Two shapes, by declaration: the phase-3 flat shape (kind rule +
        # number rule + one slash item — etsi) and the issue-#121 feature-3
        # shape for cen's wrapper forms: a separator capture ("/"
        # standalone vs "+" consolidated), per-wrapper item rules (so the
        # raw row names the kind's rule), an optional ordinal
        # (`number_optional` — the unnumbered "/AC"), string ordinals
        # (`number_kind: string`), and the wrapper-owned date columns
        # (`date: [year, month]`).
        def supplement_run_rules
          supplements = @definition.supplements
          return [] unless supplements

          return extended_run_rules(supplements) if extended_shape?(supplements)

          scheme = @definition.scheme
          faces = supplements.wrappers.map { |w| "\"#{w.face}\"" }.join(" / ")
          [
            "",
            "  # Supplement run (compiled from the supplements declaration):",
            "  # each item binds its kind face and ordinal; the builder folds",
            "  # the run into the declared wrapper classes.",
            "  #{scheme}_#{supplements.kind} = (#{faces}) as #{supplements.kind}",
            "  #{scheme}_#{supplements.number} = (1*digit) as #{supplements.number}",
            "  #{scheme}_#{supplements.item} = ( \"/\" #{scheme}_#{supplements.kind} " \
              "#{scheme}_#{supplements.number} ) as #{supplements.item}",
            "  #{scheme}_#{supplements.run} = (1*#{scheme}_#{supplements.item}) as #{supplements.run}",
          ]
        end

        # The wrapper's date capture name: the run-internal
        # `supplement_year`-shaped capture (the run name + the column).
        def generated_date_name(supplements, column)
          "#{supplements.run}_#{column}"
        end

        # The lexical tail of a wrapper date column inside the run.
        def date_column_pattern(column)
          case column
          when "year" then "4digit"
          when "month" then "2digit"
          end
        end

        # The extended shape: any of the cen wrapper declarations present.
        def extended_shape?(supplements)
          supplements.number_kind == "string" ||
            supplements.wrappers.any?(&:number_optional) ||
            !supplements.date.empty? || supplements.consolidated ||
            supplements.fragment
        end

        def extended_run_rules(supplements)
          scheme = @definition.scheme
          lines = [
            "",
            "  # Supplement run (compiled from the supplements declaration):",
            "  # each item binds its separator, kind face, ordinal and date",
            "  # columns; the builder folds the run into the declared wrapper",
            "  # classes (the slash run standalone, the plus run consolidated).",
            "  #{scheme}_#{supplements.number} = (1*digit) as #{supplements.number}",
          ]
          supplements.date.each do |column|
            name = generated_date_name(supplements, column)
            lines << "  #{scheme}_#{name} = (#{date_column_pattern(column)}) as #{name}"
          end
          # The item alternation orders by DESCENDING face length — a
          # face that extends another ("AC" of "A") must try first, or the
          # shorter face commits and the longer one can never match.
          supplements.wrappers.sort_by { |w| -w.face.length }.each do |wrapper|
            tail = extended_date_tail(supplements, wrapper)
            number_term = if wrapper.number_optional
              "[#{scheme}_#{supplements.number}]"
            else
              "#{scheme}_#{supplements.number}"
            end
            lines << "  #{scheme}_#{supplements.item}_#{wrapper.name} = {"
            lines << "    (\"/\" as #{supplements.run}_slash / \"+\" as #{supplements.run}_plus)"
            lines << "    \"#{wrapper.face}\" as #{supplements.kind} #{number_term}#{tail}"
            lines << "  }"
          end
          item_refs = supplements.wrappers.sort_by { |w| -w.face.length }.map do |wrapper|
            "#{scheme}_#{supplements.item}_#{wrapper.name}"
          end
          lines << "  #{scheme}_#{supplements.item} = ( #{item_refs.join(' / ')} ) as #{supplements.item}"
          lines << "  #{scheme}_#{supplements.run} = (1*#{scheme}_#{supplements.item}) as #{supplements.run}"
          lines
        end

        # The item's date tail: the wrapper's declared calendar columns in
        # order — ":" + the year capture, then "-" + the month capture.
        # A wrapper that declares no month never captures one.
        def extended_date_tail(supplements, wrapper)
          scheme = @definition.scheme
          tail = +""
          if supplements.date.include?("year") && wrapper.fields.include?("year")
            tail << " [\":\" #{scheme}_#{generated_date_name(supplements, 'year')}]"
          end
          if supplements.date.include?("month") && wrapper.fields.include?("month")
            tail << " [\"-\" #{scheme}_#{generated_date_name(supplements, 'month')}]"
          end
          tail
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
            lines.concat(binding_lines(field))
          end
          lines << "  }"
          lines
        end

        # One field's binding rows. A list binds its ITEM capture per
        # repetition (`item -> list[].item`); the supplement run binds its
        # item capture as raw (the fold walks the rows); the run's
        # internal captures bind only through that array — no flat rows
        # for them.
        def binding_lines(field)
          if supplements_generated?(field)
            supplements = @definition.supplements
            return [] unless field.name == supplements.run

            return ["    #{supplements.item} -> #{supplements.run}[].#{supplements.item} (raw)"]
          end
          if field.kind == "list" && field.item
            return ["    #{field.item} -> #{field.name}[].#{field.item} (string)"]
          end
          ["    #{field.name} -> #{field.name} (#{field.kind})"]
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

            # The test block's example rows carry scalar capture
            # expectations (the engines' test-object syntax is flat) — a
            # row whose bound shape nests (the supplement run's items, a
            # list's rows) is verified at COMPILE time (verify_examples)
            # and left out of the embedded panel.
            scalars = captures.select { |_k, v| v.is_a?(String) || v.is_a?(Integer) }
            next if scalars.empty?

            body = scalars.map { |k, v| "#{k}: #{JSON.generate(v)}" }.join(" ")
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
