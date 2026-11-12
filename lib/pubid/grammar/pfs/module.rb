# frozen_string_literal: true

require "digest"

module Pubid
  module Grammar
    module Pfs
      # The module library (issue #706 §4): named, versioned, composable
      # scheme modules a definition binds through its `modules:` key.
      #
      # A module (`.pfsmod`, same strict YAML surface as a `.pfs`) declares
      # what it CONTRIBUTES and what it DEMANDS:
      #
      #   * `grammar:`   named lexical fragments, merged into the composed
      #                  grammar under their own names (collisions are
      #                  compile-time errors citing both claimants);
      #   * `tokens:`    head/type tokens the module claims — the
      #                  module-aware ambiguity checks hold the definition
      #                  and every co-bound module to them;
      #   * `parameters:` named, typed values the composing definition
      #                  supplies (`national.prefix`'s NSB tokens);
      #   * `identity:`  the IDENTITY composition the module declares —
      #                  `wrapper-with-adopted` (the bsi/cen `adopted`
      #                  model is the in-fleet precedent), not just
      #                  grammar: the compiled flavor carries it so its
      #                  consumers know the adopted document is the base;
      #   * `hooks:`     the named extension points where a body exceeds
      #                  the module's parameters and drops to a coded hook
      #                  beside its definition (the v1 escape hatch —
      #                  explicit, never implicit).
      #
      # Versioning fails closed: a `modules:` entry names the version its
      # definition was written against, and the compiler refuses an entry
      # whose version is unknown (newer than the library ships) or stale
      # (a module's major is its contract; no silent downgrade).
      module ModuleLibrary
        # A module's declared parameter: name, type, required flag.
        Parameter = Struct.new(:name, :type, :required, :description, keyword_init: true)
        # The identity composition a module declares.
        Identity = Struct.new(:composition, :base_module, :adopted_field, :hooks, keyword_init: true)
        # A loaded, validated module.
        Module = Struct.new(
          :source_path, :source_sha, :name, :version, :title, :description,
          :grammar, :tokens, :parameters, :identity, keyword_init: true,
        ) do
          def lookup(name)
            parameters.find { |p| p.name == name }
          end
        end
        # One `modules:` entry of a composing definition.
        Binding = Struct.new(:name, :version, :parameters, keyword_init: true)

        NAME = /\A[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)*\z/
        PARAMETER_TYPES = %w[tokens].freeze

        class UnknownModuleError < InvalidDefinition; end
        class VersionMismatchError < InvalidDefinition; end

        module_function

        # Load and validate every `.pfsmod` in +dir+. The directory may be
        # absent (an installation without the library): the library is then
        # empty and any `modules:` binding fails closed with the citation.
        # @param dir [String] the modules directory (`definitions/modules`)
        # @return [Hash{String => Module}] module name → module
        def load(dir)
          return {} unless dir && File.directory?(dir)

          Dir[File.join(dir, "*.pfsmod")].sort.each_with_object({}) do |path, loaded|
            module_name, mod = load_one(path)
            if loaded.key?(module_name)
              raise InvalidDefinition.new(
                "modules",
                "duplicate module name #{module_name.inspect}: " \
                "#{loaded[module_name].source_path} and #{path} both declare it",
              )
            end
            loaded[module_name] = mod
          end
        end

        # @return [Array(String, Module)] the module name and the module
        def load_one(path)
          raw = Loader.load(path)
          mod = validate_module(raw, source_path: path,
                                     source_sha: Digest::SHA256.hexdigest(File.binread(path)))
          [mod.name, mod]
        end

        # Validate a module document — the module-side mirror of
        # {Validator.validate}. Every rejection cites the module section.
        def validate_module(raw, source_path:, source_sha:)
          Validator.check_keys("module", raw,
                               %w[module version title description grammar
                                  tokens parameters identity hooks])
          name = raw["module"]
          unless name.is_a?(String) && NAME.match?(name)
            raise InvalidDefinition.new("module.module",
                                        "must be a dotted lower-case name, got #{name.inspect}")
          end
          version = raw["version"]
          unless version.is_a?(Integer)
            raise InvalidDefinition.new("module.#{name}.version",
                                        "must be an integer version")
          end

          grammar = raw["grammar"] || {}
          Validator.check_grammar_map(grammar, "module.#{name}.grammar")
          tokens = check_tokens(raw["tokens"] || [], name)
          parameters = check_parameters(raw["parameters"] || {}, name)
          identity = check_identity(raw["identity"], raw["hooks"], name)

          Module.new(
            source_path: source_path, source_sha: source_sha,
            name: name, version: version,
            title: raw["title"], description: raw["description"],
            grammar: grammar.freeze, tokens: tokens.freeze,
            parameters: parameters.freeze, identity: identity,
          )
        end

        def check_tokens(tokens, name)
          unless tokens.is_a?(Array) && tokens.all?(String) && tokens.all? { |t| !t.empty? }
            raise InvalidDefinition.new("module.#{name}.tokens",
                                        "must be an array of token strings")
          end
          tokens.each_with_index do |token, i|
            Validator.check_reserved("module.#{name}.tokens[#{i}]", token)
          end
          tokens
        end

        def check_parameters(params, name)
          unless params.is_a?(Hash)
            raise InvalidDefinition.new("module.#{name}.parameters", "must be a map")
          end
          params.map do |pname, body|
            unless pname.is_a?(String) && Validator::NAME.match?(pname)
              raise InvalidDefinition.new("module.#{name}.parameters.#{pname}",
                                          "parameter name must be lower-case snake_case")
            end
            Validator.check_keys("module.#{name}.parameters.#{pname}", body,
                                 %w[type required description])
            type = body["type"] || "tokens"
            unless PARAMETER_TYPES.include?(type)
              raise InvalidDefinition.new(
                "module.#{name}.parameters.#{pname}.type",
                "unsupported parameter type #{type.inspect} — pfs:1 carries " \
                "#{PARAMETER_TYPES.map(&:inspect).join(', ')}",
              )
            end
            Parameter.new(
              name: pname, type: type,
              required: body.fetch("required", false),
              description: body["description"],
            )
          end
        end

        # The identity declaration. v1 carries exactly one composition —
        # `wrapper-with-adopted` — because that is the in-fleet identity
        # model (the adopted document is the base); anything else fails
        # closed rather than declaring a composition the compiler cannot
        # hold the definition to.
        def check_identity(identity, hooks, name)
          return nil if identity.nil? && hooks.nil?

          if identity
            unless identity.is_a?(Hash)
              raise InvalidDefinition.new("module.#{name}.identity", "must be a map")
            end
            Validator.check_keys("module.#{name}.identity", identity,
                                 %w[composition base_module adopted_field])
            composition = identity["composition"]
            unless composition == "wrapper-with-adopted"
              raise InvalidDefinition.new(
                "module.#{name}.identity.composition",
                "unknown composition #{composition.inspect} — pfs:1 carries " \
                "wrapper-with-adopted (the adopted document is the base)",
              )
            end
            base_module = identity["base_module"]
            if base_module && !(base_module.is_a?(String) && NAME.match?(base_module))
              raise InvalidDefinition.new("module.#{name}.identity.base_module",
                                          "must name the module carrying the adopted face")
            end
            adopted_field = identity["adopted_field"]
            unless adopted_field.is_a?(String) && Validator::NAME.match?(adopted_field)
              raise InvalidDefinition.new("module.#{name}.identity.adopted_field",
                                          "must be the wrapper's adopted attribute name")
            end
          end

          Identity.new(
            composition: identity && identity["composition"],
            base_module: identity && identity["base_module"],
            adopted_field: identity && identity["adopted_field"],
            hooks: check_hooks(hooks, name),
          )
        end

        # Named extension points: a composing definition that fills a hook
        # must name one the module declared — an unclaimed hook name is a
        # typo today and a silent divergence tomorrow.
        def check_hooks(hooks, name)
          return {} if hooks.nil?
          unless hooks.is_a?(Hash) && hooks.all? { |k, _| k.is_a?(String) }
            raise InvalidDefinition.new("module.#{name}.hooks",
                                        "must be a map of hook name → description")
          end
          hooks
        end

        # Resolve a definition's `modules:` entries against the library:
        # every entry must name a known module at the version the library
        # ships (unknown = the definition is written against a library this
        # compiler does not have; stale = a silent downgrade), parameters
        # must match the module's declared ones. Returns the resolved
        # [Binding, Module] pairs in declaration order.
        # @raise [UnknownModuleError, VersionMismatchError, InvalidDefinition]
        def resolve(entries, library)
          entries.map do |binding|
            mod = library[binding.name]
            if mod.nil?
              raise UnknownModuleError.new(
                "modules",
                "unknown module #{binding.name.inspect} — the library carries " \
                "#{library.keys.sort.map(&:inspect).join(', ')} (fail-closed: a " \
                "module this compiler does not have cannot be composed)",
              )
            end
            unless binding.version == mod.version
              raise VersionMismatchError.new(
                "modules",
                "module #{binding.name.inspect} is bound at version " \
                "#{binding.version}; the library ships #{mod.version} " \
                "(fail-closed: a module's major is its contract)",
              )
            end
            check_binding_parameters(binding, mod)
            [binding, mod]
          end
        end

        def check_binding_parameters(binding, mod)
          supplied = binding.parameters || {}
          mod.parameters.each do |parameter|
            value = supplied[parameter.name]
            if value.nil?
              if parameter.required
                raise InvalidDefinition.new(
                  "modules",
                  "module #{mod.name.inspect} requires parameter " \
                  "#{parameter.name.inspect} — the binding does not supply it",
                )
              end
              next
            end
            check_parameter_value(parameter, value, mod)
          end
          unknown = supplied.keys - mod.parameters.map(&:name)
          unless unknown.empty?
            raise InvalidDefinition.new(
              "modules",
              "module #{mod.name.inspect} declares no parameter(s) " \
              "#{unknown.map(&:inspect).join(', ')} — declared: " \
              "#{mod.parameters.map(&:name).map(&:inspect).join(', ')}",
            )
          end
        end

        def check_parameter_value(parameter, value, mod)
          case parameter.type
          when "tokens"
            unless value.is_a?(Array) && value.all?(String) && value.all? { |t| !t.empty? }
              raise InvalidDefinition.new(
                "modules",
                "module #{mod.name.inspect} parameter #{parameter.name.inspect} " \
                "must be an array of token strings",
              )
            end
            value.each_with_index do |token, i|
              Validator.check_reserved(
                "modules (#{mod.name}.#{parameter.name}[#{i}])", token,
              )
            end
          end
        end
      end
    end
  end
end
