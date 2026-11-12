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
        # template alternates is parenthesized: `[( a / b )]`.
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
          end
        end

        # The alternatives of a template as PARG terms.
        # @return [Array<String>]
        def emit_alternatives(template, field_namer: ->(name) { name })
          template.sequences.map { |seq| emit_sequence(seq, field_namer: field_namer) }
        end

        # The render face of a CANONICAL template: its single sequence with
        # fields substituted. An optional segment is a PRESENCE GUARD: it
        # renders its inner face iff EVERY field inside captured (an absent
        # optional leaves no bytes — no stray separators), which is the
        # tier-A declarable rendering surface (#706 §2: presence guards,
        # never value branches).
        # @param values [Hash{String => String}] capture name → value
        # @return [String]
        def render_sequence(sequence, values, rule:)
          sequence.filter_map do |item|
            case item
            when Lit then item.text
            when Field
              value = values[item.name]
              unless value
                raise TemplateError.new(rule),
                      "no captured value for field {#{item.name}}"
              end
              value.to_s
            when Opt
              next nil unless opt_present?(item, values)

              render_sequence(item.inner.sequences.first, values, rule: rule)
            when Ref
              raise TemplateError.new(rule),
                    "grammar rule #{item.name} cannot appear in a render face"
            end
          end.join
        end

        # True when every field DIRECTLY inside +opt+ captured — the
        # presence guard is top-down: an optional gates on its own direct
        # fields, and a nested optional decides its own presence inside
        # the rendered face. An optional with no direct fields renders
        # unconditionally (a vacuous guard), letting the nested guards
        # decide.
        def opt_present?(opt, values)
          direct_fields(opt).all? { |name| values[name] }
        end

        # Every {field} name anywhere inside an item — the validator's
        # signal set (a canonical optional must reference a field).
        def fields_in(item)
          case item
          when Field then [item.name]
          when Opt then item.inner.sequences.flat_map { |seq| seq.flat_map { |i| fields_in(i) } }
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
            when " "
              if depth.zero? && !quote && text[i, 3] == " / "
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
