# frozen_string_literal: true

module Pubid
  module Grammar
    module Pfs
      # `pfs capture` — the lossless wizard substrate (issue #152).
      #
      # The loop the wizard (#406) automates, in its substrate form:
      #
      #   capture  — the body's specimen identifiers enter as DATA, one
      #              per line, strings preserved verbatim (the lossless
      #              intake: no transcription, no quoting surprises, a
      #              round-trip check closes the intake)
      #   draft    — the captured rows are emitted into the REQUIRED
      #              examples format inside a draft schema (the smallest
      #              tier-A skeleton the rows drop into)
      #   verify   — `pfs lint` (pre-compile) then `pfs compile` (the
      #              engine): every positive must parse and render, every
      #              negative must fail — the loop the composer iterates
      #              until green
      #
      # This module is the substrate only: the intake + the draft
      # emission. The interactive wizard arrives later, on top of these
      # primitives.
      module Capture
        module_function

        # @param input [String] raw text: one identifier per line; blank
        #   lines and #-comments are skipped, everything else is captured
        #   verbatim
        # @return [Array<String>] the captured identifiers, order preserved
        def read_inputs(text)
          text.lines.filter_map do |line|
            line = line.chomp
            next if line.strip.empty?
            next if line.lstrip.start_with?("#")

            line
          end
        end

        # The REQUIRED-format examples block: every identifier a positive
        # row whose `renders:` starts as the identity (the canonical face
        # is the captured spelling until the composer's template says
        # otherwise — the compile-time verification is what narrows it).
        # @raise [Error] when a row would not round-trip through the
        #   strict loader losslessly
        def examples_block(inputs)
          inputs.map { |input| "    - input: #{yaml_string(input)}\n      renders: #{yaml_string(input)}" }
                .join("\n")
        end

        # The draft schema: the smallest tier-A skeleton with the captured
        # rows in the REQUIRED format. Not green by design — the verify
        # loop (lint, then compile) is what shapes the grammar until it is.
        def draft(scheme:, title:, publisher:, inputs:)
          raise Error, "scheme #{scheme.inspect} must be a lower-case " \
                       "snake_case key" unless scheme.match?(Validator::SCHEME)
          if title.match?(/["\\]/)
            raise Error, "title #{title.inspect} must not contain quotes or backslashes"
          end

          <<~PFS
            # #{title} — the capture draft (`pfs capture`), the wizard substrate.
            #
            # The body's specimen identifiers are captured below, losslessly
            # (each row is the captured string, verbatim). This draft does NOT
            # compile yet: its grammar is the barest skeleton and its renders
            # assume the identity. The loop:
            #
            #   ruby scripts/pfs lint #{scheme}.pfs          # pre-compile diagnostics
            #   ruby scripts/pfs compile #{scheme}.pfs --as #{scheme}_pfs \\
            #     --parsanol-version <fleet pin>            # the verify step
            #
            # Shape `grammar:`/`fields:`/`templates:` until every positive
            # parses and renders as declared and every negative fails. Then
            # grow the real surface (see definitions/README.md, the language
            # reference; ruby scripts/pfs new scaffolds the composed form).

            pfs: 1

            scheme: #{scheme}
            title: "#{title}"

            organization:
              name: "#{title}"
              publisher: "#{publisher}"
              prefixes: [#{prefix_list(publisher, inputs)}]

            grammar:
              digit: "%x30-39"
              printable: "%x21-7E"

            types:
              base:
                key: #{scheme}
                title: "#{title}"
                tag: "pubid:#{scheme}:base"

            fields:
              # The stub capture: the whole identifier minus the scheme
              # prefix. Replace with the real columns (number, part, year...)
              # as the loop narrows the shape.
              body:
                pattern: "1*printable"
                kind: string

            templates:
              canonical: '"#{publisher} " {body}'

            urn:
              namespace: #{scheme}
              schema:
                atoms: []
                types:
                  - { type: "pubid:#{scheme}:base", token: id, core: [] }

            # REQUIRED. The captured specimen (lossless intake) — the live
            # test panel the compile verifies.
            examples:
              positives:
            #{examples_block(inputs)}
              negatives:
                - "nonsense"
          PFS
        end

        # The YAML double-quoted scalar for a captured string, and the
        # lossless guarantee: the emitted scalar must read back EXACTLY.
        # Fail closed on control characters — an identifier carrying one
        # is not a capture, it is corruption (the substrate must not emit
        # a file the strict loader would mangle).
        def yaml_string(value)
          if value.match?(/[\x00-\x1F\x7F]/)
            raise Error,
                  "captured line contains a control character " \
                  "(#{value.bytes.select { |b| b < 0x20 || b == 0x7F }.map { |b| format("%02X", b) }.join(' ')}) " \
                  "— not a capturable identifier"
          end

          escaped = value.gsub("\\") { "\\\\" }.gsub('"') { '\\"' }
          %("#{escaped}")
        end

        # Round-trip proof for one emitted file: strict-load and compare
        # every captured row. Raises on any loss.
        def verify_lossless(path, inputs)
          raw = Loader.load(path)
          rows = raw.dig("examples", "positives") || []
          got = rows.map { |row| row.is_a?(Hash) ? row["input"] : row }
          unless got == inputs
            raise Error,
                  "the capture draft is not lossless — captured #{inputs.size} rows, " \
                  "the emitted file reads back #{got.size}: #{got.first(3).inspect}"
          end
          true
        end

        def prefix_list(publisher, inputs)
          harvested = inputs.filter_map do |input|
            head = input[/\A[^0-9\s]+/]
            head if head&.match?(Validator::TOKEN)
          end
          ([publisher] + harvested).uniq.first(8).map { |t| yaml_string(t) }.join(", ")
        end
      end
    end
  end
end
