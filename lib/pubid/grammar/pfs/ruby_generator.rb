# frozen_string_literal: true

require "fileutils"

module Pubid
  module Grammar
    module Pfs
      # Emits the Ruby flavor module that vendors a compiled flavor: the
      # lutaml-model identifier, the builder, the renderer (generated from
      # the canonical template), the URN generator, the PubidUrn schema,
      # and the typed identifier classes. The generated code enters pubid
      # through the same doors as a coded flavor — input guards, the
      # unified error namespace, registry registration — so every
      # cross-flavor contract applies to it unchanged.
      #
      # v1 emits single-type schemes (one `types:` entry). Multi-type
      # dispatch is a later extension.
      class RubyGenerator
        # @return [Array<String>] the written file paths
        def self.emit(definition, flavor_key:, dir:, parsanol_version:)
          generator = new(definition, flavor_key: flavor_key,
                          parsanol_version: parsanol_version)
          generator.emit_to(dir)
        end

        attr_reader :definition, :key, :module_name, :parsanol_version

        def initialize(definition, flavor_key:, parsanol_version:)
          @definition = definition
          @key = flavor_key
          @module_name = PargGenerator.module_name(flavor_key)
          @parsanol_version = parsanol_version
          @type = definition.types.first or raise Error, "at least one type is required"
          raise Error, "v1 emits single-type schemes" if definition.types.size > 1
        end

        # The phase-3 machinery (pubid#706): supplement wrappers, list
        # captures, folds and MR hooks switch the emission to the
        # multi-class shape (a leaf Standard + synthesized wrapper
        # classes). Definitions without them keep the v1 single-class
        # shape byte-for-byte.
        def wrapper_mode?
          !definition.supplements.nil?
        end

        def has_list?
          definition.fields.any? { |f| f.kind == "list" && !f.builder_only }
        end

        def has_fold?
          definition.fields.any? { |f| f.fold }
        end

        def view_mode?
          wrapper_mode? || has_list? || has_fold?
        end

        # The fields the MODEL declares: the builder-only captures (fold
        # sources, the supplement run and its internals, list items) are
        # the builder's inputs, never columns.
        def model_fields
          definition.fields.reject(&:builder_only)
        end

        def emit_to(dir)
          files = {
            "#{key}.rb" => module_file,
            "#{key}/identifier.rb" => identifier_file,
            "#{key}/builder.rb" => builder_file,
            "#{key}/parser.rb" => parser_file,
            "#{key}/renderer.rb" => renderer_file,
            "#{key}/urn_generator.rb" => urn_generator_file,
            "#{key}/pubid_urn_schema.rb" => urn_schema_file,
            "#{key}/identifiers.rb" => identifiers_file,
            "#{key}/identifiers/#{@type.name}.rb" => type_file,
          }
          if wrapper_mode?
            definition.supplements.wrappers.each do |wrapper|
              files["#{key}/identifiers/#{wrapper.name}.rb"] = wrapper_file(wrapper)
            end
            files["#{key}/identifiers/supplement.rb"] = supplement_file
          end
          files.filter_map do |rel, content|
            path = File.join(dir, rel)
            FileUtils.mkdir_p(File.dirname(path))
            File.binwrite(path, content)
            path
          end
        end

        private

        def header
          <<~HEADER
            # frozen_string_literal: true
            #
            # PFS-generated flavor — DO NOT EDIT BY HAND.
            # Source: #{definition.source_path} (pfs:#{Pfs::SCHEMA_VERSION}) sha256:#{definition.source_sha}
            # Compiler: pubid/grammar/pfs #{Pfs::VERSION} (baked with parsanol #{parsanol_version})
            # Regenerate: ruby scripts/pfs compile #{definition.source_path} --as #{key} --ruby-out <dir>

          HEADER
        end

        def module_file
          # The empty case reproduces the pre-module body verbatim: the
          # placeholder line was a whitespace-only spacer there.
          replacement = modules_constant.empty? ? "    " : modules_constant
          body("#{header}#{module_body.sub('    __MODULES__', replacement)}")
        end

        # The MODULES constant, emitted only when the definition binds
        # modules (a module-free flavor keeps the body verbatim — the
        # placeholder substitutes to the empty string). Lines carry their
        # own four-space base: the placeholder sits inside the flavor's
        # module body.
        def modules_constant
          return "" if definition.modules.empty?

          lines = [
            "# The module composition the definition binds (issue #706 §4):",
            "# each entry names the library module, the version it was bound",
            "# at, and — where the module declares one — its IDENTITY",
            "# composition (wrapper-with-adopted: the adopted document is",
            "# the base). Carried so consumers and the wizard can",
            "# introspect what the flavor is composed of.",
            "MODULES = [",
          ]
          definition.modules.each do |mod|
            lines << "  #{module_entry_source(mod)},"
          end
          lines << "].freeze"
          lines.map { |line| "    #{line}" }.join("\n")
        end

        def module_entry_source(mod)
          identity = mod.identity
          ruby_hash_literal(
            name: mod.name, version: mod.version,
            identity: identity && {
              composition: identity.composition,
              base_module: identity.base_module,
              adopted_field: identity.adopted_field&.to_sym,
            },
          )
        end

        # Inspectable, deterministic, no ActiveSupport: a plain Hash literal.
        def ruby_hash_literal(hash)
          inner = hash.filter_map do |key, value|
            next if value.nil?

            "#{key}: #{ruby_value(value)}"
          end.join(", ")
          "{ #{inner} }"
        end

        # A valid symbol literal for any token (hyphenated tokens need
        # the quoted form).
        def symbol_literal(token)
          if /\A[A-Za-z_][A-Za-z0-9_]*\z/.match?(token.to_s)
            ":#{token}"
          else
            format(':"%s"', token)
          end
        end

        def ruby_value(value)
          case value
          when String then value.inspect
          when Symbol then ":#{value}"
          when Integer then value.to_s
          when Hash then ruby_hash_literal(value)
          else value.inspect
          end
        end

        def module_body
          <<~RUBY
            require "pubid"

            module Pubid
              # #{definition.title || definition.scheme} flavor, compiled from its PFS definition
              # (pubid/pubid#706). A compiled flavor is a peer of the coded
              # flavors: same registry, same input guards, same error
              # namespace, same URN contracts.
              module #{module_name}
                extend Pubid::PrefixesSupport

                PREFIXES = #{ruby_array(definition.organization.prefixes)}.freeze
                __MODULES__

                autoload :Builder, "#{__dir_placeholder__}/#{key}/builder"
                autoload :Identifier, "#{__dir_placeholder__}/#{key}/identifier"
                autoload :Identifiers, "#{__dir_placeholder__}/#{key}/identifiers"
                autoload :Parser, "#{__dir_placeholder__}/#{key}/parser"
                autoload :Renderer, "#{__dir_placeholder__}/#{key}/renderer"
                autoload :PubidUrnSchema, "#{__dir_placeholder__}/#{key}/pubid_urn_schema"
                autoload :UrnGenerator, "#{__dir_placeholder__}/#{key}/urn_generator"

                def self.parse(identifier)
                  Identifier.parse(identifier)
                end

                Identifier.format_registry = FormatRegistry.new(parent: Identifier.format_registry)
                Identifier.format_registry.register(:human, renderer: #{module_name}::Renderer)

                def self.identifier_types
                  @identifier_types ||= Identifiers.constants
                    .filter_map { |c| begin; Identifiers.const_get(c); rescue NameError; nil; end }
                    .select { |c| c.is_a?(Class) && c.singleton_methods(false).include?(:type) }
                    .select { |c| c.type.is_a?(Hash) }
                end

                def self.all_typed_stages
                  @all_typed_stages ||= identifier_types.flat_map do |klass|
                    klass.const_defined?(:TYPED_STAGES) ? klass.const_get(:TYPED_STAGES) : []
                  end
                end

                def self.locate_type(code)
                  identifier_types.find { |t| t.type[:key].to_s == code.to_s }
                end

                def self.locate_stage(abbr)
                  abbr_str = abbr.to_s.upcase
                  all_typed_stages.find { |s| s.abbr.any? { |a| a.to_s.upcase == abbr_str } }
                end
              end
            end

            Pubid::Registry.register(:#{key}, Pubid::#{module_name})
          RUBY
        end

        def identifier_file
          # The wrapper shape: the shared base carries only the publisher
          # column (the MR publisher segment reads it) and the parse
          # funnel; the columns live on the leaf Standard and the wrapper
          # attributes on the synthesized Supplement.
          return body(wrapper_identifier_file) if wrapper_mode?

          # With the calendar binding, the date fields fold into the shared
          # Components::Date (the coded flavors' own shape): one attribute,
          # flat year/month/day key_value converters, and a builder that
          # composes the component. Without it, every field is a plain
          # string attribute (doi's shape).
          if date_binding
            plain = definition.fields.reject { |f| date_binding.fields.include?(f.name) }
            attrs = plain.map do |field|
              "        attribute :#{field.name}, :#{field.kind}"
            end
            attrs << "        attribute :date, ::Pubid::Components::Date"
            maps = plain.map do |field|
              "          map #{field.name.inspect}, to: :#{field.name}"
            end
            maps.concat(date_binding.fields.map do |f|
              "          map \"#{f}\", with: { to: :#{f}_to_kv, from: :#{f}_from_kv }"
            end)
            body(identifier_file_body(attrs.join("\n"), maps.join("\n"),
                                      converters: date_converter_source))
          else
            attrs = definition.fields.map do |field|
              "        attribute :#{field.name}, :#{field.kind}"
            end.join("\n")
            maps = definition.fields.map do |field|
              "          map #{field.name.inspect}, to: :#{field.name}"
            end.join("\n")
            body(identifier_file_body(attrs, maps))
          end
        end

        # The flat date converters, mirroring the coded flavors' shape:
        # the date serializes as flat year/month/day keys (nils omitted)
        # and each key rebuilds its component field on from_hash. Lines
        # carry their own base indentation: the block interpolates at the
        # class body level.
        def date_converter_source
          converters = date_binding.fields.flat_map do |f|
            [
              "          # --- date serialized flat (the shared flat-scalar shape) ---",
              "          def #{f}_to_kv(model, doc)",
              "            emit_date_part(doc, \"#{f}\", model.date&.#{f})",
              "          end",
              "",
              "          def #{f}_from_kv(model, value)",
              "            date_for(model).#{f} = value.to_s",
              "          end",
              "",
            ]
          end
          [
            *converters,
            "          def emit_date_part(doc, key, val)",
            "            return if val.nil? || val.to_s.empty?",
            "",
            "            doc.add_child(Lutaml::KeyValue::DataModel::Element.new(key, val.to_s))",
            "          end",
            "",
            "          def date_for(model)",
            "            model.date ||= ::Pubid::Components::Date.new",
            "          end",
          ].join("\n")
        end

        def date_binding
          definition.date
        end

        def identifier_file_body(attrs, maps, converters: nil)
          <<~RUBY
            module Pubid
              module #{module_name}
                class Identifier < ::Pubid::Identifier
          #{attrs.chomp}

                  #{@type.key.upcase}_TYPE_MAP = {
                    #{@type.tag.inspect} => "Pubid::#{module_name}::Identifiers::#{camelize(@type.name)}",
                  }.freeze

                  key_value do
                    map "_type", to: :_type, polymorphic_map: #{@type.key.upcase}_TYPE_MAP
          #{maps.chomp}
                  end
          #{converters ? "\n#{converters.chomp}\n" : ""}
                  PUBLISHER = #{definition.organization.publisher.inspect}

                  # The scheme's declared publisher token: the internal-form
                  # cut (to_s(with_publisher: false)) strips it from the
                  # rendered face.
                  def publisher_prefixes
                    [PUBLISHER]
                  end

                  def self.parse(identifier)
                    unless identifier.is_a?(String)
                      raise Pubid::Errors::InvalidInputError,
                            Pubid::INPUT_NOT_A_STRING_MESSAGE
                    end

                    if identifier.length > Pubid::MAX_INPUT_LENGTH
                      raise Pubid::Errors::InvalidInputError, Pubid::INPUT_TOO_LONG_MESSAGE
                    end

                    identifier = ::Pubid.utf8_input(identifier)

                    parsed = Pubid::Parg::Model.bound(:#{key}, identifier)
                    Builder.build(parsed)
                  end
                end
              end
            end
          RUBY
        end

        # The wrapper shape's shared base: the publisher column only (the
        # MR publisher segment reads it) plus the parse funnel. The
        # columns live on the leaf Standard and the wrapper attributes on
        # the synthesized Supplement — each concrete class declares its
        # own key_value block (a subclass block REPLACES the parent's,
        # the coded leaf-placement rule), so the base declares none.
        def wrapper_identifier_file
          lines = []
          lines << "module Pubid"
          lines << "  module #{module_name}"
          lines << "    class Identifier < ::Pubid::Identifier"
          lines << "      attribute :publisher, :string, default: -> { #{definition.organization.publisher.inspect} }"
          lines << ""
          lines << "      PUBLISHER = #{definition.organization.publisher.inspect}"
          lines << ""
          lines << "      # The scheme's declared publisher token: the internal-form"
          lines << "      # cut (to_s(with_publisher: false)) strips it from the"
          lines << "      # rendered face."
          lines << "      def publisher_prefixes"
          lines << "        [PUBLISHER]"
          lines << "      end"
          lines << ""
          lines << "      def self.parse(identifier)"
          lines << "        unless identifier.is_a?(String)"
          lines << "          raise Pubid::Errors::InvalidInputError,"
          lines << "                Pubid::INPUT_NOT_A_STRING_MESSAGE"
          lines << "        end"
          lines << ""
          lines << "        if identifier.length > Pubid::MAX_INPUT_LENGTH"
          lines << "          raise Pubid::Errors::InvalidInputError, Pubid::INPUT_TOO_LONG_MESSAGE"
          lines << "        end"
          lines << ""
          lines << "        identifier = ::Pubid.utf8_input(identifier)"
          lines << ""
          lines << "        parsed = Pubid::Parg::Model.bound(:#{key}, identifier)"
          lines << "        Builder.build(parsed)"
          lines << "      end"
          lines << "    end"
          lines << "  end"
          lines << "end"
          lines.join("\n") << "\n"
        end

        def builder_file
          return body(wrapper_builder_file) if wrapper_mode?

          if date_binding
            plain = definition.fields.reject { |f| date_binding.fields.include?(f.name) }
            args = plain.map do |field|
              "          #{field.name}: data[:#{field.name}]"
            end.join(",\n")
            body(<<~RUBY)
              module Pubid
                module #{module_name}
                  class Builder
                    def self.build(parsed_data)
                      new.build(parsed_data)
                    end

                    def build(data)
                      Identifiers::#{camelize(@type.name)}.new(
            #{args.chomp},
                        date: build_date(data),
                      )
                    end

                    private

                    # The publication date as the shared Components::Date, or
                    # nil when the reference omits the calendar fields (a
                    # partial reference matches by excluding the date).
                    def build_date(data)
                      values = [#{date_binding.fields.map { |f| "data[:#{f}]" }.join(", ")}]
                      return nil if values.compact.empty?

                      ::Pubid::Components::Date.new(
            #{date_binding.fields.map { |f| "          #{f}: data[:#{f}]&.to_s" }.join(",\n")},
                      )
                    end
                  end
                end
              end

              Pubid::#{module_name}::Builder.prepend(Pubid::Builder::AllPartsWrap)
            RUBY
          else
            args = definition.fields.map do |field|
              "          #{field.name}: data[:#{field.name}]"
            end.join(",\n")

            body(<<~RUBY)
              module Pubid
                module #{module_name}
                  class Builder
                    def self.build(parsed_data)
                      new.build(parsed_data)
                    end

                    def build(data)
                      Identifiers::#{camelize(@type.name)}.new(
            #{args.chomp},
                      )
                    end
                  end
                end
              end

              Pubid::#{module_name}::Builder.prepend(Pubid::Builder::AllPartsWrap)
            RUBY
          end
        end

        # The wrapper shape's builder: the base standard receives every
        # non-fold column (lists mapped out of their item rows), the fold
        # lands on its target column plus the boolean flag, and the
        # supplement run folds into the declared wrapper classes outermost
        # last — the printed run's order IS the nesting ("/A1/C1" is
        # Corrigendum over Amendment over the standard).
        # The wrapper shape's builder: the base standard receives every
        # model column (lists mapped out of their bound item rows), the
        # fold lands on its target column plus the boolean flag, and the
        # supplement run folds into the declared wrapper classes
        # outermost-last — the printed run's order IS the nesting
        # ("/A1/C1" is Corrigendum over Amendment over the standard).
        def wrapper_builder_file
          lines = []
          lines << "module Pubid"
          lines << "  module #{module_name}"
          lines << "    class Builder"
          wrappers = definition.supplements.wrappers
          lines << "      # The wrapper classes by kind face: the run's dispatch."
          lines << "      SUPPLEMENT_WRAPPERS = {"
          wrappers.each do |wrapper|
            lines << "        \"#{wrapper.face}\" => Identifiers::#{camelize(wrapper.name)},"
          end
          lines << "      }.freeze"
          lines << ""
          lines << "      def self.build(parsed_data)"
          lines << "        new.build(parsed_data)"
          lines << "      end"
          lines << ""
          lines << "      def build(data)"
          lines << "        identifier = Identifiers::#{camelize(@type.name)}.new("
          item_names = definition.fields
            .select { |f| f.kind == "list" && f.item }.map(&:item)
          fold_targets = definition.fields
            .select(&:fold).map { |f| f.fold.into }
          emitted = {}
          definition.fields.each do |field|
            next if emitted[field.name]
            next if supplement_run_internal?(field)
            next if item_names.include?(field.name)
            # The fold's target column receives its value through the
            # fold source's row (the fold lands below).
            next if fold_targets.include?(field.name) && !field.fold

            if field.kind == "list" && !field.builder_only
              lines << "          #{field.name}: build_#{field.name}(data),"
              emitted[field.name] = true
            elsif field.fold
              lines << "          #{field.fold.into}: data[:#{field.fold.into}] || data[:#{field.name}],"
              lines << "          #{field.fold.flag}: !data[:#{field.name}].nil?,"
              emitted[field.name] = true
              emitted[field.fold.into] = true
            elsif !field.builder_only
              lines << "          #{field.name}: data[:#{field.name}],"
              emitted[field.name] = true
            end
          end
          lines << "        )"
          run = definition.supplements
          lines << "        run = Array(data[:#{run.run}])"
          lines << "        run.each do |row|"
          lines << "          item = row[:#{run.item}] || row[\"#{run.item}\"] || {}"
          lines << "          kind = unwrap(item[:#{run.kind}] || item[\"#{run.kind}\"])"
          lines << "          identifier = SUPPLEMENT_WRAPPERS.fetch(kind).new("
          lines << "            number: unwrap(item[:#{run.number}] || item[\"#{run.number}\"]).to_i,"
          lines << "            base: identifier,"
          lines << "          )"
          lines << "        end"
          lines << "        identifier"
          lines << "      end"
          lines << ""
          lines << "      # The run's internal captures bind only through the item row"
          lines << "      # (the cen_cenelec precedent), so unbound ones arrive as raw"
          lines << "      # leaves — a Parsanol::Slice or a {value:, offset: ...} span."
          lines << "      # Unwrap the captured value."
          lines << "      def unwrap(capture)"
          lines << "        return capture.content if capture.is_a?(Parsanol::Slice)"
          lines << "        return capture[:value] if capture.is_a?(Hash) && capture.key?(:value)"
          lines << ""
          lines << "        capture"
          lines << "      end"
          definition.fields
            .select { |f| f.kind == "list" && !f.builder_only }.each do |field|
            lines << ""
            lines << "      # The #{field.name} column from its bound item rows."
            lines << "      def build_#{field.name}(data)"
            lines << "        Array(data[:#{field.name}]).map do |row|"
            lines << "          row[:#{field.item}] || row[\"#{field.item}\"]"
            lines << "        end.compact"
            lines << "      end"
          end
          lines << "    end"
          lines << "  end"
          lines << ""
          lines << "  Pubid::#{module_name}::Builder.prepend(Pubid::Builder::AllPartsWrap)"
          lines << "end"
          lines.join("\n") << "\n"
        end

        def parser_file
          body(<<~RUBY)
            module Pubid
              module #{module_name}
                # PFS-generated parser shell. Parsing runs through the baked
                # PARG artifact (data/parg/#{key}.json) via Pubid::Parg::Model.bound;
                # the grammar source lives in pubid-grammar
                # (grammars/#{key}.parg, compiled from #{definition.source_path}).
                class Parser
                end
              end
            end
          RUBY
        end

        def renderer_file
          return body(wrapper_renderer_file) if view_mode?

          body(<<~RUBY)
            module Pubid
              module #{module_name}
                # Human renderer, generated from the canonical template.
                class Renderer < ::Pubid::Renderers::Base
                  def render(**_opts)
                    #{render_expression}
                  end
                end
              end
            end
          RUBY
        end

        # The wrapper shape's renderer: the canonical face evaluated over
        # a FIELD VIEW, so a supplement wrapper renders its base's columns
        # with the notation run inserted where the run segment sits — the
        # same composition semantics the compiler's own template verifier
        # applies (the verified `renders:` rows and this renderer cannot
        # disagree).
        def wrapper_renderer_file
          face = wrapper_render_expression
          lines = []
          lines << "module Pubid"
          lines << "  module #{module_name}"
          lines << "    # Human renderer, generated from the canonical template."
          lines << "    class Renderer < ::Pubid::Renderers::Base"
          lines << "      def render(**_opts)"
          lines << "        f = render_fields(@id)"
          lines << "        \"#{face}\""
          lines << "      end"
          lines << ""
          lines << "      private"
          lines << ""
          lines << "      # The field view: a supplement wrapper reads through to"
          lines << "      # the wrapped standard and carries the notation run"
          lines << "      # (\"/A1/C1\", outermost last); the fold's target renders"
          lines << "      # only outside the fold flag (the V/ed faces are mutually"
          lines << "      # exclusive by grammar)."
          lines << "      def render_fields(id)"
          lines << "        root = id"
          lines << "        run = +\"\""
          lines << "        while root.is_a?(Identifiers::Supplement)"
          lines << "          run.prepend(\"/\#{root.supplement_notation}\")"
          lines << "          root = root.base"
          lines << "        end"
          # The view keys: every field a face may reference — the model
          # columns, a fold's SOURCE (its value under the flag), and the
          # supplement run (the notations). List items and the run's
          # internals are never faces.
          item_names = definition.fields
            .select { |f| f.kind == "list" && f.item }.map(&:item)
          face_fields = definition.fields.select do |field|
            next false if item_names.include?(field.name)
            next false if supplement_run_internal?(field)

            !field.builder_only || field.fold ||
              field.name == definition.supplements&.run
          end
          fold_targets = definition.fields.select(&:fold)
            .map { |field| field.fold.into }
          lines << "        {"
          face_fields.each do |field|
            if field.kind == "list" && field.name == definition.supplements&.run
              lines << "          #{field.name}: run.empty? ? nil : run,"
            elsif field.kind == "list"
              glue = field.render&.glue || "-"
              lines << "          #{field.name}: root.#{field.name}.any? ? root.#{field.name}.map { |item| \"#{glue}\#{item}\" }.join : nil,"
            elsif field.fold
              # The fold's source renders under the flag: its value is
              # the folded column's.
              lines << "          #{field.name}: root.#{field.fold.flag} ? root.#{field.fold.into} : nil,"
            elsif fold_targets.include?(field.name)
              # The fold's TARGET column is invisible to the plain face
              # while the flag holds (the V and ed faces are mutually
              # exclusive by grammar — the view restores that split).
              source = definition.fields.find { |f| f.fold&.into == field.name }
              lines << "          #{field.name}: root.#{source.fold.flag} ? nil : root.#{field.name},"
            else
              lines << "          #{field.name}: root.#{field.name},"
            end
          end
          lines << "        }"
          lines << "      end"
          lines << "    end"
          lines << "  end"
          lines << "end"
          lines.join("\n") << "\n"
        end

        # The supplement run's generated internals (item, kind, number)
        # — never model columns, never render faces.
        def supplement_run_internal?(field)
          return false unless definition.supplements

          [definition.supplements.item, definition.supplements.kind,
           definition.supplements.number].include?(field.name)
        end

        def urn_generator_file
          segments = definition.urn.official || []
          if segments.empty?
            body(<<~RUBY)
              module Pubid
                module #{module_name}
                  # The official URN generator, pinned to the scheme's declared
                  # namespace (#{definition.urn.namespace.inspect}) so to_urn stays
                  # scheme-canonical under the compiled flavor key.
                  class UrnGenerator < ::Pubid::UrnGenerator::Base
                    def urn_namespace
                      #{definition.urn.namespace.inspect}
                    end
                  end
                end
              end
            RUBY
          elsif wrapper_mode?
            wrapper_urn_generator_file(segments)
          else
            body(<<~RUBY)
              module Pubid
                module #{module_name}
                  # The official URN generator: the scheme's declared namespace
                  # (#{definition.urn.namespace.inspect}) and the ordered segments the
                  # definition's urn.official declares — an absent field leaves no
                  # segment, a date group joins its fields with "-".
                  class UrnGenerator < ::Pubid::UrnGenerator::Base
                    def urn_namespace
                      #{definition.urn.namespace.inspect}
                    end

                    def generate
                      parts = ["urn", urn_namespace]
                      parts.concat(official_segments)
                      parts.join(":")
                    end

                    private

                    def official_segments
                      segments = []
                      #{segments.map { |segment| urn_segment_source(segment) }.join("\n        ")}
                      segments
                    end
                  end
                end
              end
            RUBY
          end
        end

        # The wrapper shape's official generator: every segment reads the
        # SUBJECT (a supplement wrapper reads through to the wrapped
        # standard — the coded generator's own delegation shape, so a
        # supplement's URN is its base's composition, byte-identical with
        # the coded flavor).
        def wrapper_urn_generator_file(segments)
          <<~RUBY
            module Pubid
              module #{module_name}
                # The official URN generator: the scheme's declared namespace
                # (#{definition.urn.namespace.inspect}) and the ordered segments the
                # definition's urn.official declares — an absent field leaves no
                # segment, a date group joins its fields with "-", a compose
                # slots its fields with the declared glue, and a fold target
                # switches to its edition affix while the flag holds.
                class UrnGenerator < ::Pubid::UrnGenerator::Base
                  def urn_namespace
                    #{definition.urn.namespace.inspect}
                  end

                  def generate
                    parts = ["urn", urn_namespace]
                    parts.concat(official_segments)
                    parts.join(":")
                  end

                  private

                  # A supplement wrapper reads through to the wrapped
                  # standard (the coded generator's own delegation shape).
                  def subject
                    current = @identifier
                    current = current.base while current.is_a?(Identifiers::Supplement)
                    current
                  end

                  def official_segments
                    segments = []
                    #{segments.map { |segment| urn_segment_source(segment) }.join("\n        ")}
                    segments
                  end
                end
              end
            end
          RUBY
        end

        # One urn.official segment as the generator's Ruby lines. A field
        # under the date binding reads the calendar component (nil-safe),
        # a plain field reads the attribute (or the subject, under the
        # wrapper shape); affix/edition_affix/lower decorate the value;
        # a compose slots its fields with the declared glue.
        def urn_segment_source(segment)
          case segment
          when Definition::UrnField
            if segment.edition_affix
              edition_affix_source(segment)
            elsif segment.affix
              "segments << #{segment.affix.inspect} + #{urn_field_reader(segment.name)}.to_s#{lower_suffix(segment)} if #{urn_field_guard(segment.name)}"
            elsif segment.lower
              "segments << #{urn_field_reader(segment.name)}.to_s.downcase if #{urn_field_guard(segment.name)}"
            else
              "segments << #{urn_field_reader(segment.name)} if #{urn_field_guard(segment.name)}"
            end
          when Definition::UrnDate
            date = segment.fields.map { |f| urn_field_reader(f) }.join(", ")
            "date = [#{date}].compact\n" \
              "        segments << date.join(\"-\") unless date.empty?"
          when Definition::UrnCompose
            compose_source(segment)
          end
        end

        # The fold-aware version segment: while the fold flag holds the
        # value carries the edition affix, otherwise the plain affix —
        # the coded generator's `version.to_s.downcase` split (V…/ed…)
        # restored by declaration.
        def edition_affix_source(segment)
          fold = definition.fields.find { |f| f.fold&.into == segment.name }
          flag = fold.fold.flag
          lower = segment.lower ? ".downcase" : ""
          [
            "if #{urn_field_guard(flag)}",
            "  segments << #{segment.edition_affix.inspect} + #{urn_field_reader(segment.name)}.to_s#{lower}",
            "elsif #{urn_field_guard(segment.name)}",
            "  segments << #{segment.affix.inspect} + #{urn_field_reader(segment.name)}.to_s#{lower}",
            "end",
          ].join("\n        ")
        end

        # The composed code segment: ordered slots, each with the glue
        # that precedes it (per item under `prefix` — the parts-run
        # shape; before the value under `infix`). The first slot carries
        # no glue. The compose renders only when any slot did.
        def compose_source(segment)
          lines = ["code = []"]
          segment.slots.each_with_index do |slot, i|
            reader = urn_field_reader(slot.field)
            field = definition.fields.find { |f| f.name == slot.field }
            glue = slot.glue.inspect
            if field&.kind == "list" && !field.builder_only
              if slot.style == "infix"
                if i.zero?
                  lines << "code << subject.#{slot.field}.join(#{glue}) if subject.#{slot.field}.any?"
                else
                  lines << "code << #{glue} + subject.#{slot.field}.join(#{glue}) if subject.#{slot.field}.any?"
                end
              else
                lines << "subject.#{slot.field}.each { |item| code << #{glue} + item } if subject.#{slot.field}.any?"
              end
            elsif i.zero?
              lines << "code << #{reader}.to_s if #{urn_field_guard(slot.field)}"
            else
              lines << "code << #{glue} + #{reader}.to_s if #{urn_field_guard(slot.field)}"
            end
          end
          lines << "segments << code.join unless code.empty?"
          lines.join("\n        ")
        end

        def lower_suffix(segment)
          segment.lower ? ".downcase" : ""
        end

        def urn_field_reader(name)
          root = wrapper_mode? ? "subject" : "@identifier"
          if date_binding && date_binding.fields.include?(name)
            "#{root}.date&.#{name}"
          else
            "#{root}.#{name}"
          end
        end

        def urn_field_guard(name)
          urn_field_reader(name)
        end

        def urn_schema_file
          atoms = definition.urn.atoms.map do |atom|
            "        atom #{atom.path.inspect}, #{atom.prefix.inspect}"
          end.join("\n")
          types = definition.urn.types.map do |type|
            "        type #{type.type.inspect}, #{type.token.inspect}, core: #{core_literal(type.core)}"
          end.join("\n")

          body(<<~RUBY)
            module Pubid
              module #{module_name}
                # The pubid-scheme URN schema, registered under the compiled
                # flavor key. The definition's declared namespace
                # (#{definition.urn.namespace.inspect}) is the scheme's canonical
                # namespace; identifiers carry the scheme's wire tag, so their
                # pubid URNs encode through the scheme's own schema.
                PubidUrnSchema = Pubid::PubidUrn.define("#{key}") do
          #{atoms.chomp}
          #{types.chomp}
                end
              end
            end
          RUBY
        end

        def identifiers_file
          if wrapper_mode?
            rows = [camelize(@type.name), "Supplement"] +
              definition.supplements.wrappers.map { |w| camelize(w.name) }
            rows_source = rows.map do |name|
              "            autoload :#{name}, \"#{__dir_placeholder__}/identifiers/#{name.downcase}\""
            end.join("\n")
            return body(<<~RUBY)
              module Pubid
                module #{module_name}
                  module Identifiers
              #{rows_source.chomp}
                  end
                end
              end
            RUBY
          end
          body(<<~RUBY)
            module Pubid
              module #{module_name}
                module Identifiers
                  autoload :#{camelize(@type.name)}, "#{__dir_placeholder__}/identifiers/#{@type.name}"
                end
              end
            end
          RUBY
        end

        def type_file
          stage = @type.stage
          typed_stages = if stage
            ["          TYPED_STAGES = [",
             "            Pubid::Components::TypedStage.new(",
             "              code: :#{stage.code},",
             "              stage_code: :#{stage.stage_code},",
             "              type_code: :#{@type.key},",
             "              abbr: #{ruby_array(stage.abbr)},",
             "              name: #{@type.title.inspect},",
             "              harmonized_stages: [],",
             "            ),",
             "          ].freeze"].join("\n")
          else
            "          TYPED_STAGES = [].freeze"
          end

          if wrapper_mode?
            return body(wrapper_type_file(typed_stages))
          end

          body(<<~RUBY)
            module Pubid
              module #{module_name}
                module Identifiers
                  # Concrete #{@type.title} identifier type (PFS type `#{@type.name}`).
                  class #{camelize(@type.name)} < Identifier
          #{typed_stages.chomp}

                    def self.type
                      { key: #{symbol_literal(@type.key)}, web: #{symbol_literal(@type.web)}, title: #{@type.title.inspect}, short: #{@type.short.inspect} }
                    end

                    # The scheme-canonical wire tag declared in the definition:
                    # to_hash stays byte-identical with the scheme's coded
                    # flavor, and this flavor's own from_hash routes the tag
                    # to this class.
                    def self.polymorphic_name
                      #{@type.tag.inspect}
                    end
                  end
                end
              end
            end
          RUBY
        end

        # The leaf Standard under the wrapper shape: the columns live here
        # (the shared base carries only the publisher), with its own
        # key_value block (a subclass block replaces the parent's — the
        # coded leaf-placement rule) and the scheme-canonical wire tag.
        # The MR hooks (declared under `mr:`) fill the shared MrString
        # renderer's slots; the sanitize mirrors the coded flavors'
        # charset rule (lowercase, [a-z0-9-], runs collapsed — the BIPM
        # precedent).
        def wrapper_type_file(typed_stages)
          lines = []
          lines << "module Pubid"
          lines << "  module #{module_name}"
          lines << "    module Identifiers"
          lines << "      # Concrete #{@type.title} identifier type (PFS type `#{@type.name}`)."
          lines << "      class #{camelize(@type.name)} < Identifier"
          lines << typed_stages
          lines << ""
          model_fields.each do |field|
            if field.kind == "list"
              lines << "      attribute :#{field.name}, :string, collection: true, initialize_empty: true"
            else
              lines << "      attribute :#{field.name}, :#{field.kind}"
            end
          end
          definition.fields.select(&:fold).each do |field|
            lines << "      attribute :#{field.fold.flag}, :boolean, default: -> { false }"
          end
          lines << ""
          lines << "        key_value do"
          lines << "          map \"_type\", to: :_type"
          model_fields.each do |field|
            lines << "          map #{field.name.inspect}, to: :#{field.name}"
          end
          definition.fields.select(&:fold).each do |field|
            lines << "          map #{field.fold.flag.inspect}, to: :#{field.fold.flag}"
          end
          lines << "        end"
          lines << ""
          lines << "        def self.type"
          lines << "          { key: #{symbol_literal(@type.key)}, web: #{symbol_literal(@type.web)}, title: #{@type.title.inspect}, short: #{@type.short.inspect} }"
          lines << "        end"
          lines << ""
          lines << "        # The scheme-canonical wire tag declared in the definition:"
          lines << "        # to_hash stays byte-identical with the scheme's coded"
          lines << "        # flavor, and this flavor's own from_hash routes the tag"
          lines << "        # to this class."
          lines << "        def self.polymorphic_name"
          lines << "          #{@type.tag.inspect}"
          lines << "        end"
          mr_hook_lines.each do |line|
            lines << line
          end
          lines << "      end"
          lines << "    end"
          lines << "  end"
          lines << "end"
          lines.join("\n") << "\n"
        end

        # The mr: hooks as the leaf's methods, named after the shared
        # MrString renderer's hook slots. A {field:} hook reads the
        # column; a {join:} hook flattens (a list joins its items), keeps
        # the present values in order and glues them; everything passes
        # through the charset sanitize, and a fully-empty hook answers
        # nil (the shared renderer skips a nil segment).
        MR_HOOK_NAMES = {
          "type" => "mr_type",
          "number" => "mr_number_with_part",
          "year" => "mr_year",
          "edition" => "mr_edition",
        }.freeze

        def mr_hook_lines
          mr = definition.mr
          return [] unless mr

          lines = [""]
          mr.segments.each do |segment, hook|
            method = MR_HOOK_NAMES.fetch(segment)
            lines << "        def #{method}"
            lines << "          mr_sanitize(#{mr_hook_expression(hook)})"
            lines << "        end"
            lines << ""
          end
          lines.concat([
            "        # The MR charset rule (the coded flavors' mr_sanitize):",
            "        # lowercase, [a-z0-9-], non-charset runs collapsed to one",
            "        # dash; empty answers nil so the joined slug never gains a",
            "        # blank segment.",
            "        def mr_sanitize(value)",
            "          return nil if value.nil? || value.to_s.empty?",
            "",
            "          sanitized = value.to_s.downcase",
            "            .gsub(/[^a-z0-9-]+/, \"-\").gsub(/\\A-+|-+\\z/, \"\")",
            "          sanitized.empty? ? nil : sanitized",
            "        end",
          ])
          lines
        end

        def mr_hook_expression(hook)
          if Definition::MrField === hook
            hook.field.to_s
          else # MrJoin
            parts = hook.join.map do |name|
              field = definition.fields.find { |f| f.name == name }
              if field&.kind == "list" && !field.builder_only
                "*Array(#{name})"
              else
                name.to_s
              end
            end
            "[#{parts.join(', ')}].compact.join(#{hook.glue.inspect})"
          end
        end

        # The synthesized supplement wrapper classes: the kind face and
        # the scheme-canonical wire tag per class, over the shared
        # Supplement base.
        def wrapper_file(wrapper)
          <<~RUBY
            module Pubid
              module #{module_name}
                module Identifiers
                  # The synthesized #{wrapper.title} wrapper (PFS supplements
                  # declaration): the kind face "#{wrapper.face}" is the run's
                  # dispatch token and the printed notation's face.
                  class #{camelize(wrapper.name)} < Supplement
                    FACE = "#{wrapper.face}".freeze

                    def self.face
                      FACE
                    end

                    def self.polymorphic_name
                      #{wrapper.tag.inspect}
                    end
                  end
                end
              end
            end
          RUBY
        end

        # The supplement wrapper base: wraps its base standard, carries
        # its own Integer ordinal, serializes as {_type, number, base}
        # (the coded supplement shape — type/code/version/date delegate),
        # and renders the MR suffix the shared MrString recurses on.
        def supplement_file
          <<~RUBY
            module Pubid
              module #{module_name}
                module Identifiers
                  # The supplement wrapper base (pubid#706 phase 3): the
                  # wrapper owns its ordinal and the base identifier; every
                  # delegated attribute reads through.
                  class Supplement < ::Pubid::#{module_name}::Identifier
                    attribute :base, ::Pubid::#{module_name}::Identifier
                    attribute :number, :integer

                    key_value do
                      map "_type", to: :_type
                      map "number", to: :number
                      map "base", with: { to: :base_to_kv, from: :base_from_kv }
                    end

                    # Serialize the base via its own to_hash so it collapses
                    # to the leaf standard shape (the coded converters'
                    # rule).
                    def base_to_kv(model, doc)
                      return unless model.base

                      doc.add_child(
                        Lutaml::KeyValue::DataModel::Element.new("base", model.base.to_hash),
                      )
                    end

                    # Re-dispatch through the flavor base so _type resolves
                    # to the concrete Standard (the coded JCGM/ETSI rule).
                    def base_from_kv(model, value)
                      return unless value

                      model.base = ::Pubid::#{module_name}::Identifier.from_hash(value)
                    end

                    # Delegations: the wrapper reads through to the wrapped
                    # standard (the coded SupplementIdentifier shape).
                    def type
                      base&.type
                    end

                    def version
                      base&.version
                    end

                    def year
                      base&.year
                    end

                    def month
                      base&.month
                    end

                    def is_edition
                      base&.is_edition
                    end

                    # The printed notation: the kind face + the ordinal.
                    def supplement_notation
                      "\#{self.class.face}\#{number}"
                    end

                    # The MR slug's supplement suffix: the shared MrString
                    # recurses into base and appends this (the coded
                    # mr_supplement_suffix rule).
                    def mr_supplement_suffix
                      [supplement_notation.to_s.downcase, number].compact.join(".")
                    end
                  end
                end
              end
            end
          RUBY
        end

        # Trim the trailing newline variance: heredoc bodies end with a
        # newline; files end with exactly one.
        def body(text)
          text.sub(/\A\n+/, "").sub(/\n*\z/, "\n")
        end

        # The canonical render face as a Ruby expression over the
        # identifier's fields: literals + interpolation, with optional
        # segments as PRESENCE GUARDS — an optional renders its face iff
        # every field inside captured (the same semantics the compiler's
        # own template verifier applies, so the emitted renderer and the
        # verified examples cannot disagree).
        def render_expression
          sequence = definition.templates[:canonical].sequences.first
          parts = sequence.map { |item| render_item_source(item) }
          "\"#{parts.join}\""
        end

        def render_item_source(item)
          case item
          when Template::Lit
            item.text.gsub("\\\\") { "\\\\\\" }.gsub('"') { '\\"' }.gsub('#{') { '\\#{' }
          when Template::Field
            "\#{#{field_reader(item.name)}}"
          when Template::Opt
            sequences = item.inner.sequences
            if sequences.size > 1
              raise Error,
                    "a render face cannot alternate inside an optional segment " \
                    "— an alternation is an accept surface, not a render decision"
            end
            body = sequences.first.map { |i| render_item_source(i) }.join
            guards = Template.direct_fields(item).map { |name| field_guard(name) }.join(" && ")
            "\#{\"#{body}\" if #{guards}}"
          else
            raise Error, "render face may only carry literals and fields"
          end
        end

        # The reader a render face uses for a field: the plain attribute,
        # or the calendar component's field under the date binding.
        def field_reader(name)
          if date_binding && date_binding.fields.include?(name)
            "@id.date.#{name}"
          else
            "@id.#{name}"
          end
        end

        def field_guard(name)
          if date_binding && date_binding.fields.include?(name)
            "@id.date&.#{name}"
          else
            "@id.#{name}"
          end
        end

        # The canonical face as the wrapper renderer's interpolation over
        # the field view: literals + `f[:name]` reads, optionals as
        # presence guards, alternated optionals as the first alternative
        # whose direct fields captured — the compiler's own render
        # semantics (Template.render_sequence) one-to-one.
        def wrapper_render_expression
          sequence = definition.templates[:canonical].sequences.first
          sequence.map { |item| view_item_source(item) }.join
        end

        def view_item_source(item)
          case item
          when Template::Lit
            item.text.gsub("\\\\") { "\\\\\\" }.gsub('"') { '\\"' }.gsub('#{') { '\\#{' }
          when Template::Field
            "\#{f[:#{item.name}]}"
          when Template::Opt
            alternatives = item.inner.sequences
            faces = alternatives.map { |seq| view_sequence_source(seq) }
            guards = alternatives.map do |seq|
              seq.filter_map do |i|
                if Template::Field === i
                  "f[:#{i.name}]"
                end
              end
            end
            if faces.size == 1
              body = faces.first
              guard = guards.first.any? ? guards.first.join(" && ") : "true"
              "\#{(\"#{body}\") if #{guard}}"
            else
              branches = faces.each_with_index.map do |face_body, i|
                guard = guards[i].any? ? guards[i].join(" && ") : "true"
                "#{i.zero? ? 'if' : 'elsif'} #{guard}; \"#{face_body}\""
              end
              "\#{#{branches.join(' ')}; end}"
            end
          else
            raise Error, "render face may only carry literals and fields"
          end
        end

        def view_sequence_source(sequence)
          sequence.map { |item| view_item_source(item) }.join
        end

        def render_item_source(item)
          case item
          when Template::Lit
            item.text.gsub("\\\\") { "\\\\\\" }.gsub('"') { '\\"' }.gsub('#{') { '\\#{' }
          when Template::Field
            "\#{#{field_reader(item.name)}}"
          when Template::Opt
            sequences = item.inner.sequences
            if sequences.size > 1
              raise Error,
                    "a render face cannot alternate inside an optional segment " \
                    "— an alternation is an accept surface, not a render decision"
            end
            body = sequences.first.map { |i| render_item_source(i) }.join
            guards = Template.direct_fields(item).map { |name| field_guard(name) }.join(" && ")
            "\#{\"#{body}\" if #{guards}}"
          else
            raise Error, "render face may only carry literals and fields"
          end
        end

        # The reader a render face uses for a field: the plain attribute,
        # or the calendar component's field under the date binding.
        def field_reader(name)
          if date_binding && date_binding.fields.include?(name)
            "@id.date.#{name}"
          else
            "@id.#{name}"
          end
        end

        def field_guard(name)
          if date_binding && date_binding.fields.include?(name)
            "@id.date&.#{name}"
          else
            "@id.#{name}"
          end
        end

        # The core declaration as the runtime schema reads it: bare paths
        # for string-kind cores (the legacy emission, byte-stable), and
        # `[path, :kind]` pairs once an int-kind core is declared (the
        # coded schemas' supplement rows: `core: [["number", :int]]`).
        def core_literal(core)
          specs = core.map do |(path, kind)|
            kind == "string" ? path.inspect : "[#{path.inspect}, :#{kind}]"
          end
          "[" + specs.join(", ") + "]"
        end

        def ruby_array(array)
          "[" + array.map(&:inspect).join(", ") + "]"
        end

        # "resource" -> "Resource" (snake_case to constant, no ActiveSupport).
        def camelize(snake)
          snake.split("_").map(&:capitalize).join
        end

        def __dir_placeholder__
          "\#{__dir__}"
        end
      end
    end
  end
end
