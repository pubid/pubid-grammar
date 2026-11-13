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
          urn examples modules date supplements mr
        ].freeze

        # The kinds a field's list render may declare.
        LIST_RENDER_STYLES = %w[prefix infix].freeze
        # The kinds a urn.schema.types[] core entry may carry.
        CORE_KINDS = %w[string int].freeze
        # The MR segments a definition may hook (the shared
        # Renderers::MrString segment order minus the hooks the shared
        # model already answers: publisher reads the publisher attribute,
        # the rest are value slots a flavor fills).
        MR_SEGMENTS = %w[type number year edition].freeze

        module_function

        # @param raw [Hash] the strict-loaded definition
        # @param source_path [String] citing path for the header
        # @param source_sha [String] sha256 of the raw definition bytes
        # @param module_library [Hash{String => ModuleLibrary::Module}] the
        #   loaded module library (name → module); empty when absent
        # @return [Definition::Root]
        # @raise [InvalidDefinition]
        def validate(raw, source_path:, source_sha:, module_library: {})
          check_keys("definition", raw, TOP_LEVEL_KEYS)
          check_version(raw.fetch("pfs", nil))

          scheme = check_scheme(raw)
          organization = check_organization(raw)
          modules, module_bindings = check_modules(raw.fetch("modules", []), module_library, raw)
          grammar = check_grammar(raw, scheme, modules)
          # The merged fragment view: module fragments first, then the
          # definition's own. Names are unique across the view — the
          # module-aware collision checks guarantee it. Templates resolve
          # against it, so a composed definition names a module's face
          # (`en_face`) exactly like its own fragment.
          grammar = merged_grammar(modules, grammar)
          types = check_types(raw, scheme)
          fields = check_fields(raw, scheme, grammar)
          supplements, fields = check_supplements(raw["supplements"], fields)
          templates = check_templates(raw, fields, grammar)
          mr = check_mr(raw["mr"], fields)
          urn = check_urn(raw, fields, supplements)

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
            modules: modules.freeze,
            module_bindings: module_bindings.freeze,
            date: check_date(raw.fetch("date", nil), fields),
            supplements: supplements,
            mr: mr,
          )
        end

        # Resolve the `modules:` entries against the library and run the
        # MODULE-AWARE checks the composition exists to enable:
        #
        #   * fragment collisions — a `grammar:` name claimed by two modules,
        #     or by a module and the definition, is a compile-time ambiguity
        #     citing both claimants (templates resolve against the merged
        #     view, so a collision is a silent rebinding if allowed);
        #   * token claims — a module token colliding with the definition's
        #     publisher, prefixes, type keys or stage abbreviations, or with
        #     a co-bound module's tokens, cites both (the module-aware form
        #     of the type-token ambiguity rule);
        #   * reserved tokens hold inside modules and their parameters too;
        #   * versioning — resolved and version-checked by the library
        #     (fail-closed on unknown and stale versions).
        def check_modules(entries, library, raw)
          entries ||= []
          unless entries.is_a?(Array)
            raise InvalidDefinition.new("modules",
                                        "must be an array of module bindings")
          end

          bindings = entries.map.with_index do |entry, i|
            rule = "modules[#{i}]"
            unless entry.is_a?(Hash)
              raise InvalidDefinition.new(
                rule,
                "must be {module:, version:[, parameters:]} — a bare module " \
                "name would let the version drift silently",
              )
            end
            check_keys(rule, entry, %w[module version parameters])
            name = entry["module"]
            unless name.is_a?(String) && ModuleLibrary::NAME.match?(name)
              raise InvalidDefinition.new("#{rule}.module",
                                          "must be a dotted module name, got #{name.inspect}")
            end
            version = entry["version"]
            unless version.is_a?(Integer)
              raise InvalidDefinition.new(
                "#{rule}.version",
                "must be the integer version the definition is written against",
              )
            end
            parameters = entry["parameters"] || {}
            unless parameters.is_a?(Hash)
              raise InvalidDefinition.new("#{rule}.parameters", "must be a map")
            end
            ModuleLibrary::Binding.new(
              name: name, version: version, parameters: parameters,
            )
          end

          resolved = ModuleLibrary.resolve(bindings, library)

          check_fragment_collisions(resolved)
          check_module_token_claims(resolved, raw)
          check_identity_base_modules(resolved, bindings)

          [resolved.map { |_, mod| mod }, bindings]
        end

        # Compile-time span of the identity declarations: a module whose
        # identity names the module carrying its adopted face holds the
        # definition to BINDING that module — an en.overlay composed
        # without iso.inner would declare a base the composition cannot
        # resolve.
        def check_identity_base_modules(resolved, bindings)
          bound = bindings.map(&:name)
          resolved.each do |binding, mod|
            base = mod.identity&.base_module
            next if base.nil? || bound.include?(base)

            raise InvalidDefinition.new(
              "modules",
              "module #{mod.name.inspect} (#{binding.name}) declares the " \
              "identity base #{base.inspect}, which the definition does not " \
              "bind — add it to `modules:` or the composition cannot resolve",
            )
          end
        end

        # A fragment name claimed twice across the composition — modules
        # first, then the definition — is an ambiguity, not an override.
        def check_fragment_collisions(resolved)
          seen = {}
          resolved.each do |binding, mod|
            mod.grammar.each_key do |name|
              if seen.key?(name)
                raise InvalidDefinition.new(
                  "modules",
                  "ambiguity: grammar rule #{name.inspect} is declared by " \
                  "#{seen[name]} and by module #{mod.name.inspect} " \
                  "(#{binding.name}) — templates resolve against the merged " \
                  "view, so a collision would be a silent rebinding",
                )
              end
              seen[name] = "module #{mod.name.inspect} (#{binding.name})"
            end
          end
          seen
        end

        # A module's claimed tokens must be unclaimed by every CO-BOUND
        # module: two modules fighting over one token is an unresolved
        # composition. Claims shared with the BINDING definition are
        # co-ownership, not competition — the definition binding a module
        # IS the sharing (its prefixes, publisher and stage abbreviations
        # may all name the module's spellings; the overlay's EN face is
        # the definition's head token and its stage abbreviation). The
        # claim is case-insensitive — head dispatch is.
        def check_module_token_claims(resolved, _raw)
          claimed = {}
          resolved.each do |binding, mod|
            mod.tokens.each do |token|
              owner = claimed[token.to_s.downcase.tr(":-_.", "")]
              next unless owner

              raise InvalidDefinition.new(
                "modules",
                "ambiguity: modules #{owner} and #{mod.name.inspect} " \
                "(#{binding.name}) both claim token #{token.inspect} — " \
                "co-bound modules must not compete for a token",
              )
            end
            mod.tokens.each do |token|
              claimed[token.to_s.downcase.tr(":-_.", "")] =
                "module #{mod.name.inspect} (#{binding.name})"
            end
          end
        end

        # The definition-side token inventory the module claims are checked
        # against: publisher, prefixes, type keys and stage abbreviations.
        def token_claims(raw)
          claims = {}
          org = raw["organization"] || {}
          claims[org["publisher"].to_s.downcase.tr(":-_.", "")] = "organization.publisher" if org["publisher"].is_a?(String)
          (org["prefixes"] || []).each do |token|
            claims[token.to_s.downcase.tr(":-_.", "")] = "organization.prefixes" if token.is_a?(String)
          end
          (raw["types"] || {}).each do |name, body|
            next unless body.is_a?(Hash)

            claims[body["key"].to_s.downcase.tr(":-_.", "")] = "types.#{name}.key" if body["key"].is_a?(String)
            (body.dig("stage", "abbr") || []).each do |abbr|
              claims[abbr.to_s.downcase.tr(":-_.", "")] = "types.#{name}.stage.abbr" if abbr.is_a?(String)
            end
          end
          claims
        end

        # The merged fragment view the templates reference and the PARG
        # generator emits: module fragments, then the definition's own.
        def merged_grammar(modules, grammar)
          modules.reduce({}) { |merged, mod| merged.merge(mod.grammar) }
                 .merge(grammar)
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

        def check_grammar(raw, scheme, resolved_modules = [])
          fragments = raw["grammar"] || {}
          unless fragments.is_a?(Hash)
            raise InvalidDefinition.new("grammar", "must be a map of rule name → term")
          end
          check_grammar_map(fragments, "grammar")
          # Module-aware collision: the definition may not re-claim a name a
          # bound module already declared (the merged view would make the
          # definition's copy a silent override).
          resolved_modules.each do |mod|
            fragments.each_key do |name|
              next unless mod.grammar.key?(name)

              raise InvalidDefinition.new(
                "grammar.#{name}",
                "ambiguity: grammar rule #{name.inspect} is already declared by " \
                "module #{mod.name.inspect} — the definition and its modules " \
                "must not compete for a rule name",
              )
            end
          end
          fragments.freeze
        end

        # The shared fragment checks (rule names, single-line terms,
        # balanced quotes/brackets), citable under any prefix — the
        # definition's `grammar:` and a module's `grammar:` both use it.
        #
        # The NAMED-SEGMENTS rule (owner directive 2026-11-13, PFS v2):
        # a fragment's term may not carry an UNNAMED capture — a
        # parenthesized group without an explicit `as name`. The grammar
        # is read by every consuming body, so every segment it produces
        # carries a semantic name (number, publisher, copublisher, ...);
        # the compiler names its own generated rules the same way, and an
        # anonymous group in a hand-written fragment is a compile-time
        # rejection citing the rule, never an anonymous node on the wire.
        def check_grammar_map(fragments, prefix)
          fragments.each do |name, term|
            unless name.is_a?(String) && NAME.match?(name)
              raise InvalidDefinition.new("#{prefix}.#{name}",
                                          "rule name must be lower-case snake_case")
            end
            unless term.is_a?(String) && !term.empty?
              raise InvalidDefinition.new("#{prefix}.#{name}", "term must be a string")
            end
            unless single_line?(term)
              raise InvalidDefinition.new(
                "#{prefix}.#{name}",
                "term spans multiple lines — edition-2 line discipline is the " \
                "compiler's job; a fragment is a single-line term",
              )
            end
            unless balanced?(term)
              raise InvalidDefinition.new("#{prefix}.#{name}",
                                          "unbalanced quotes or brackets")
            end
            unnamed_capture = unnamed_capture_in(term)
            if unnamed_capture
              raise InvalidDefinition.new(
                "#{prefix}.#{name}",
                "unnamed capture: every grammar segment must carry a semantic " \
                "name (… ) as number … — the generated grammar is read by the " \
                "consuming bodies, so an anonymous group is rejected at compile " \
                "time (owner directive 2026-11-13: PFS names every segment)",
              )
            end
          end
        end

        # The offset of the first parenthesized group in +term+ that
        # carries no `as name` — the named-segments rejection's witness.
        # Quote-aware; a group is named iff the run after its closing
        # paren is `as <name>` (a nested group must be named too — the
        # rule names every segment, not only the outermost).
        def unnamed_capture_in(term)
          depth = 0
          quote = false
          term.each_char.with_index do |char, i|
            case char
            when '"' then quote = !quote
            when "("
              depth += 1 unless quote
            when ")"
              next if quote

              depth -= 1
              next if depth.positive?

              rest = term[(i + 1)..].to_s.lstrip
              return i unless rest.match?(/\Aas\s+[a-z][a-z0-9_]*(?![a-z0-9_])/)
            end
          end
          nil
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
            check_keys("types.#{name}", body, %w[key web title short tag stage])

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
              web: body["web"] || key,
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

          list = fields.map do |name, body|
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
            check_keys("fields.#{name}", body,
                       %w[pattern kind sub_numbering item render fold builder_only])

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
            pattern = apply_sub_numbering(name, pattern, body["sub_numbering"])

            kind = body["kind"] || "string"
            unless %w[string list].include?(kind)
              raise InvalidDefinition.new(
                "fields.#{name}.kind",
                "unsupported field kind #{kind.inspect} — pfs:1 carries `string` " \
                "and `list` (a list binds its `item` capture per repetition)",
              )
            end

            Definition::Field.new(
              name: name,
              pattern: pattern,
              kind: kind,
              item: body["item"],
              render: check_list_render(name, kind, body["render"]),
              fold: check_fold(name, body["fold"]),
              builder_only: body["builder_only"] || false,
            )
          end

          check_field_references(list)
          list
        end

        # The list render declaration: REQUIRED on a list field (the render
        # face composes the array through it), refused on a plain field.
        def check_list_render(name, kind, render)
          return nil if render.nil?

          unless kind == "list"
            raise InvalidDefinition.new(
              "fields.#{name}.render",
              "only a `kind: list` field renders a composition — a plain " \
              "string capture renders whole",
            )
          end
          unless render.is_a?(Hash)
            raise InvalidDefinition.new("fields.#{name}.render", "must be a map")
          end
          check_keys("fields.#{name}.render", render, %w[glue style])
          glue = render["glue"]
          unless glue.is_a?(String) && !glue.empty?
            raise InvalidDefinition.new("fields.#{name}.render.glue",
                                        "must be a separator string")
          end
          style = render["style"] || "prefix"
          unless LIST_RENDER_STYLES.include?(style)
            raise InvalidDefinition.new(
              "fields.#{name}.render.style",
              "unsupported style #{style.inspect} — known: " \
              "#{LIST_RENDER_STYLES.join(', ')} (`prefix` glues each item " \
              "before itself, `infix` joins the items)",
            )
          end
          Definition::ListRender.new(glue: glue, style: style)
        end

        # The ed.N-style fold: the capture folds into another field's
        # column plus a boolean flag (the coded flavors'
        # `ed.N → version + is_edition` shape). Fail-closed on unknown
        # targets, self-folds and flag names.
        def check_fold(name, fold)
          return nil if fold.nil?

          unless fold.is_a?(Hash)
            raise InvalidDefinition.new("fields.#{name}.fold", "must be a map")
          end
          check_keys("fields.#{name}.fold", fold, %w[into flag])
          into = fold["into"]
          unless into.is_a?(String) && NAME.match?(into)
            raise InvalidDefinition.new("fields.#{name}.fold.into",
                                        "must be a field name")
          end
          if into == name
            raise InvalidDefinition.new("fields.#{name}.fold.into",
                                        "a fold cannot target its own capture")
          end
          flag = fold["flag"]
          unless flag.is_a?(String) && NAME.match?(flag)
            raise InvalidDefinition.new("fields.#{name}.fold.flag",
                                        "must be a boolean flag name")
          end
          Definition::Fold.new(into: into, flag: flag)
        end

        # Cross-field reference checks: a list's `item` names a declared
        # field (and only one list claims it); a fold's target is a
        # declared plain field and its flag name is free; a builder-only
        # field is never referenced by a render surface (the render face
        # guards below refuse it in the template check).
        def check_field_references(fields)
          by_name = fields.each_with_object({}) { |field, map| map[field.name] = field }
          claimed_items = {}
          fields.each do |field|
            next unless field.kind == "list"

            item_name = field.item
            unless item_name.is_a?(String) && by_name.key?(item_name)
              raise InvalidDefinition.new(
                "fields.#{field.name}.item",
                "must name a declared field — the item capture the list " \
                "binds per repetition, got #{item_name.inspect}",
              )
            end
            item = by_name[item_name]
            unless item.kind == "string" && item.render.nil? && item.fold.nil?
              raise InvalidDefinition.new(
                "fields.#{field.name}.item",
                "must name a plain string field without fold or render",
              )
            end
            if claimed_items.key?(item_name)
              raise InvalidDefinition.new(
                "fields.#{field.name}.item",
                "ambiguity: item capture #{item_name.inspect} is already " \
                "claimed by the list field #{claimed_items[item_name].inspect}",
              )
            end
            claimed_items[item_name] = field.name
          end
          fields.each do |field|
            next if field.fold.nil?

            target = by_name[field.fold.into]
            unless target && target.kind == "string" && target.fold.nil?
              raise InvalidDefinition.new(
                "fields.#{field.name}.fold.into",
                "must name a declared plain string field, got " \
                "#{field.fold.into.inspect}",
              )
            end
            flag = field.fold.flag
            collides = by_name.key?(flag) || fields.any? do |other|
              other != field && other.fold&.flag == flag
            end
            if collides
              raise InvalidDefinition.new(
                "fields.#{field.name}.fold.flag",
                "the boolean flag #{flag.inspect} must not collide with a " \
                "declared field or another fold flag",
              )
            end
          end
        end

        # The sub-numbering extension (tier-B extension 6, #706 §6): a
        # decimal/dashed sub-number suffix on a field, declared at the
        # pattern level so the wizard offers it as a form field. CalConnect's
        # `CC/Adv 0707.1:2007` is the motivating surface. The declaration
        # folds into the field's pattern — the capture stays WHOLE (the
        # sub-number is part of the field's value, exactly as the coded
        # flavors model it), so the model stores what the scheme prints.
        def apply_sub_numbering(field_name, pattern, sub_numbering)
          return pattern if sub_numbering.nil?

          unless sub_numbering.is_a?(Hash)
            raise InvalidDefinition.new("fields.#{field_name}.sub_numbering",
                                        "must be a map")
          end
          check_keys("fields.#{field_name}.sub_numbering", sub_numbering, %w[separators])
          separators = sub_numbering["separators"]
          unless separators.is_a?(Array) && !separators.empty? &&
              separators.all? { |s| s.is_a?(String) && !s.empty? && !s.include?('"') }
            raise InvalidDefinition.new(
              "fields.#{field_name}.sub_numbering.separators",
              "must be a non-empty array of separator literals",
            )
          end

          "#{pattern} [(#{separators.map { |s| "\"#{s}\"" }.join(' / ')}) 1*digit]"
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
          check_canonical_optionals(canonical)

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
          # The captures a face may never reference: a list's item capture
          # (the list renders whole through its `render:` composition) and
          # the supplement run's generated internals. Renderable
          # exceptions: a fold's SOURCE capture (its render presence is
          # the fold flag) and the run list itself.
          item_names = fields.select { |f| f.kind == "list" && f.item }.map(&:item)
          run_name = fields.find { |f| f.builder_only && f.kind == "list" }&.name
          unrenderable = fields.select do |f|
            next true if item_names.include?(f.name)
            next false if f.fold
            next false if f.name == run_name

            f.builder_only
          end.map(&:name)
          walk(template) do |item|
            case item
            when Template::Field
              field = fields.find { |f| f.name == item.name }
              unless field
                raise InvalidDefinition.new(rule,
                                            "unknown field {#{item.name}}")
              end
              next unless unrenderable.include?(item.name)

              if item_names.include?(item.name)
                list_name = fields.find { |f| f.item == item.name }&.name
                raise InvalidDefinition.new(
                  rule,
                  "{#{item.name}} is a list's item capture — the list " \
                  "{#{list_name}} renders whole through its `render:` " \
                  "composition; items are not a render surface",
                )
              end
              raise InvalidDefinition.new(
                rule,
                "{#{item.name}} is a compiler-generated supplement-run " \
                "capture — only the run itself is a render surface",
              )
            when Template::Ref
              unless grammar.key?(item.name)
                raise InvalidDefinition.new(
                  rule,
                  "unknown grammar rule #{item.name} — declare it under " \
                  "`grammar:` (or bind the module that declares it)",
                )
              end
            end
          end
        end

        # A canonical optional renders as a PRESENCE GUARD (it renders its
        # inner face iff every field inside captured), so an optional with
        # no field inside has no presence signal — its rendering could not
        # be decided. Parse-only alternates are free of the rule.
        def check_canonical_optionals(canonical)
          walk(canonical) do |item|
            next unless Template::Opt === item

            unless Template.fields_in(item).any?
              raise InvalidDefinition.new(
                "templates.canonical",
                "an optional segment with no field inside cannot render — " \
                "the render face decides presence from the captured fields",
              )
            end
          end
        end

        def check_urn(raw, fields, supplements)
          urn = raw["urn"]
          unless urn.is_a?(Hash)
            raise InvalidDefinition.new("urn", "section is required")
          end
          check_keys("urn", urn, %w[namespace schema official])
          check_keys("urn.schema", urn["schema"], %w[atoms types])

          namespace = urn["namespace"]
          unless namespace.is_a?(String) && NAME.match?(namespace)
            raise InvalidDefinition.new("urn.namespace",
                                        "must be a lower-case namespace, got #{namespace.inspect}")
          end

          official = check_urn_official(urn["official"] || [], fields)

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
            core = check_urn_core(rule, type["core"] || [], fields)
            Definition::UrnType.new(type: type_str, token: token, core: core)
          end

          tags = types.map(&:type)
          if tags.uniq.size != tags.size
            raise InvalidDefinition.new("urn.schema.types",
                                        "ambiguity: duplicate URN type declarations")
          end

          Definition::Urn.new(namespace: namespace, atoms: atoms, types: types,
                              official: official)
        end

        # The core declaration of a urn.schema.types[] row: bare field
        # paths (string-kind) or `[path, kind]` pairs — pfs:1 phase 3 adds
        # the `int` kind (the coded schemas' `core: [["number", :int]]`
        # supplement rows). The normalized rows carry the pairs; the
        # generator emits them verbatim.
        def check_urn_core(rule, core, fields)
          unless core.is_a?(Array)
            raise InvalidDefinition.new(rule, "core must be an array of field paths")
          end
          core.map do |entry|
            path, kind =
              case entry
              when String then [entry, "string"]
              when Array
                unless entry.size == 2
                  raise InvalidDefinition.new(rule,
                                              "a typed core entry must be [path, kind]")
                end
                entry
              else
                raise InvalidDefinition.new(
                  rule,
                  "core entries are field paths or [path, kind] pairs, " \
                  "got #{entry.inspect}",
                )
              end
            unless fields.any? { |f| f.name == path }
              raise InvalidDefinition.new(rule, "unknown core field #{path.inspect}")
            end
            unless CORE_KINDS.include?(kind)
              raise InvalidDefinition.new(
                rule,
                "unsupported core kind #{kind.inspect} — known: " \
                "#{CORE_KINDS.join(', ')}",
              )
            end
            [path, kind]
          end
        end

        # The calendar binding (`date:`): the declared fields fold into the
        # shared ::Pubid::Components::Date — the coded flavors' own shape —
        # and the serialized hash stays flat (the shared flat-scalar
        # machinery). A definition without `date:` keeps its fields as
        # plain string attributes (doi's shape).
        def check_date(date, fields)
          return nil if date.nil?

          unless date.is_a?(Hash)
            raise InvalidDefinition.new("date", "must be a map")
          end
          check_keys("date", date, %w[component fields])

          component = date["component"] || "pubid"
          unless component == "pubid"
            raise InvalidDefinition.new(
              "date.component",
              "unsupported component #{component.inspect} — pfs:1 folds the " \
              "calendar fields into the shared ::Pubid::Components::Date",
            )
          end

          date_fields = date["fields"]
          known = fields.map(&:name)
          unless date_fields.is_a?(Array) && date_fields.all? { |f| known.include?(f) }
            raise InvalidDefinition.new(
              "date.fields",
              "must be an array of declared field names, got " \
              "#{date_fields.inspect}",
            )
          end

          Definition::Date.new(fields: date_fields)
        end

        # The SUPPLEMENT WRAPPER machinery (pubid#706 phase 3, gap c): the
        # printed supplement run (`/A1/C1`) parses as a builder-only
        # capture, and the builder folds it into SYNTHESIZED wrapper
        # classes (Amendment/Corrigendum over the base standard — the
        # coded flavors' own shape), one per declared wrapper kind. The
        # compiler GENERATES the run grammar from the declaration, so the
        # run's shape and the fold can never drift apart, and it
        # registers the generated capture names as fields so the
        # templates reference them like any other segment.
        #
        #   supplements:
        #     run: supplements       # the builder-only capture
        #     item: supplement       # the run's item capture
        #     kind: supplement_kind  # the item's kind face capture
        #     number: supplement_number  # the item's ordinal capture
        #     wrappers:
        #       amendment:   { face: "A", tag: "pubid:etsi:amendment" }
        #       corrigendum: { face: "C", tag: "pubid:etsi:corrigendum" }
        def check_supplements(raw, fields)
          return [nil, fields] if raw.nil?

          unless raw.is_a?(Hash)
            raise InvalidDefinition.new("supplements", "must be a map")
          end
          check_keys("supplements", raw, %w[run item kind number wrappers])
          names = %w[run item kind number].map do |key|
            value = raw[key]
            unless value.is_a?(String) && NAME.match?(value)
              raise InvalidDefinition.new("supplements.#{key}",
                                          "must be a lower-case capture name")
            end
            value
          end
          run_name, item_name, kind_name, number_name = names
          if names.uniq.size != names.size
            raise InvalidDefinition.new(
              "supplements",
              "the generated capture names (run, item, kind, number) must " \
              "be distinct — two of #{names.map(&:inspect).join(', ')} collide",
            )
          end
          collides = fields.select do |field|
            names.include?(field.name) || names.include?(field.fold&.flag)
          end
          unless collides.empty?
            raise InvalidDefinition.new(
              "supplements",
              "the generated capture name(s) #{collides.map(&:name).map(&:inspect).join(', ')} " \
              "collide with declared fields — the run grammar's names must be free",
            )
          end

          wrappers = raw["wrappers"]
          unless wrappers.is_a?(Hash) && !wrappers.empty?
            raise InvalidDefinition.new("supplements.wrappers",
                                        "at least one wrapper kind is required")
          end
          faces = {}
          tags = {}
          rows = wrappers.map do |name, body|
            unless name.is_a?(String) && NAME.match?(name)
              raise InvalidDefinition.new("supplements.wrappers.#{name}",
                                          "wrapper name must be snake_case")
            end
            check_keys("supplements.wrappers.#{name}", body, %w[face tag title])
            face = body["face"]
            unless face.is_a?(String) && face.match?(/\A[A-Z]\z/)
              raise InvalidDefinition.new(
                "supplements.wrappers.#{name}.face",
                "must be a single upper-case kind face letter, got #{face.inspect}",
              )
            end
            if faces.key?(face)
              raise InvalidDefinition.new(
                "supplements.wrappers.#{name}.face",
                "ambiguity: face #{face.inspect} is already claimed by wrapper " \
                "#{faces[face].inspect} — the run grammar cannot dispatch two " \
                "kinds on one face",
              )
            end
            faces[face] = name
            tag = body["tag"]
            unless tag.is_a?(String) && TAG.match?(tag)
              raise InvalidDefinition.new(
                "supplements.wrappers.#{name}.tag",
                "must match pubid:<flavor>:<type>, got #{tag.inspect}",
              )
            end
            if tags.key?(tag)
              raise InvalidDefinition.new(
                "supplements.wrappers.#{name}.tag",
                "ambiguity: wire tag #{tag.inspect} already claimed",
              )
            end
            tags[tag] = name
            Definition::Wrapper.new(
              name: name, face: face, tag: tag,
              title: body["title"] || name.capitalize,
            )
          end

          wrapper = Definition::Supplements.new(
            run: run_name, item: item_name, kind: kind_name, number: number_name,
            wrappers: rows.freeze,
          )

          # The generated capture names join the field list: the run as the
          # builder-only list the fold consumes, the item/kind/number as
          # the generated grammar's internal captures (never model columns,
          # never render faces — the templates may reference the run).
          generated = [
            Definition::Field.new(
              name: run_name,
              pattern: generated_run_pattern(wrapper),
              kind: "list",
              item: item_name,
              # The notations render as the printed run: "/" before each
              # kind face + ordinal ("/A1/C1").
              render: Definition::ListRender.new(glue: "/", style: "prefix"),
              builder_only: true,
            ),
            Definition::Field.new(name: item_name, pattern: "", kind: "string",
                                  builder_only: true),
            Definition::Field.new(name: kind_name, pattern: generated_kind_pattern(wrapper),
                                  kind: "string", builder_only: true),
            Definition::Field.new(name: number_name, pattern: "1*digit",
                                  kind: "string", builder_only: true),
          ]
          [wrapper, fields + generated]
        end

        # The run pattern the compiler generates from the wrapper faces:
        # `1*( "/" ("A" / "C") 1*digit )`-shaped, in declared face order.
        def generated_run_pattern(wrapper)
          inner = "(\"/\" #{wrapper.wrappers.map { |w| "\"#{w.face}\"" }.join(' / ')}) " \
                  "1*digit"
          "1*(#{inner})"
        end

        # The kind face alternation the item rule captures.
        def generated_kind_pattern(wrapper)
          wrapper.wrappers.map { |w| "\"#{w.face}\"" }.join(" / ")
        end

        # The MR-slug hooks (`mr:`): a map of MR segment name → hook
        # declaration over the declared fields. The shared MrString
        # renderer reads the hooks off the model in its fixed segment
        # order; the declared hooks REPLACE the base hooks for their
        # segments (an undeclared segment keeps the shared model's
        # answer). The charset sanitize is the generated method's job
        # (lowercase, [a-z0-9-], runs collapsed) — the declaration only
        # says WHICH fields feed the segment.
        def check_mr(raw, fields)
          return nil if raw.nil?

          unless raw.is_a?(Hash)
            raise InvalidDefinition.new("mr", "must be a map of segment → hook")
          end
          known = fields.map(&:name)
          segments = raw.map do |segment, hook|
            unless MR_SEGMENTS.include?(segment.to_s)
              raise InvalidDefinition.new(
                "mr.#{segment}",
                "unknown MR segment — the shared renderer's hookable " \
                "segments are: #{MR_SEGMENTS.join(', ')} (publisher and the " \
                "supplement suffix are the shared model's)",
              )
            end
            unless hook.is_a?(Hash)
              raise InvalidDefinition.new("mr.#{segment}", "must be a map")
            end
            check_keys("mr.#{segment}", hook, %w[field join glue])
            if hook.key?("field")
              name = hook["field"]
              unless known.include?(name)
                raise InvalidDefinition.new("mr.#{segment}.field",
                                            "unknown field #{name.inspect}")
              end
              [segment, Definition::MrField.new(field: name)]
            else
              join = hook["join"]
              glue = hook["glue"] || "-"
              unless join.is_a?(Array) && !join.empty? && join.all? do |f|
                known.include?(f) || list_fields(fields).include?(f)
              end
                raise InvalidDefinition.new(
                  "mr.#{segment}.join",
                  "must be a non-empty array of known field names, got " \
                  "#{join.inspect}",
                )
              end
              unless glue.is_a?(String) && !glue.empty?
                raise InvalidDefinition.new("mr.#{segment}.glue",
                                            "must be a separator string")
              end
              [segment, Definition::MrJoin.new(join: join, glue: glue)]
            end
          end
          if segments.map(&:first).uniq.size != segments.size
            raise InvalidDefinition.new("mr", "a segment is declared twice")
          end
          Definition::Mr.new(segments: segments.to_h)
        end

        def list_fields(fields)
          fields.select { |f| f.kind == "list" }.map(&:name)
        end

        # The OFFICIAL URN's ordered segments (`urn.official`): the scheme's
        # registered form (`urn:calconnect:<series>:<number>:<date>`) is the
        # generator's composition, declared — not inherited from a base
        # template that knows nothing of the scheme. A segment is a field
        # name (omitted when the field did not capture) or a fused
        # `{date: [fields...]}` group (the fields joined with `-`, the
        # group omitted when none captured). A definition without
        # `official:` keeps the shared base generator (doi's shape).
        # The OFFICIAL URN's ordered segments (`urn.official`): the scheme's
        # registered form is the generator's composition, declared — not
        # inherited from a base template that knows nothing of the scheme.
        # A segment is a field name (omitted when it did not capture), a
        # `{field:, lower:, affix:, edition_affix:}` row (lower downcases,
        # affix prefixes the value, edition_affix replaces the affix while
        # the fold flag holds), a fused `{date: [fields]}` group (the
        # fields joined with `-`), or a `{compose: [...]}` code (ordered
        # slots, each glued before the previously rendered). A definition
        # without `official:` keeps the shared base generator (doi's shape).
        def check_urn_official(official, fields)
          unless official.is_a?(Array)
            raise InvalidDefinition.new("urn.official",
                                        "must be an array of ordered segments")
          end
          known = fields.map(&:name)
          fold_targets = fields.select { |f| f.fold }.map { |f| f.fold.into }
          official.map.with_index do |segment, i|
            rule = "urn.official[#{i}]"
            case segment
            when String
              unless known.include?(segment)
                raise InvalidDefinition.new(rule, "unknown field #{segment.inspect}")
              end
              Definition::UrnField.new(name: segment)
            when Hash
              check_keys(rule, segment, %w[field date compose lower affix edition_affix])
              if segment.key?("field")
                name = segment["field"]
                unless known.include?(name)
                  raise InvalidDefinition.new(rule, "unknown field #{name.inspect}")
                end
                edition_affix = segment["edition_affix"]
                if edition_affix && !fold_targets.include?(name)
                  raise InvalidDefinition.new(
                    "#{rule}.edition_affix",
                    "the segment field #{name.inspect} carries no fold — an " \
                    "edition affix replaces the affix only where a fold flag " \
                    "decides the face",
                  )
                end
                Definition::UrnField.new(
                  name: name,
                  lower: segment["lower"] || false,
                  affix: segment["affix"],
                  edition_affix: edition_affix,
                )
              elsif segment.key?("date")
                date_fields = segment["date"]
                unless date_fields.is_a?(Array) && !date_fields.empty? &&
                    date_fields.all? { |f| known.include?(f) }
                  raise InvalidDefinition.new(
                    "#{rule}.date",
                    "must be a non-empty array of known field names",
                  )
                end
                Definition::UrnDate.new(fields: date_fields)
              else
                slots = segment["compose"]
                unless slots.is_a?(Array) && !slots.empty?
                  raise InvalidDefinition.new(
                    "#{rule}.compose",
                    "must be a non-empty array of {field:, glue:, style:} slots",
                  )
                end
                Definition::UrnCompose.new(
                  slots: slots.map.with_index do |slot, j|
                    check_urn_compose_slot("#{rule}.compose[#{j}]", slot, known,
                                           first: j.zero?)
                  end,
                )
              end
            else
              raise InvalidDefinition.new(
                rule,
                "must be a field name, {field: ...}, {date: [fields]} or " \
                "{compose: [...]}",
              )
            end
          end
        end

        # One compose slot: the field it reads, the glue rendered before it
        # (or before each of its items, under `style: prefix`), and the
        # join style (default prefix — the parts-run shape).
        def check_urn_compose_slot(rule, slot, known, first: false)
          unless slot.is_a?(Hash)
            raise InvalidDefinition.new(rule, "must be a map")
          end
          check_keys(rule, slot, %w[field glue style])
          name = slot["field"]
          unless known.include?(name)
            raise InvalidDefinition.new(rule, "unknown field #{name.inspect}")
          end
          glue = slot["glue"]
          if first
            unless glue.nil?
              raise InvalidDefinition.new(
                "#{rule}.glue",
                "the first slot carries no glue — nothing renders before it",
              )
            end
          elsif !(glue.is_a?(String) && !glue.empty?)
            raise InvalidDefinition.new("#{rule}.glue", "must be a separator string")
          end
          style = slot["style"] || "prefix"
          unless LIST_RENDER_STYLES.include?(style)
            raise InvalidDefinition.new(
              "#{rule}.style",
              "unsupported style #{style.inspect} — known: " \
              "#{LIST_RENDER_STYLES.join(', ')}",
            )
          end
          Definition::UrnSlot.new(field: name, glue: glue, style: style)
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
