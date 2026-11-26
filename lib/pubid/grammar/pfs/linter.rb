# frozen_string_literal: true

require "digest"

module Pubid
  module Grammar
    module Pfs
      # `pfs lint <file>` — the compile-time guarantees as PRE-compile
      # diagnostics (issue #152).
      #
      # The compiler already fails closed on every one of these; lint
      # surfaces the same guarantees BEFORE the engine is invoked, each as
      # a named, actionable rule:
      #
      #   PFS001  schema-version-pin    the `pfs:` major (fail-closed versioning)
      #   PFS002  module-pin            module bindings: unknown modules, stale
      #                                 versions, parameter contracts
      #   PFS003  fragment-collision    a grammar name claimed twice across the
      #                                 composition (templates resolve against the
      #                                 merged view — a collision is a silent
      #                                 rebinding)
      #   PFS004  token-collision       co-bound modules competing for a token
      #   PFS005  reserved-token        `ed`/`amd`/`cor` claimed anywhere
      #   PFS006  template-citation     a {reference} resolving to neither a
      #                                 field nor a fragment (the citation
      #                                 errors, fast-scan form)
      #   PFS007  numeric-kind-safety   the v2 type system: `int` cores/atoms
      #                                 must reference integer-kind fields;
      #                                 string cores must not
      #   PFS008  supplement-declaration  supplement captures named without a
      #                                 declared `supplements:` section (and
      #                                 generated names colliding with fields)
      #   PFS009  examples-required     the REQUIRED live test panel
      #   PFS010  unknown-key           a top-level key outside the dialect
      #                                 (a newer dialect, not noise — the same
      #                                 fail-closed rule the compiler applies)
      #   PFS999  unresolved            anything else the compiler refuses,
      #                                 carried with its citing rule
      #
      # Exit status: 0 = no findings, 1 = findings. The compiler remains
      # the authority; lint is the fast pre-compile pass (no engine pin
      # needed — it never requires parsanol).
      module Linter
        Finding = Struct.new(:id, :rule, :message, keyword_init: true)

        # The mapping table for validator refusals (rule path + message →
        # named lint rule).
        VALIDATOR_MAP = [
          [%r{\Amodules\z}, /unknown module|is bound at version|the library ships|requires parameter|declares no parameter|must be an array of module bindings|must be \{module:/, "PFS002"],
          [%r{\Amodules\z}, /is declared by/, "PFS003"],
          [%r{\Amodules\z}, /both claim token/, "PFS004"],
          [/reserved token/, //, "PFS005"],
          [/\Atemplates/, //, "PFS006"],
          [/\Aurn/, /unknown field path|core|kind/, "PFS007"],
          [//, /supplement/, "PFS008"],
          [/\Aexamples/, //, "PFS009"],
          [/\Adefinition\z/, //, "PFS010"],
        ].freeze

        module_function

        # @param path [String] the .pfs file
        # @param module_library [Hash{String => ModuleLibrary::Module}]
        #   loaded library; loaded from the repo's definitions/modules when
        #   nil (and errors tolerated — the library may be absent)
        # @return [Array<Finding>] every finding, in rule order
        def run(path, module_library: nil)
          raw = Loader.load(path)
          library = module_library.nil? ? load_library_quietly : module_library

          findings = []
          findings.concat(check_version_pin(raw))
          findings.concat(check_unknown_keys(raw))
          findings.concat(check_module_pins(raw, library))
          findings.concat(check_reserved_tokens(raw, library))
          findings.concat(check_fragment_collisions(raw, library))
          findings.concat(check_token_collisions(raw, library))
          findings.concat(check_supplement_declaration(raw))
          findings.concat(check_numeric_kinds(raw))
          findings.concat(check_template_citations(raw))
          findings.concat(check_examples(raw))
          return findings unless findings.empty?

          # No named finding: run the compiler's own fail-closed validation
          # as the closing sweep. Anything it refuses is carried with its
          # citing rule (the deep checks — ambiguity, structure, folds,
          # official-URN shapes — stay the compiler's).
          Validator.validate(
            raw,
            source_path: path,
            source_sha: Digest::SHA256.hexdigest(File.binread(path)),
            module_library: library,
          )
          []
        rescue InvalidDefinition => e
          [Finding.new(id: map_rule(e.rule, e.message), rule: e.rule,
                       message: e.message)]
        end

        # @return [String] the one-line report for a finding
        def format(finding, path)
          "#{path}: [#{finding.id}] #{finding.rule}: #{finding.message}"
        end

        # Map a validator refusal to its named lint rule (first match).
        def map_rule(rule, message)
          VALIDATOR_MAP.each do |rule_re, message_re, id|
            return id if rule_re.match?(rule.to_s) && message_re.match?(message.to_s)
          end
          "PFS999"
        end

        def load_library_quietly
          dir = File.join(File.expand_path("../../../..", __dir__), "definitions/modules")
          File.directory?(dir) ? ModuleLibrary.load(dir) : {}
        rescue InvalidDefinition
          {}
        end

        # --- PFS001: the schema major ------------------------------------
        def check_version_pin(raw)
          value = raw.fetch("pfs", nil)
          if value.nil?
            [Finding.new(id: "PFS001", rule: "pfs",
                         message: "missing — a definition declares its schema major " \
                                  "(pfs: #{Pfs::SCHEMA_VERSION})")]
          elsif !value.is_a?(Integer) || value != Pfs::SCHEMA_VERSION
            [Finding.new(id: "PFS001", rule: "pfs",
                         message: "declares pfs: #{value.inspect}; this compiler " \
                                  "speaks pfs: #{Pfs::SCHEMA_VERSION} — a newer " \
                                  "dialect fails closed, upgrade the compiler")]
          else
            []
          end
        end

        # --- PFS010: keys outside the dialect ------------------------------
        def check_unknown_keys(raw)
          unknown = raw.keys - Validator::TOP_LEVEL_KEYS
          return [] if unknown.empty?

          [Finding.new(id: "PFS010", rule: "definition",
                       message: "unknown key(s) #{unknown.map(&:inspect).join(', ')} — " \
                                "`pfs:` versioning is additive, so an unknown key " \
                                "means a newer dialect: upgrade the compiler or " \
                                "remove the key")]
        end

        # --- PFS002: the module pins ---------------------------------------
        def check_module_pins(raw, library)
          entries = raw.fetch("modules", [])
          return [] if entries.nil?
          unless entries.is_a?(Array)
            return [Finding.new(id: "PFS002", rule: "modules",
                                message: "must be an array of {module:, version:, " \
                                         "parameters:} bindings")]
          end

          entries.filter_map.with_index do |entry, i|
            rule = "modules[#{i}]"
            unless entry.is_a?(Hash)
              next Finding.new(id: "PFS002", rule: rule,
                               message: "must be {module:, version:[, parameters:]} — " \
                                        "a bare module name would let the version drift")
            end
            name = entry["module"]
            mod = library[name] if name.is_a?(String)
            if mod.nil?
              next Finding.new(id: "PFS002", rule: rule,
                               message: "unknown module #{name.inspect} — the library " \
                                        "carries #{library.keys.sort.map(&:inspect).join(', ')}; " \
                                        "a module this compiler does not have cannot compose")
            end
            if entry["version"] != mod.version
              next Finding.new(id: "PFS002", rule: "#{rule}.version",
                               message: "bound at version #{entry["version"].inspect}; the " \
                                        "library ships #{mod.version} — a module's major " \
                                        "is its contract, no silent downgrade")
            end
            missing = mod.parameters.select(&:required)
                                    .reject { |p| (entry["parameters"] || {}).key?(p.name) }
            unless missing.empty?
              next Finding.new(id: "PFS002", rule: rule,
                               message: "module #{name.inspect} requires parameter(s) " \
                                        "#{missing.map { |p| p.name.inspect }.join(', ')} — " \
                                        "supply them under parameters:")
            end
            unknown_params = (entry["parameters"] || {}).keys - mod.parameters.map(&:name)
            unless unknown_params.empty?
              next Finding.new(id: "PFS002", rule: rule,
                               message: "module #{name.inspect} declares no parameter(s) " \
                                        "#{unknown_params.map(&:inspect).join(', ')} — " \
                                        "declared: #{mod.parameters.map { |p| p.name.inspect }.join(', ')}")
            end
            nil
          end
        end

        # --- PFS005: reserved tokens ---------------------------------------
        def check_reserved_tokens(raw, library)
          findings = []
          inventory = token_inventory(raw)
          inventory.each do |rule, token|
            core = token.to_s.downcase.tr(":-_.", "")
            next unless Validator::RESERVED_TOKENS.include?(core)

            findings << Finding.new(
              id: "PFS005", rule: rule,
              message: "reserved token #{token.inspect} — `ed`, `amd` and `cor` " \
                       "belong to the edition/supplement machinery; bind the " \
                       "body's spelling through supplements.core/edition.core instead",
            )
          end
          library.each_value do |mod|
            mod.tokens.each_with_index do |token, i|
              next unless Validator::RESERVED_TOKENS.include?(token.downcase.tr(":-_.", ""))

              findings << Finding.new(id: "PFS005", rule: "modules (#{mod.name}.tokens[#{i}])",
                                      message: "reserved token #{token.inspect} claimed by the module")
            end
          end
          findings
        end

        # The definition-side token inventory (the validator's own).
        def token_inventory(raw)
          claims = {}
          org = raw["organization"].is_a?(Hash) ? raw["organization"] : {}
          claims["organization.publisher"] = org["publisher"] if org["publisher"].is_a?(String)
          (org["prefixes"] || []).each_with_index do |token, i|
            claims["organization.prefixes[#{i}]"] = token if token.is_a?(String)
          end
          (raw["types"] || {}).each do |name, body|
            next unless body.is_a?(Hash)

            claims["types.#{name}.key"] = body["key"] if body["key"].is_a?(String)
            (body.dig("stage", "abbr") || []).each_with_index do |abbr, i|
              claims["types.#{name}.stage.abbr[#{i}]"] = abbr if abbr.is_a?(String)
            end
          end
          claims
        end

        # --- PFS003: fragment collisions -----------------------------------
        def check_fragment_collisions(raw, library)
          seen = {}
          findings = []

          library.each_value do |mod|
            mod.grammar.each_key do |name|
              findings << collision_finding(name, seen[name],
                                            "module #{mod.name}") if seen.key?(name)
              seen[name] = "module #{mod.name}"
            end
          end
          (raw["grammar"] || {}).each_key do |name|
            next unless name.is_a?(String)

            findings << collision_finding(name, seen[name], "the definition") if seen.key?(name)
            seen[name] = "the definition"
          end
          findings
        end

        def collision_finding(name, claimant, claimant2)
          Finding.new(
            id: "PFS003", rule: "grammar",
            message: "ambiguity: grammar rule #{name.inspect} is declared by " \
                     "#{claimant} and by #{claimant2} — templates resolve against " \
                     "the merged view, so a collision would be a silent rebinding; " \
                     "rename one claimant",
          )
        end

        # --- PFS004: co-bound module token competition ----------------------
        def check_token_collisions(raw, library)
          claimed = {}
          findings = []
          library.each_value do |mod|
            mod.tokens.each do |token|
              key = token.downcase.tr(":-_.", "")
              if claimed.key?(key)
                findings << Finding.new(
                  id: "PFS004", rule: "modules",
                  message: "ambiguity: modules #{claimed[key]} and #{mod.name} both " \
                           "claim token #{token.inspect} — co-bound modules must not " \
                           "compete for a token; drop one binding or narrow its tokens",
                )
              end
              claimed[key] = mod.name
            end
          end
          findings
        end

        # --- PFS008: the supplement declarations ----------------------------
        def check_supplement_declaration(raw)
          findings = []
          declared = raw["supplements"].is_a?(Hash)

          templates(raw).each_with_index do |template, i|
            next unless template.is_a?(String)
            next if declared || !template.include?("{supplements}")

            findings << Finding.new(
              id: "PFS008", rule: "templates (entry #{i})",
              message: "references {supplements} but no supplements: section is " \
                       "declared — declare the wrapper machinery (run/item/kind/number " \
                       "+ wrappers) or drop the {supplements} segment",
            )
          end

          if declared
            decl = raw["supplements"]
            fields = raw["fields"].is_a?(Hash) ? raw["fields"].keys : []
            %w[run item kind number].each do |role|
              name = decl[role]
              next unless name.is_a?(String)

              # The generated captures carry the scheme prefix; a declared
              # field under the SAME bare name is a duplicate (the run capture
              # is `<scheme>_<name>`-shaped in the grammar, the column in the
              # builder). Only a verbatim collision is a finding.
              if fields.include?(name)
                findings << Finding.new(
                  id: "PFS008", rule: "supplements.#{role}",
                  message: "capture #{name.inspect} collides with a declared field " \
                           "of the same name — the supplements machinery generates " \
                           "its own captures; rename one",
                )
              end
            end
          end
          findings
        end

        # --- PFS007: the v2 numeric-kind surface ----------------------------
        # Only DECLARED fields are pre-checked: a core/atom path the
        # definition does not declare belongs to the wrapper namespace (the
        # generated ordinal columns — `[[number, int]]` on a supplement row
        # is the wrapper's own ordinal, typed by supplements.number_kind) —
        # the validator's column resolution stays the deep authority there.
        # A WRAPPER row's `number` IS the wrapper ordinal (the tag names the
        # synthesized class), so it resolves to number_kind, not to a
        # same-named document field.
        def check_numeric_kinds(raw)
          findings = []
          fields = raw["fields"].is_a?(Hash) ? raw["fields"] : {}

          field_kind = fields.transform_values do |body|
            body.is_a?(Hash) ? body["kind"] : nil
          end

          supplements = raw["supplements"].is_a?(Hash) ? raw["supplements"] : {}
          number_kind = supplements["number_kind"] == "string" ? "string" : "int"
          wrapper_tags = []
          (supplements["wrappers"] || {}).each_value do |w|
            wrapper_tags << w["tag"] if w.is_a?(Hash)
          end
          [supplements["consolidated"], supplements["fragment"]].each do |w|
            wrapper_tags << w["tag"] if w.is_a?(Hash)
          end

          urn = raw["urn"].is_a?(Hash) ? raw["urn"] : {}
          schema = urn["schema"].is_a?(Hash) ? urn["schema"] : {}

          (schema["atoms"] || []).each_with_index do |atom, i|
            next unless atom.is_a?(Hash)

            kind = atom["kind"]
            next unless %w[int string].include?(kind.to_s)

            name = atom["path"].to_s.split(".").first
            next unless field_kind.key?(name)

            expected = field_kind[name] == "integer" ? "int" : "string"
            next if kind == expected

            findings << Finding.new(
              id: "PFS007", rule: "urn.schema.atoms[#{i}]",
              message: "atom kind #{kind.inspect} for field #{name.inspect} " \
                       "(declared kind: #{field_kind[name].inspect}) — numeric-kind " \
                       "safety: an int atom must reference a `kind: integer` field, " \
                       "a string atom a string field",
            )
          end

          (schema["types"] || []).each_with_index do |type, i|
            next unless type.is_a?(Hash)

            (type["core"] || []).each_with_index do |entry, j|
              path, kind = entry.is_a?(Array) ? entry : [entry, "string"]
              next unless %w[int string].include?(kind.to_s)

              name = path.to_s.split(".").first
              # A wrapper row's `number` is the wrapper ordinal — its kind
              # is supplements.number_kind, never a document field's.
              expected =
                if wrapper_tags.include?(type["type"]) && name == "number"
                  number_kind
                elsif field_kind.key?(name)
                  field_kind[name] == "integer" ? "int" : "string"
                else
                  next # the wrapper namespace: the validator resolves it
                end
              next if kind == expected

              findings << Finding.new(
                id: "PFS007", rule: "urn.schema.types[#{i}].core[#{j}]",
                message: "core kind #{kind.inspect} for #{name.inspect} " \
                         "(expected #{expected.inspect}) — numeric-kind safety: " \
                         "declare the source `kind: integer` or the core `string`",
              )
            end
          end
          findings
        end

        # --- PFS006: template citations (fast scan) -------------------------
        def check_template_citations(raw)
          findings = []
          fields = raw["fields"].is_a?(Hash) ? raw["fields"].keys : []
          known = fields.dup
          known << "supplements" if raw["supplements"].is_a?(Hash)

          templates(raw).each_with_index do |template, i|
            next unless template.is_a?(String)

            template.scan(/\{(\w+)\}/) do |(name)|
              next if known.include?(name)

              findings << Finding.new(
                id: "PFS006", rule: "templates (entry #{i})",
                message: "citation error: unknown field {#{name}} — a {brace} reference " \
                         "names a declared field (bare words name grammar rules); " \
                         "known fields: #{fields.sort.map(&:inspect).join(', ')} — " \
                         "declare it or fix the citation",
              )
            end
          end
          findings
        end

        # --- PFS009: the REQUIRED examples ----------------------------------
        def check_examples(raw)
          examples = raw["examples"]
          unless examples.is_a?(Hash)
            return [Finding.new(id: "PFS009", rule: "examples",
                                message: "section is required — the examples are the " \
                                         "live test panel, not documentation; capture a " \
                                         "specimen with `pfs capture`")]
          end
          positives = examples["positives"]
          unless positives.is_a?(Array) && !positives.empty?
            return [Finding.new(id: "PFS009", rule: "examples.positives",
                                message: "at least one positive example is required")]
          end

          findings = []
          positives.each_with_index do |row, i|
            next unless row.is_a?(Hash)

            input = row["input"]
            unless input.is_a?(String) && !input.empty?
              findings << Finding.new(id: "PFS009", rule: "examples.positives[#{i}].input",
                                      message: "must be an identifier string")
            end
          end
          findings
        end

        def templates(raw)
          t = raw["templates"].is_a?(Hash) ? raw["templates"] : {}
          [t["canonical"], *(t["alternates"] || [])].compact
        end
      end
    end
  end
end
