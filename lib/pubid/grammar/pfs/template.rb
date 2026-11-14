# frozen_string_literal: true

module Pubid
  module Grammar
    module Pfs
      # The template term language — the declarative surface that drives
      # both the accept templates (canonical + alternates) and the render
      # face of a scheme.
      #
      #   "doi:" {prefix} "/" {suffix}            literals + field captures
      #   [url_prefix] [scheme_prefix] [slash] …  optional segments (rule refs)
      #   "https://" / "http://"                  alternation (a / b)
      #
      # Alternation splits on ` / ` outside quotes and brackets; brackets
      # hold a nested template (which may itself alternate); braces name a
      # declared field; a quoted string is a literal; a bare word is a
      # reference to a `grammar:` rule. Everything else is a definition
      # error citing the template.
      module Template
        # A literal chunk of the identifier face.
        Lit = Struct.new(:text)
        # A `{field}` capture reference.
        Field = Struct.new(:name)
        # A bare-word reference to a `grammar:` rule.
        Ref = Struct.new(:name)
        # A `[ … ]` optional segment holding a nested template.
        Opt = Struct.new(:inner)
        # A `( … )` REQUIRED group holding a nested template — the head
        # dispatch whose alternatives each capture (issue #121): the face
        # renders the first alternative whose direct fields captured, and
        # an all-miss group is a compile error (the examples panel pins
        # it), never a silent empty render.
        Group = Struct.new(:inner)
        # The whole template: alternatives (each a sequence of items).
        Alt = Struct.new(:sequences)

        class TemplateError < InvalidDefinition; end

        NAME = /\A[a-z][a-z0-9_]*\z/

        module_function

        # @param text [String] the template as written in the definition
        # @param rule [String] the citing rule (section path) on failure
        # @return [Alt]
        def parse(text, rule:)
          sequences = split_alternation(text, rule).map { |s| parse_sequence(s, rule) }
          Alt.new(sequences)
        end

        # The PARG term for one sequence: items joined by single spaces.
        # +field_namer+ maps a field name to its capture rule (the
        # generator rewrites `{prefix}` to `doi_prefix`); bare by default.
        # @return [String]
        def emit_sequence(sequence, field_namer: ->(name) { name })
          sequence.map { |item| emit_item(item, field_namer) }.join(" ")
        end

        # The PARG term for one template item. An optional whose inner
        # template alternates is parenthesized: `[( a / b )]`; a required
        # group emits its alternation directly: `( a / b )`.
        # @return [String]
        def emit_item(item, field_namer)
          case item
          when Lit then "\"#{item.text.gsub('"', '\\"')}\""
          when Field then field_namer.call(item.name)
          when Ref then item.name
          when Opt
            inner = emit_alternatives(item.inner, field_namer: field_namer)
            body = inner.size == 1 ? inner.first : "( #{inner.join(' / ')} )"
            "[#{body}]"
          when Group
            inner = emit_alternatives(item.inner, field_namer: field_namer)
            body = inner.size == 1 ? inner.first : "( #{inner.join(' / ')} )"
            body
          end
        end

        # The alternatives of a template as PARG terms.
        # @return [Array<String>]
        def emit_alternatives(template, field_namer: ->(name) { name })
          template.sequences.map { |seq| emit_sequence(seq, field_namer: field_namer) }
        end

        # The render face of a CANONICAL template: its single sequence with
        # fields substituted. An optional segment is a PRESENCE GUARD: it
        # renders its first alternative whose fields all captured (an
        # absent optional leaves no bytes — no stray separators), which is
        # the tier-A declarable rendering surface (#706 §2: presence
        # guards, never value branches). Phase 3 adds the composition
        # kinds the presence of a capture drives: a LIST field renders
        # through its `render:` composition (prefix glues each item
        # before itself, infix joins them), a fold's source capture
        # renders when the run matched it, and the supplement run renders
        # its notations ("/A1/C1").
        #
        # @param values [Hash{String => ...}] capture name → value
        # @param fields [Array<Definition::Field>] the declared fields
        # @return [String]
        def render_sequence(sequence, values, rule:, fields: [])
          sequence.filter_map do |item|
            case item
            when Lit then item.text
            when Field
              field_value(item.name, values, fields, rule)
            when Opt
              face = selected_face(item, values, fields)
              next nil unless face

              render_sequence(face, values, rule: rule, fields: fields)
            when Group
              face = selected_face(item, values, fields)
              if face.nil?
                raise TemplateError.new(rule),
                      "the required head group matched no alternative — every " \
                      "face alternative missed its fields"
              end

              render_sequence(face, values, rule: rule, fields: fields)
            when Ref
              raise TemplateError.new(rule),
                    "grammar rule #{item.name} cannot appear in a render face"
            end
          end.join
        end
        # The rendered value of one {field}: a plain capture renders whole
        # (through its `map:` token→value and value→face maps — the
        # draft-stage spellings), a list renders through its composition,
        # the supplement run renders its notations. Absent at a TOP-LEVEL
        # position is the compile error (the face needs the capture);
        # inside an optional the presence guard already gated the call.
        def field_value(name, values, fields, rule)
          field = fields.find { |f| f.name == name }
          value = values[name]
          if field && field.kind == "list"
            return list_render(field, value)
          end
          unless present?(value)
            raise TemplateError.new(rule),
                  "no captured value for field {#{name}}"
          end
          value = field.map.fetch(value.to_s) if field&.map
          value = field.render.fetch(value.to_s) if field&.render.is_a?(Hash)
          value.to_s
        end

        # A list capture's rendered composition: the item values pulled
        # out of the bound rows, glued per the declared style. An empty
        # run renders "" (a list's emptiness IS its absence).
        def list_render(field, value)
          return "" unless present_list?(value)

          items = value.map { |row| list_item_value(field, row) }.compact
          case field.render&.style
          when "infix"
            items.join(field.render.glue)
          else # prefix (the default — the parts-run shape)
            items.map { |item| "#{field.render&.glue}#{item}" }.join
          end
        end

        # One bound list row's item value: a plain item capture's span, or
        # the supplement run's printed notation. The flat run row (etsi:
        # kind face + ordinal) composes "A1"; the per-wrapper row (cen:
        # separator + kind face + optional ordinal + date columns)
        # composes "/A1:2005" / "+AC:2016-11" — the wrapper node descends
        # one level, and every absent piece leaves no bytes.
        def list_item_value(field, row)
          if field.builder_only
            inner = row[:supplement] || row["supplement"] || {}
            inner = inner.values.first if inner.is_a?(Hash) && inner.values.all?(Hash)

            kind = inner[:supplement_kind] || inner["supplement_kind"]
            return nil unless kind

            number = inner[:supplement_number] || inner["supplement_number"]
            sep = inner[:supplements_slash] || inner["supplements_slash"] ||
                  (inner[:supplements_plus] || inner["supplements_plus"] ? "+" : "")
            year = inner[:supplements_year] || inner["supplements_year"]
            month = inner[:supplements_month] || inner["supplements_month"]
            return "#{sep}#{kind}#{number}#{year ? ":#{year}" : ''}#{month ? "-#{month}" : ''}"
          end
          key = field.item.to_sym
          row[key] || row[key.to_s]
        end

        # The face an optional renders: its first alternative whose DIRECT
        # fields all captured, else nil (nothing renders). Nested
        # optionals do NOT gate the parent's selection — they decide
        # their own presence inside the rendered face (an absent nested
        # optional leaves no bytes). A single-sequence optional is the
        # plain presence guard.
        def selected_face(opt, values, fields)
          opt.inner.sequences.find do |seq|
            seq.all? do |item|
              case item
              when Field then present_value?(item.name, values, fields)
              else true
              end
            end
          end
        end

        # True when every field DIRECTLY inside +opt+ captured — the
        # presence guard is top-down: an optional gates on its own direct
        # fields, and a nested optional decides its own presence inside
        # the rendered face. An optional with no direct fields renders
        # unconditionally (a vacuous guard), letting the nested guards
        # decide. Lists are present when their items are non-empty.
        def opt_present?(opt, values, fields = [])
          direct_fields(opt).all? { |name| present_value?(name, values, fields) }
        end

        def present_value?(name, values, fields)
          field = fields.find { |f| f.name == name }
          value = values[name]
          if field&.kind == "list"
            return present_list?(value)
          end
          present?(value)
        end

        def present_list?(value)
          value.is_a?(Array) && value.any?
        end

        def present?(value)
          !(value.nil? || value == "" || (value.respond_to?(:empty?) && value.empty?))
        end

        # Every {field} name anywhere inside an item — the validator's
        # signal set (a canonical optional must reference a field).
        def fields_in(item)
          case item
          when Field then [item.name]
          when Opt, Group then item.inner.sequences.flat_map { |seq| seq.flat_map { |i| fields_in(i) } }
          else []
          end
        end

        # The {field} names on an optional's own level: the fields of its
        # sequences' items, NOT descending into nested optionals.
        def direct_fields(opt)
          opt.inner.sequences.flat_map do |seq|
            seq.map do |item|
              item.is_a?(Field) ? item.name : nil
            end.compact
          end
        end

        # A comparable structure for duplicate/overlap detection.
        def structural_key(template)
          [:alt, template.sequences.map { |seq| [:seq, seq.map { |i| item_key(i) }] }]
        end

        def item_key(item)
          case item
          when Lit then [:lit, item.text]
          when Field then [:field, item.name]
          when Ref then [:ref, item.name]
          when Opt then [:opt, structural_key(item.inner)]
          when Group then [:group, structural_key(item.inner)]
          end
        end

        # True when two templates are structurally identical — the
        # overlapping-alternates error.
        def same_structure?(a, b)
          structural_key(a) == structural_key(b)
        end

        def split_alternation(text, rule)
          parts = []
          current = +""
          depth = 0
          paren = 0
          quote = false
          i = 0
          while i < text.length
            case text[i]
            when '"'
              quote = !quote
              current << text[i]
            when "[" then depth += 1; current << text[i]
            when "]"
              depth -= 1
              raise TemplateError.new(rule), "unbalanced ']'" if depth.negative?

              current << text[i]
            when "(" then paren += 1; current << text[i]
            when ")"
              paren -= 1
              raise TemplateError.new(rule), "unbalanced ')'" if paren.negative?

              current << text[i]
            when " "
              if depth.zero? && paren.zero? && !quote && text[i, 3] == " / "
                parts << current
                current = +""
                i += 3
                next
              end
              current << text[i]
            else
              current << text[i]
            end
            i += 1
          end
          raise TemplateError.new(rule), "unbalanced quote" if quote
          raise TemplateError.new(rule), "unclosed '['" if depth.positive?
          raise TemplateError.new(rule), "unclosed '('" if paren.positive?

          parts << current
          parts
        end

        def parse_sequence(text, rule)
          items = []
          i = 0
          while i < text.length
            case text[i]
            when " "
              i += 1
            when '"'
              close = text.index('"', i + 1)
              raise TemplateError.new(rule), "unbalanced quote" if close.nil?

              literal = text[(i + 1)...close]
              raise TemplateError.new(rule), "empty literal" if literal.empty?

              items << Lit.new(literal)
              i = close + 1
            when "{"
              close = text.index("}", i + 1)
              raise TemplateError.new(rule), "unclosed '{'" if close.nil?

              name = text[(i + 1)...close]
              unless NAME.match?(name)
                raise TemplateError.new(rule),
                      "field reference {#{name}} is not a field name"
              end

              items << Field.new(name)
              i = close + 1
            when "["
              close = matching_bracket(text, i, rule)
              inner = text[(i + 1)...close]
              raise TemplateError.new(rule), "empty optional segment" if inner.strip.empty?

              items << Opt.new(parse(inner, rule: rule))
              i = close + 1
            when "("
              close = matching_paren(text, i, rule)
              inner = text[(i + 1)...close]
              raise TemplateError.new(rule), "empty required group" if inner.strip.empty?

              items << Group.new(parse(inner, rule: rule))
              i = close + 1
            when /[A-Za-z]/
              word = text[i..].sub(/\A([A-Za-z][A-Za-z0-9_]*).*/, '\1')
              unless NAME.match?(word)
                raise TemplateError.new(rule),
                      "rule reference #{word.inspect} is not a rule name"
              end

              items << Ref.new(word)
              i += word.length
            else
              raise TemplateError.new(rule),
                    "unexpected character #{text[i].inspect} in template"
            end
          end
          raise TemplateError.new(rule), "empty template" if items.empty?

          items
        end

        def matching_paren(text, open, rule)
          depth = 0
          quote = false
          text[open..].each_char.with_index do |char, offset|
            case char
            when '"' then quote = !quote
            when "("
              depth += 1 unless quote
            when ")"
              unless quote
                depth -= 1
                return open + offset if depth.zero?
              end
            end
          end
          raise TemplateError.new(rule), "unclosed '('"
        end

        def matching_bracket(text, open, rule)
          depth = 0
          quote = false
          text[open..].each_char.with_index do |char, offset|
            case char
            when '"' then quote = !quote
            when "["
              depth += 1 unless quote
            when "]"
              unless quote
                depth -= 1
                return open + offset if depth.zero?
              end
            end
          end
          raise TemplateError.new(rule), "unclosed '['"
        end
      end
    end
  end
end
