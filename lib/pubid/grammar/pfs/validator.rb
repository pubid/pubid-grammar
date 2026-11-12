# frozen_string_literal: true

module Pubid
  module Grammar
    module Pfs
      # Definition validation. Every check raises {InvalidDefinition} with
      # the citing rule — the section path of the offending declaration —
      # so the compiler's refusals are actionable (and spec-pinned).
      #
      # The v1 rules:
      #   * `pfs:` — exactly #{Pfs::SCHEMA_VERSION}; newer fails closed.
      #   * reserved tokens — `ed`, `amd`, `cor` are the edition/supplement
      #     machinery's tokens; a definition may not claim them as type
      #     keys/names, publisher or prefix tokens, or stage abbreviations.
      #   * ambiguity — two types with the same token set (key, tag, or
      #     stage abbreviation), or two structurally identical accept
      #     templates, are compile-time errors citing the conflict.
      #   * duplicate field names — rejected by the strict loader (silent
      #     last-key-wins is not a definition), plus field-vs-fragment
      #     name collisions here.
      #   * unknown keys — fail closed everywhere; `pfs:` versioning is
      #     additive, so an unknown key means a newer dialect, not noise.
      module Validator
        RESERVED_TOKENS = %w[ed amd cor].freeze
        NAME = /\A[a-z][a-z0-9_]*\z/
        TOKEN = /\A[A-Za-z][A-Za-z0-9_.\-:]*\z/
        SCHEME = /\A[a-z][a-z0-9_]*\z/
        TAG = /\Apubid:[a-z0-9_]+:[a-z0-9\-]+\z/

        TOP_LEVEL_KEYS = %w[
          pfs scheme title organization grammar types fields templates
          urn examples
        ].freeze

        module_function

        # @param raw [Hash] the strict-loaded definition
        # @param source_path [String] citing path for the header
        # @param source_sha [String] sha256 of the raw definition bytes
        # @return [Definition::Root]
        # @raise [InvalidDefinition]
        def validate(raw, source_path:, source_sha:)
          check_keys("definition", raw, TOP_LEVEL_KEYS)
          check_version(raw.fetch("pfs", nil))

          scheme = check_scheme(raw)
          organization = check_organization(raw)
          grammar = check_grammar(raw, scheme)
          types = check_types(raw, scheme)
          fields = check_fields(raw, scheme, grammar)
          templates = check_templates(raw, fields, grammar)
          urn = check_urn(raw, fields)

          Definition::Root.new(
            source_path: source_path,
            source_sha: source_sha,
            scheme: scheme,
            title: raw["title"],
            organization: organization,
            grammar: grammar,
            types: types,
            fields: fields,
            templates: templates,
            urn: urn,
            examples: check_examples_shape(raw),
          )
        end

        def check_version(value)
          unless value.is_a?(Integer)
            raise InvalidDefinition.new("pfs", "must be the integer #{Pfs::SCHEMA_VERSION}")
          end
          return if value == Pfs::SCHEMA_VERSION

          raise InvalidDefinition.new(
            "pfs",
            "definition declares pfs: #{value}; this compiler speaks pfs: " \
            "#{Pfs::SCHEMA_VERSION} (fail-closed: upgrade the compiler)",
          )
        end

        def check_scheme(raw)
          scheme = raw["scheme"]
          unless scheme.is_a?(String) && SCHEME.match?(scheme)
            raise InvalidDefinition.new("scheme",
                                        "must be a lower-case scheme key, got #{scheme.inspect}")
          end
          scheme
        end

        def check_keys(where, hash, allowed)
          return unless hash.is_a?(Hash)

          unknown = hash.keys - allowed
          return if unknown.empty?

          raise InvalidDefinition.new(
            where,
            "unknown key(s) #{unknown.map(&:inspect).join(', ')} — known: " \
            "#{allowed.join(', ')} (a key this compiler does not know means " \
            "a dialect newer than pfs:#{Pfs::SCHEMA_VERSION})",
          )
        end

        def check_organization(raw)
          org = raw["organization"]
          unless org.is_a?(Hash)
            raise InvalidDefinition.new("organization", "section is required")
          end
          check_keys("organization", org, %w[name publisher prefixes])

          name = org["name"]
          unless name.is_a?(String) && !name.empty?
            raise InvalidDefinition.new("organization.name", "must be a string")
          end

          publisher = org["publisher"]
          unless publisher.is_a?(String) && TOKEN.match?(publisher)
            raise InvalidDefinition.new(
              "organization.publisher",
              "must be a token, got #{publisher.inspect}",
            )
          end
          check_reserved("organization.publisher", publisher)

          prefixes = org["prefixes"]
          unless prefixes.is_a?(Array) && prefixes.all? do |p|
            p.is_a?(String) && !p.empty?
          end
            raise InvalidDefinition.new(
              "organization.prefixes",
              "must be an array of head-dispatch tokens",
            )
          end
          prefixes.each_with_index do |token, i|
            check_reserved("organization.prefixes[#{i}]", token)
          end

          Definition::Organization.new(
            name: name, publisher: publisher, prefixes: prefixes.freeze,
          )
        end

        def check_grammar(raw, scheme)
          fragments = raw["grammar"] || {}
          unless fragments.is_a?(Hash)
            raise InvalidDefinition.new("grammar", "must be a map of rule name → term")
          end
          fragments.each do |name, term|
            unless name.is_a?(String) && NAME.match?(name)
              raise InvalidDefinition.new("grammar.#{name}",
                                          "rule name must be lower-case snake_case")
            end
            unless term.is_a?(String) && !term.empty?
              raise InvalidDefinition.new("grammar.#{name}", "term must be a string")
            end
            unless single_line?(term)
              raise InvalidDefinition.new(
                "grammar.#{name}",
                "term spans multiple lines — edition-2 line discipline is the " \
                "compiler's job; a fragment is a single-line term",
              )
            end
            unless balanced?(term)
              raise InvalidDefinition.new("grammar.#{name}",
                                          "unbalanced quotes or brackets")
            end
          end
          fragments.freeze
        end

        def check_types(raw, scheme)
          types = raw["types"]
          unless types.is_a?(Hash) && !types.empty?
            raise InvalidDefinition.new("types", "at least one type is required")
          end

          seen_keys = {}
          seen_tags = {}
          seen_abbrs = {}
          types.map do |name, body|
            unless name.is_a?(String) && NAME.match?(name)
              raise InvalidDefinition.new("types.#{name}", "type name must be snake_case")
            end
            check_keys("types.#{name}", body, %w[key title short tag stage])

            key = body["key"]
            unless key.is_a?(String) && NAME.match?(key)
              raise InvalidDefinition.new("types.#{name}.key",
                                          "must be a lower-case token, got #{key.inspect}")
            end
            check_reserved("types.#{name}.key", key)
            if seen_keys.key?(key)
              raise InvalidDefinition.new(
                "types.#{name}.key",
                "ambiguity: type key #{key.inspect} is already claimed by type " \
                "#{seen_keys[key].inspect} — two types with identical token sets " \
                "are a compile-time error",
              )
            end
            seen_keys[key] = name

            tag = body["tag"] || "pubid:#{scheme}:#{name}"
            unless tag.is_a?(String) && TAG.match?(tag)
              raise InvalidDefinition.new("types.#{name}.tag",
                                          "must match pubid:<flavor>:<type>, got #{tag.inspect}")
            end
            if seen_tags.key?(tag)
              raise InvalidDefinition.new(
                "types.#{name}.tag",
                "ambiguity: wire tag #{tag.inspect} already claimed by " \
                "#{seen_tags[tag].inspect}",
              )
            end
            seen_tags[tag] = name

            stage = check_stage(name, body["stage"], seen_abbrs)

            Definition::Type.new(
              name: name,
              key: key,
              title: body["title"] || key,
              short: body["short"] || key,
              tag: tag,
              stage: stage,
            )
          end
        end

        def check_stage(type_name, stage, seen_abbrs)
          return nil if stage.nil?

          unless stage.is_a?(Hash)
            raise InvalidDefinition.new("types.#{type_name}.stage", "must be a map")
          end
          check_keys("types.#{type_name}.stage", stage, %w[code stage_code abbr])

          code = stage["code"]
          unless code.is_a?(String) && NAME.match?(code)
            raise InvalidDefinition.new("types.#{type_name}.stage.code",
                                        "must be a lower-case token")
          end

          stage_code = stage["stage_code"]
          unless stage_code.is_a?(String) && !stage_code.empty?
            raise InvalidDefinition.new("types.#{type_name}.stage.stage_code",
                                        "must be a harmonized stage code string")
          end

          abbrs = stage["abbr"] || []
          unless abbrs.is_a?(Array) && abbrs.all?(String) && !abbrs.empty?
            raise InvalidDefinition.new("types.#{type_name}.stage.abbr",
                                        "must be a non-empty array of spellings")
          end
          abbrs.each_with_index do |abbr, i|
            check_reserved("types.#{type_name}.stage.abbr[#{i}]", abbr)
            seen = seen_abbrs[abbr.upcase]
            if seen
              raise InvalidDefinition.new(
                "types.#{type_name}.stage.abbr[#{i}]",
                "ambiguity: abbreviation #{abbr.inspect} already claimed by type " \
                "#{seen.inspect} — two types with identical token sets are a " \
                "compile-time error",
              )
            end
            seen_abbrs[abbr.upcase] = type_name
          end

          Definition::Stage.new(
            code: code, stage_code: stage_code, abbr: abbrs.freeze,
          )
        end

        def check_fields(raw, scheme, grammar)
          fields = raw["fields"]
          unless fields.is_a?(Hash) && !fields.empty?
            raise InvalidDefinition.new("fields", "at least one field is required")
          end

          fields.map do |name, body|
            unless name.is_a?(String) && NAME.match?(name)
              raise InvalidDefinition.new("fields.#{name}", "field name must be snake_case")
            end
            if grammar.key?(name)
              raise InvalidDefinition.new(
                "fields.#{name}",
                "duplicate field name: a `grammar:` rule named #{name.inspect} " \
                "already exists — field captures compile to #{scheme}_#{name}, " \
                "but the bare name stays reserved for the fragment",
              )
            end
            check_keys("fields.#{name}", body, %w[pattern kind])

            pattern = body["pattern"]
            unless pattern.is_a?(String) && !pattern.empty?
              raise InvalidDefinition.new("fields.#{name}.pattern", "must be a term string")
            end
            unless single_line?(pattern)
              raise InvalidDefinition.new(
                "fields.#{name}.pattern",
                "pattern spans multiple lines — edition-2 line discipline is the " \
                "compiler's job",
              )
            end
            unless balanced?(pattern)
              raise InvalidDefinition.new("fields.#{name}.pattern",
                                          "unbalanced quotes or brackets")
            end

            kind = body["kind"] || "string"
            unless %w[string].include?(kind)
              raise InvalidDefinition.new(
                "fields.#{name}.kind",
                "unsupported field kind #{kind.inspect} — pfs:1 carries `string` " \
                "(int patterns are a later extension)",
              )
            end

            Definition::Field.new(name: name, pattern: pattern, kind: kind)
          end
        end

        def check_templates(raw, fields, grammar)
          templates = raw["templates"]
          unless templates.is_a?(Hash)
            raise InvalidDefinition.new("templates", "section is required")
          end
          check_keys("templates", templates, %w[canonical alternates])

          canonical_text = templates["canonical"]
          unless canonical_text.is_a?(String) && !canonical_text.empty?
            raise InvalidDefinition.new("templates.canonical",
                                        "must be the canonical template string")
          end

          canonical = Template.parse(canonical_text, rule: "templates.canonical")
          if canonical.sequences.size > 1
            raise InvalidDefinition.new(
              "templates.canonical",
              "top-level alternation cannot be a render face — put the variants " \
              "under `alternates:`",
            )
          end
          check_refs(canonical, fields, grammar, "templates.canonical")

          alternates = (templates["alternates"] || []).map.with_index do |text, i|
            unless text.is_a?(String) && !text.empty?
              raise InvalidDefinition.new("templates.alternates[#{i}]",
                                          "must be a template string")
            end
            rule = "templates.alternates[#{i}]"
            parsed = Template.parse(text, rule: rule)
            check_refs(parsed, fields, grammar, rule)

            if Template.same_structure?(parsed, canonical)
              raise InvalidDefinition.new(
                rule,
                "ambiguity: alternate is structurally identical to the canonical " \
                "template — an accept form that matches exactly what the " \
                "canonical form matches is an overlapping alternate",
              )
            end
            parsed
          end

          alternates.each_with_index do |parsed, i|
            later = alternates[(i + 1)..].index do |other|
              Template.same_structure?(other, parsed)
            end
            next unless later

            raise InvalidDefinition.new(
              "templates.alternates[#{i + 1 + later}]",
              "ambiguity: structurally identical to templates.alternates[#{i}] " \
              "— overlapping alternates are a compile-time error",
            )
          end

          { canonical: canonical, alternates: alternates }
        end

        def check_refs(template, fields, grammar, rule)
          walk(template) do |item|
            case item
            when Template::Field
              unless fields.any? { |f| f.name == item.name }
                raise InvalidDefinition.new(rule,
                                            "unknown field {#{item.name}}")
              end
            when Template::Ref
              unless grammar.key?(item.name)
                raise InvalidDefinition.new(
                  rule,
                  "unknown grammar rule #{item.name} — declare it under `grammar:`",
                )
              end
            end
          end
        end

        def check_urn(raw, fields)
          urn = raw["urn"]
          unless urn.is_a?(Hash)
            raise InvalidDefinition.new("urn", "section is required")
          end
          check_keys("urn", urn, %w[namespace schema])
          check_keys("urn.schema", urn["schema"], %w[atoms types])

          namespace = urn["namespace"]
          unless namespace.is_a?(String) && NAME.match?(namespace)
            raise InvalidDefinition.new("urn.namespace",
                                        "must be a lower-case namespace, got #{namespace.inspect}")
          end

          schema = urn["schema"] || {}
          atoms = (schema["atoms"] || []).map.with_index do |atom, i|
            rule = "urn.schema.atoms[#{i}]"
            check_keys(rule, atom, %w[path prefix kind])
            path = atom["path"]
            unless fields.any? { |f| f.name == path }
              raise InvalidDefinition.new(rule, "unknown field path #{path.inspect}")
            end
            prefix = atom["prefix"]
            unless prefix.is_a?(String) && NAME.match?(prefix)
              raise InvalidDefinition.new(rule, "prefix must be a lower-case token")
            end
            Definition::UrnAtom.new(
              path: path, prefix: prefix, kind: atom["kind"] || "string",
            )
          end

          types = (schema["types"] || []).map.with_index do |type, i|
            rule = "urn.schema.types[#{i}]"
            check_keys(rule, type, %w[type token core])
            type_str = type["type"]
            unless type_str.is_a?(String) && TAG.match?(type_str)
              raise InvalidDefinition.new(rule,
                                          "must match pubid:<flavor>:<type>")
            end
            token = type["token"]
            unless token.is_a?(String) && NAME.match?(token)
              raise InvalidDefinition.new(rule, "token must be a lower-case token")
            end
            core = type["core"] || []
            unless core.is_a?(Array) && core.all?(String)
              raise InvalidDefinition.new(rule, "core must be an array of field paths")
            end
            core.each do |path|
              unless fields.any? { |f| f.name == path }
                raise InvalidDefinition.new(rule, "unknown core field #{path.inspect}")
              end
            end
            Definition::UrnType.new(type: type_str, token: token, core: core)
          end

          tags = types.map(&:type)
          if tags.uniq.size != tags.size
            raise InvalidDefinition.new("urn.schema.types",
                                        "ambiguity: duplicate URN type declarations")
          end

          Definition::Urn.new(namespace: namespace, atoms: atoms, types: types)
        end

        def check_examples_shape(raw)
          examples = raw["examples"]
          unless examples.is_a?(Hash)
            raise InvalidDefinition.new("examples",
                                        "section is required — a definition without " \
                                        "examples does not compile (they are the " \
                                        "live test panel, not documentation)")
          end
          check_keys("examples", examples, %w[positives negatives])

          positives = examples["positives"]
          unless positives.is_a?(Array) && !positives.empty?
            raise InvalidDefinition.new("examples.positives",
                                        "at least one positive example is required")
          end

          positives = positives.map.with_index do |row, i|
            rule = "examples.positives[#{i}]"
            if row.is_a?(String)
              Definition::Positive.new(input: row, renders: nil)
            elsif row.is_a?(Hash)
              check_keys(rule, row, %w[input renders])
              input = row["input"]
              unless input.is_a?(String) && !input.empty?
                raise InvalidDefinition.new("#{rule}.input", "must be an identifier string")
              end
              renders = row["renders"]
              if renders && !renders.is_a?(String)
                raise InvalidDefinition.new("#{rule}.renders", "must be a string")
              end
              Definition::Positive.new(input: input, renders: renders)
            else
              raise InvalidDefinition.new(rule,
                                          "must be a string or {input:, renders:}")
            end
          end

          negatives = (examples["negatives"] || []).map do |input|
            unless input.is_a?(String) && !input.empty?
              raise InvalidDefinition.new("examples.negatives",
                                          "each negative must be an identifier string")
            end
            input
          end

          { positives: positives, negatives: negatives }
        end

        def check_reserved(rule, token)
          core = token.to_s.downcase.tr(":-_.", "")
          return unless RESERVED_TOKENS.include?(core)

          raise InvalidDefinition.new(
            rule,
            "reserved token #{token.inspect} — `ed`, `amd` and `cor` belong to " \
            "the edition/supplement machinery and cannot be claimed by a " \
            "definition",
          )
        end

        def single_line?(term)
          !term.include?("\n")
        end

        def balanced?(term)
          depth_paren = 0
          depth_bracket = 0
          quote = false
          term.each_char do |char|
            case char
            when '"' then quote = !quote
            when "(" then depth_paren += 1 unless quote
            when ")" then depth_paren -= 1 unless quote
            when "[" then depth_bracket += 1 unless quote
            when "]" then depth_bracket -= 1 unless quote
            end
            return false if depth_paren.negative? || depth_bracket.negative?
          end
          !quote && depth_paren.zero? && depth_bracket.zero?
        end

        def walk(template, &)
          template.sequences.each do |seq|
            seq.each do |item|
              yield item
              Template::Opt === item && walk(item.inner, &)
            end
          end
        end
      end
    end
  end
end
