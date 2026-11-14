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
      # v1 emits single-type schemes (one `types:` entry). Issue #121 adds
      # the scheme-canonical mode: a definition using the six
      # declared-emission features (multi-type, draft stages, cen wrapper
      # shapes, the adopted-base dispatch, publisher-type defaults, fused
      # URN segments) emits the coded flavor's own class shape — typed
      # leaves over a shared base, synthesized supplement wrappers, the
      # consolidated bundle and the fragment wrapper, serialization through
      # the shared ::Pubid::Identifier tables (flat scalars, the stage
      # compaction hook) so to_hash is byte-identical with the coded
      # flavor.
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
          raise Error, "v1 emits single-type schemes" if definition.types.size > 1 && !scheme_mode?
        end

        # The issue-#121 scheme-canonical mode: any of the six features on.
        def scheme_mode?
          definition.stages.any? || !definition.adopted.nil? ||
            definition.types.size > 1 ||
            definition.supplements&.consolidated || definition.supplements&.fragment
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
          return scheme_emit_to(dir) if scheme_mode?

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

        # The scheme-canonical emission (issue #121): the coded flavor's
        # class shape. The shared base carries the flat-scalar tables and
        # the stage compaction hook; every declared type is a leaf over it
        # (with its declared publisher default); the supplement wrappers,
        # the consolidated bundle and the fragment are synthesized; the
        # adopted dispatch calls the vendored hook class.
        def scheme_emit_to(dir)
          files = {
            "#{key}.rb" => scheme_module_file,
            "#{key}/identifier.rb" => scheme_identifier_file,
            "#{key}/builder.rb" => scheme_builder_file,
            "#{key}/parser.rb" => parser_file,
            "#{key}/renderer.rb" => scheme_renderer_file,
            "#{key}/urn_generator.rb" => scheme_urn_generator_file,
            "#{key}/pubid_urn_schema.rb" => scheme_urn_schema_file,
            "#{key}/identifiers.rb" => scheme_identifiers_file,
          }
          definition.types.each do |type|
            files["#{key}/identifiers/#{type.name}.rb"] = scheme_type_file(type)
          end
          if definition.supplements
            definition.supplements.wrappers.each do |wrapper|
              files["#{key}/identifiers/#{wrapper.name}.rb"] = scheme_wrapper_file(wrapper)
            end
            files["#{key}/identifiers/supplement.rb"] = scheme_supplement_file
            if definition.supplements.consolidated
              files["#{key}/identifiers/consolidated_identifier.rb"] =
                scheme_consolidated_file
            end
            if definition.supplements.fragment
              files["#{key}/identifiers/fragment.rb"] = scheme_fragment_file
            end
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
          when Definition::UrnPubGroup
            lower = segment.lower ? ".downcase" : ""
            [
              "group = [@identifier.publisher&.respond_to?(:body) ? @identifier.publisher.body : @identifier.publisher,",
              "        *Array(@identifier.copublishers).map { |p| p.respond_to?(:body) ? p.body : p }].compact.map(&:to_s)",
              "        segments << group.map(&:#{'downcase'}).join(#{segment.glue.inspect}) unless group.empty?",
            ].join("\n        ").sub(".map(&:downcase)", segment.lower ? ".map(&:downcase)" : "")
          when Definition::UrnAdoptedMr
            [
              "adopted = @identifier.respond_to?(:adopted) ? @identifier.adopted : nil",
              "        mr = adopted&.to_mr_string",
              "        segments << mr.tr(\"._\", \"::\") unless mr.nil? || mr.empty?",
            ].join("\n        ")
          when Definition::UrnStageCode
            [
              "stage = @identifier.typed_stage",
              "        code = stage&.stage_code",
              "        segments << #{segment.marker.inspect} + code.to_s if code && code.to_s != \"published\"",
            ].join("\n        ")
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
          root = if scheme_mode?
            "@identifier"
          else
            wrapper_mode? ? "subject" : "@identifier"
          end
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

        # === The issue-#121 scheme-canonical emission =====================

        def scheme_module_file
          autoloads = []
          if definition.adopted
            autoloads << "    # The adopted-base dispatch hook (the §4 coded escape hatch):"
            autoloads << "    # vendored beside the generated classes — a missing hook file"
            autoloads << "    # fails loudly on the first adoption, never silently."
            autoloads << "    autoload :AdoptedBase, \"#{__dir_placeholder__}/#{key}/adopted_base\""
            autoloads << ""
          end
          body("#{header}#{scheme_module_body(autoloads)}")
        end

        def scheme_module_body(autoloads)
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
            #{autoloads.join("\n").chomp}
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

        # The default type: the declared type with no selection tokens that
        # is not an adopted wrapper (the hook builds those).
        def default_type
          @default_type ||= begin
            defaults = definition.types.select { |t| Array(t.tokens).empty? && !t.adopted }
            raise Error, "exactly one token-free non-adopted type is required " \
                         "(the default class)" if defaults.size != 1

            defaults.first
          end
        end

        def type_by_name(name)
          definition.types.find { |t| t.name == name } or raise Error, "unknown type #{name.inspect}"
        end

        # The shared base: the version column, the flat-scalar tables, the
        # stage compaction hook (the coded CenCenelec::Identifier shape),
        # the draft-aware mr_type, the publisher-prefix cut and the parse
        # funnel.
        def scheme_identifier_file
          stages = definition.stages
          stage_table = stages.map do |stage|
            "        #{stage.name.inspect} => { stage_code: :#{stage.urn} },"
          end.join("\n")
          body(<<~RUBY)
            module Pubid
              module #{module_name}
                # The shared base of every concrete #{module_name} class. The
                # serialization is the shared ::Pubid::Identifier's (the coded
                # flavor's own shape): flat publisher/copublishers scalars, the
                # date flattened to its fields, and the draft stage compacted
                # to its code by the class hooks below.
                class Identifier < ::Pubid::Identifier
                  # The ETSI-style version suffix ("EN 302 326-2 V2.2.1").
                  attribute :version, :string

                  # A published document holds no type, stage or typed stage, so
                  # a nil one means "published", not "any stage": `EN 1325` is
                  # not `prEN 1325`. The three components repeat one entry of
                  # the stage registry, so they move together.
                  subset_strict :type, :stage, :typed_stage

                  # The bodies that print as a publisher prefix. The publisher
                  # attribute also holds the deliverable types that ARE the
                  # designation ("CR 954"); those stay under
                  # with_publisher: false, as `BS` does for BSI.
                  PUBLISHER_PREFIXES = #{ruby_array(definition.organization.prefixes.map { |p| p.sub(%r{/\\z}, "") }.uniq)}.freeze

                  def publisher_prefixes
                    super.select do |prefix|
                      PUBLISHER_PREFIXES.include?(prefix.split("/").first)
                    end
                  end

                  # The publisher serializes as a bare string, the copublishers
                  # as a list of strings (the coded flavor's flat-scalar table).
                  def self.flat_scalar_components
                    super.merge(publisher: "publisher", copublishers: "copublishers")
                  end

                  def self.flat_scalar_fields
                    super.merge(publisher: :body, copublishers: :body)
                  end

                  # The declared draft stages: the serialized code is the key,
                  # the official-URN code the declared `urn:` value.
                  STAGE_CODES = {
            #{stage_table}
                  }.freeze

                  # A draft stage serializes as its typed-stage code
                  # ("stage" => "pren"); #inflate_scalar_components rebuilds
                  # the three components from it (the coded compact-hash shape).
                  def self.compact_hash(model, hash)
                    stage = model.typed_stage
                    return unless stage && hash.key?("typed_stage")
                    return unless model.type == stage.to_type &&
                                  model.stage == stage.to_stage

                    hash.delete("type")
                    hash.delete("typed_stage")
                    hash["stage"] = stage.code.to_s
                  end

                  # Reads the short stage form back; the nested form still
                  # reads as before.
                  def self.inflate_scalar_components(data)
                    data = super
                    return data unless data.is_a?(::Hash) && component_attribute?(:stage)

                    key = data.key?("stage") ? "stage" : :stage
                    value = data[key]
                    return data unless value.is_a?(::String) || value.is_a?(::Symbol)

                    stage = locate_stage_by_code(value)
                    return data unless stage

                    data = data.dup
                    data.delete(key)
                    data["type"] = stage.to_type.to_hash
                    data["stage"] = stage.to_stage.to_hash
                    data["typed_stage"] = stage.to_hash
                    data
                  end

                  # The stage entry by serialized code, or nil.
                  def self.locate_stage_by_code(code)
                    Builder.stage_by_code(code.to_s)
                  end

                  # The draft stage's own code is the MR type segment
                  # ("en.pren.10160"); a published identifier has no typed
                  # stage, so the shared hook answers nil.
                  def mr_type
                    stage = typed_stage
                    return super unless stage && stage.stage_code.to_s != "published"

                    stage.code.to_s.downcase
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

                  private

                  # "amd.1.2005" from ("amd", "1", 2005). A nil or blank
                  # segment is left out.
                  def mr_join_segments(*segments)
                    segments.map(&:to_s).reject(&:empty?).join(".").downcase
                  end
                end
              end
            end
          RUBY
        end

        # The builder: type dispatch over the declared tokens, the column
        # assignment (the coded cast's shape), the supplement fold (the
        # slash run standalone, the plus run consolidated), the fragment
        # wrapper, and the two adopted-dispatch call points.
        def scheme_builder_file
          token_map = definition.types.flat_map do |type|
            Array(type.tokens).map { |token| "          #{token.inspect} => \"#{camelize(type.name)}\"," }
          end
          # The declared draft stages: the serialized code is the key, the
          # declared URN code is the harmonized stage code, and the
          # stage's type is the scheme's token-free default class.
          stage_rows = definition.stages.map do |stage|
            "        \"#{stage.name}\" => { code: :#{stage.name}, " \
              "stage_code: :#{stage.urn}, type_code: :#{default_type.key}, " \
              "abbr: #{ruby_array(stage.tokens)} },"
          end.join("\n")
          stage_map = definition.stages.flat_map do |stage|
            stage.tokens.map { |token| "          #{token.inspect} => #{stage.name.inspect}," }
          end.join("\n")
          supplements = definition.supplements
          adopted = !definition.adopted.nil?

          lines = []
          lines << "module Pubid"
          lines << "  module #{module_name}"
          lines << "    class Builder"
          lines << "      # The type each declared token selects (feature 1); the"
          lines << "      # token-free type is the default class."
          lines << "      TYPE_TOKENS = {"
          lines << token_map.join("\n").chomp
          lines << "      }.freeze"
          lines << ""
          lines << "      DEFAULT_TYPE = \"#{camelize(default_type.name)}\""
          lines << ""
          lines << "      # The declared draft stages (feature 2): code → the"
          lines << "      # typed-stage row the trio builds from."
          lines << "      STAGES = {"
          lines << stage_rows.chomp
          lines << "      }.freeze"
          lines << ""
          lines << "      # The captured spelling → the serialized stage code."
          lines << "      STAGE_MAP = {"
          lines << stage_map.chomp
          lines << "      }.freeze"
          lines << ""
          lines << "      def self.build(parsed_data)"
          lines << "        new.build(parsed_data)"
          lines << "      end"
          lines << ""
          lines << "      def self.stage_by_code(code)"
          lines << "        row = STAGES[code.to_s]"
          lines << "        return nil unless row"
          lines << ""
          lines << "        ::Pubid::Components::TypedStage.new("
          lines << "          code: row[:code], stage_code: row[:stage_code],"
          lines << "          type_code: row[:type_code], abbr: row[:abbr],"
          lines << "        )"
          lines << "      end"
          lines << ""
          lines << "      def build(data)"
          lines << "        base = build_base_document(data)"
          lines << "        wrapped = wrap_supplements(base, data)"
          if supplements&.fragment
            lines << "        wrap_fragment(wrapped, data)"
          else
            lines << "        wrapped"
          end
          lines << "      end"
          lines << ""
          lines << "      # The document the supplements apply to. The adopted-base"
          lines << "      # dispatch (feature 4) calls the vendored hook at two explicit"
          lines << "      # points: the captured adopted run, and the hook's own implicit"
          lines << "      # probe — never implicitly."
          lines << "      def build_base_document(data)"
          if adopted
            lines << "        return AdoptedBase.build(self, data) if data[:#{definition.adopted.field}]"
            lines << ""
            lines << "        implicit = AdoptedBase.implicit(self, data)"
            lines << "        return implicit if implicit"
            lines << ""
          end
          lines << "        identifier = locate_identifier_klass(data).new"
          lines << "        assign_attributes(identifier, data)"
          lines << "        identifier"
          lines << "      end"
          lines << ""
          lines << "      # The class each reference selects: the type-position token"
          lines << "      # first, then the publisher-position token (the publisher-type"
          lines << "      # faces CR/CWA/…), then the token-free default class."
          lines << "      def locate_identifier_klass(data)"
          lines << "        token = data[:guide] || data[:type]"
          lines << "        token ||= data[:publisher] if TYPE_TOKENS.key?(data[:publisher].to_s)"
          lines << "        name = token ? TYPE_TOKENS.fetch(token.to_s, DEFAULT_TYPE) : DEFAULT_TYPE"
          lines << "        Identifiers.const_get(name)"
          lines << "      end"
          lines << ""
          lines << "      # The columns, as the coded builder's cast writes them."
          lines << "      def assign_attributes(identifier, data)"
          if date_binding
            lines << "        if data[:#{date_binding.fields.first}]"
            lines << "          identifier.date = ::Pubid::Components::Date.new("
            lines << "            #{date_binding.fields.map { |f| "#{f}: data[:#{f}]&.to_s" }.join(', ')},"
            lines << "          )"
            lines << "        end"
          end
          lines << "        identifier.number = data[:number]&.to_s"
          lines << "        identifier.part = data[:part]&.to_s"
          lines << "        identifier.version = present_string(data[:version])"
          lines << "        if data[:publisher]"
          lines << "          identifier.publisher = ::Pubid::Components::Publisher.new(body: data[:publisher].to_s)"
          lines << "        end"
          lines << "        copubs = Array(data[:copublishers]).map do |row|"
          lines << "          value = row[:copublisher] || row[\"copublisher\"]"
          lines << "          ::Pubid::Components::Publisher.new(body: unwrap(value).to_s)"
          lines << "        end"
          lines << "        identifier.copublishers = copubs unless copubs.empty?"
          lines << "        type_token = data[:guide] || data[:type]"
          lines << "        identifier.type = ::Pubid::Components::Type.new(abbr: type_token.to_s) if type_token"
          lines << "        captured = data[:stage]"
          lines << "        return unless captured"
          lines << ""
          lines << "        typed_stage = Builder.stage_by_code(STAGE_MAP.fetch(captured.to_s))"
          lines << "        identifier.typed_stage = typed_stage"
          lines << "        identifier.type = typed_stage.to_type"
          lines << "        identifier.stage = typed_stage.to_stage"
          lines << "      end"
          lines << ""
          lines << "      # A capture the grammar bound as an empty string stores as nil:"
          lines << "      # to_hash drops the empty string, so from_hash would give nil and"
          lines << "      # the two identifiers would not be ==."
          lines << "      def present_string(value)"
          lines << "        str = unwrap(value)&.to_s"
          lines << "        str unless str.nil? || str.empty?"
          lines << "      end"
          lines << ""
          lines << "      # The run's internal captures bind only through the item row, so"
          lines << "      # unbound ones arrive as raw leaves — a Parsanol::Slice or a"
          lines << "      # {value:, offset: ...} span. Unwrap the captured value."
          lines << "      def unwrap(capture)"
          lines << "        return capture.content if capture.is_a?(Parsanol::Slice)"
          lines << "        return capture[:value] if capture.is_a?(Hash) && capture.key?(:value)"
          lines << ""
          lines << "        capture"
          lines << "      end"
          lines.concat(scheme_supplement_fold_lines(supplements)) if supplements
          lines << "    end"
          lines << "  end"
          lines << ""
          lines << "  Pubid::#{module_name}::Builder.prepend(Pubid::Builder::AllPartsWrap)"
          lines << "end"
          body(lines.join("\n") << "\n")
        end

        # The supplement fold: the plus run synthesizes the declared
        # consolidated bundle (the base first, members baseless); the
        # slash run makes the outermost-last standalone chain.
        def scheme_supplement_fold_lines(supplements)
          wrapper_map = supplements.wrappers.map do |wrapper|
            "        \"#{wrapper.face}\" => Identifiers::#{camelize(wrapper.name)},"
          end
          integer = supplements.number_kind == "integer"
          lines = [
            "",
            "      # The wrapper classes by kind face: the run's dispatch.",
            "      SUPPLEMENT_WRAPPERS = {",
            *wrapper_map,
            "      }.freeze",
            "",
            "      def wrap_supplements(base, data)",
            "        rows = Array(data[:supplements])",
            "        return base if rows.empty?",
            "",
            "        items = rows.map do |row|",
            "          inner = row[:supplement] || row[\"supplement\"] || {}",
            "          inner = inner.values.first if inner.values.all?(Hash)",
            "          inner",
            "        end",
            "        if items.any? { |item| item[:supplements_plus] || item[\"supplements_plus\"] }",
            "          members = items.map { |item| supplement_from(item) }",
            "          Identifiers::ConsolidatedIdentifier.new(identifiers: [base] + members)",
            "        else",
            "          supplement_from(items.first, base: base)",
            "        end",
            "      end",
            "",
            "      def supplement_from(item, base: nil)",
            "        kind = unwrap(item[:supplement_kind] || item[\"supplement_kind\"])",
            "        number = unwrap(item[:supplement_number] || item[\"supplement_number\"])",
            "        attrs = {}",
            "        attrs[:base] = base if base",
            integer ? "        attrs[:number] = number.to_i" : "        attrs[:number] = present_string(number)",
          ]
          supplements.date.each do |column|
            capture = "supplements_#{column}"
            lines << "        attrs[:#{column}] = present_string(unwrap(item[:#{capture}] || item[\"#{capture}\"]))"
          end
          lines.concat([
            "        SUPPLEMENT_WRAPPERS.fetch(kind.to_s).new(**attrs)",
            "      end",
          ])
          if supplements.fragment
            lines.concat([
              "",
              "      def wrap_fragment(identifier, data)",
              "        return identifier unless data[:#{supplements.fragment.field}]",
              "",
              "        Identifiers::Fragment.new(",
              "          number: unwrap(data[:#{supplements.fragment.field}]).to_s, base: identifier,",
              "        )",
              "      end",
            ])
          end
          lines
        end

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

# The canonical render face as the emitted renderer's interpolation
        # over the field view, with the required head group as the face
        # selection the compiler's verifier applies.
        def scheme_render_expression
          sequence = definition.templates[:canonical].sequences.first
          sequence.map { |item| scheme_view_item_source(item) }.join
        end

        def scheme_view_item_source(item)
          case item
          when Template::Lit
            item.text.gsub("\\\\") { "\\\\\\" }.gsub('"') { '\\"' }.gsub('#{') { '\\#{' }
          when Template::Field
            "\#{f[:#{item.name}]}"
          when Template::Opt, Template::Group
            alternatives = item.inner.sequences
            faces = alternatives.map { |seq| scheme_view_sequence_source(seq) }
            guards = alternatives.map do |seq|
              seq.filter_map { |i| "f[:#{i.name}]" if Template::Field === i }
            end
            required = Template::Group === item
            if faces.size == 1
              body = faces.first
              guard = guards.first.any? ? guards.first.join(" && ") : "true"
              if required
                "\#{(\"#{body}\") if #{guard} || true}"
              else
                "\#{(\"#{body}\") if #{guard}}"
              end
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

        def scheme_view_sequence_source(sequence)
          sequence.map { |item| scheme_view_item_source(item) }.join
        end

        # The field view lines: the identifier's columns, with the declared
        # value maps applied (the stored stage code renders as its
        # spelling) and the date binding read through the calendar.
        def scheme_view_lines
          adopted_field = definition.adopted&.field
          fragment_field = definition.supplements&.fragment&.field
          run_name = definition.supplements&.run
          item_names = definition.fields
            .select { |f| f.kind == "list" && f.item }.map(&:item)
          lines = []
          definition.fields.each do |field|
            next if item_names.include?(field.name)
            next if field.builder_only && field.name != adopted_field &&
                    field.name != fragment_field && field.name != run_name

            if field.name == run_name
              next # the run is composed by the walker; set after the view
            elsif field.name == definition.adopted&.field
              lines << "          #{field.name}: root.respond_to?(:adopted) ? root.adopted : nil,"
            elsif field.name == definition.supplements&.fragment&.field
              next # the fragment face is composed by the walker
            elsif field.name == "stage"
              lines << "          #{field.name}: FACE_stage.fetch(root.typed_stage&.code&.to_s, root.typed_stage&.code&.to_s),"
            elsif token_position_field?(field)
              tokens = field_pattern_tokens(field)
              lines << "          #{field.name}: (v = root.type&.abbr) && #{ruby_array(tokens)}.include?(v) ? v : nil,"
            elsif field.kind == "list"
              glue = field.render&.glue || "-"
              lines << "          #{field.name}: root.#{field.name}.to_a.any? ? root.#{field.name}.map { |item| \"#{glue}\#{item.respond_to?(:body) ? item.body : item}\" }.join : nil,"
            elsif date_binding&.fields&.include?(field.name)
              lines << "          #{field.name}: root.date&.#{field.name},"
            elsif field.render.is_a?(Hash)
              # A mapped column: the stored value renders through the
              # declared face map ("pren" renders "prEN").
              lines << "          #{field.name}: FACE_#{field.name}.fetch(root.#{field.name}, root.#{field.name}),"
            elsif field.name == "publisher"
              lines << "          #{field.name}: root.publisher&.respond_to?(:body) ? root.publisher.body : root.publisher,"
            else
              lines << "          #{field.name}: root.#{field.name},"
            end
          end
          lines
        end

        # The fields the face reads from the type component's abbreviation
        # (the type/guide dispatch captures — the classes carry the token
        # as their type, never as a column).
        def token_position_field?(field)
          %w[type guide].include?(field.name)
        end

        # The literal spellings a field's pattern alternates over (the
        # quoted tokens of the type/guide patterns).
        def field_pattern_tokens(field)
          field.pattern.scan(/"([^"]+)"/).flatten
        end

        # The face maps a mapped column carries, emitted as constants the
        # renderer reads ("pren" → "prEN").
        def scheme_face_map_lines
          definition.fields.select { |f| f.render.is_a?(Hash) }.map do |field|
            rows = field.render.map { |k, v| "        #{k.inspect} => #{v.inspect}," }.join("\n")
            ["      FACE_#{field.name} = {", rows, "      }.freeze"].join("\n")
          end
        end

        def scheme_renderer_file
          lines = []
          lines << "module Pubid"
          lines << "  module #{module_name}"
          lines << "    # Human renderer, generated from the canonical template."
          lines << "    class Renderer < ::Pubid::Renderers::Base"
          scheme_face_map_lines.each { |block| lines << block }
          lines << "      def render(**_opts)"
          lines << "        f = render_fields(@id)"
          lines << "        \"#{scheme_render_expression}\""
          lines << "      end"
          lines << ""
          lines << "      private"
          lines << ""
          lines << "      # The field view: a wrapper reads through to the wrapped"
          lines << "      # standard and composes the printed run once — the standalone"
          lines << "      # chain behind its slash, the consolidated members behind the"
          lines << "      # plus — and the fragment face follows its base."
          lines << "      def render_fields(id)"
          lines << "        root = id"
          lines << "        run = +\"\""
          lines << "        members = nil"
          lines << "        frag = nil"
          if definition.supplements&.fragment
            lines << "        if root.is_a?(Identifiers::Fragment)"
            lines << "          frag = root.number"
            lines << "          root = root.base"
            lines << "        end"
          end
          if definition.supplements&.consolidated
            lines << "        if root.is_a?(Identifiers::ConsolidatedIdentifier)"
            lines << "          base, *consolidated = root.identifiers"
            lines << "          members = consolidated"
            lines << "          root = base"
            lines << "        end"
          end
          if definition.supplements
            lines << "        while root.is_a?(Identifiers::Supplement)"
            lines << "          run.prepend(\"/\#{root.supplement_notation}\")"
            lines << "          root = root.base"
            lines << "        end"
            if definition.supplements.consolidated
              lines << "        members&.each do |member|"
              lines << "          run << \"+\#{member.supplement_notation}\""
              lines << "        end"
            end
          end
          lines << "        view = {"
          lines.concat(scheme_view_lines)
          lines << "        }"
          run_name = definition.supplements&.run
          if run_name
            lines << "        view[:#{run_name}] = run.empty? ? nil : run"
          end
          if fragment_field = definition.supplements&.fragment&.field
            lines << "        view[:#{fragment_field}] = frag"
          end
          lines << "        view"
          lines << "      end"
          lines << "    end"
          lines << "  end"
          lines << "end"
          body(lines.join("\n") << "\n")
        end

        def scheme_urn_generator_file
          segments = definition.urn.official || []
          wrapper_urns = definition.supplements&.wrappers&.select(&:urn)
          lines = []
          lines << "module Pubid"
          lines << "  module #{module_name}"
          lines << "    # The official URN generator: the scheme's declared namespace"
          lines << "    # (#{definition.urn.namespace.inspect}) and the ordered fused segments"
          lines << "    # (feature 6) — the publisher group, the adopted document's"
          lines << "    # fused MR string, the composed code, the year, the draft"
          lines << "    # stage. A wrapper reads through to its subject and appends"
          lines << "    # its declared chain; the consolidated bundle marks each"
          lines << "    # member with the plus marker."
          lines << "    class UrnGenerator < ::Pubid::UrnGenerator::Base"
          lines << "      def urn_namespace"
          lines << "        #{definition.urn.namespace.inspect}"
          lines << "      end"
          lines << ""
          lines << "      def generate"
          lines << "        id = @identifier"
          lines << "        members = nil"
          lines << "        frag_segments = []"
          lines << "        wrapper = []"
          if definition.supplements&.fragment
            lines << "        if id.is_a?(Identifiers::Fragment)"
            lines << "          frag_segments = wrapper_segments(id)"
            lines << "          id = id.base"
            lines << "        end"
          end
          if definition.supplements&.consolidated
            lines << "        if id.is_a?(Identifiers::ConsolidatedIdentifier)"
            lines << "          base, *consolidated = id.identifiers"
            lines << "          members = consolidated"
            lines << "          id = base"
            lines << "        end"
          end
          if definition.supplements
            lines << "        while id.is_a?(Identifiers::Supplement)"
            lines << "          wrapper.prepend(*wrapper_segments(id))"
            lines << "          id = id.base"
            lines << "        end"
          end
          lines << "        @identifier = id"
          lines << "        parts = [\"urn\", urn_namespace]"
          lines << "        parts.concat(official_segments)"
          lines << "        parts.concat(wrapper)"
          if definition.supplements&.consolidated
            lines << "        members&.each do |member|"
            lines << "          parts << \"plus\""
            lines << "          parts.concat(wrapper_segments(member))"
            lines << "        end"
          end
          lines << "        parts.concat(frag_segments)"
          lines << "        parts.join(\":\")"
          lines << "      end"
          lines << ""
          lines << "      private"
          lines << ""
          lines << "      def official_segments"
          lines << "        segments = []"
          lines << "        " + segments.map { |segment| urn_segment_source(segment) }.join("\n        ")
          lines << "        segments"
          lines << "      end"
          lines << ""
          lines << "      # One wrapper's declared URN chain: the kind word, then the"
          lines << "      # wrapper's columns (the ordinal, the year-month date)."
          lines << "      def wrapper_segments(id)"
          lines << "        segments = case id"
          wrapper_urns&.each do |wrapper|
            lines << "        when Identifiers::#{camelize(wrapper.name)}"
            lines << "          #{wrapper_segment_source(wrapper.urn)}"
          end
          if (fragment = definition.supplements&.fragment)&.urn
            lines << "        when Identifiers::Fragment"
            lines << "          #{wrapper_segment_source(fragment.urn)}"
          end
          lines << "        else"
          lines << "          []"
          lines << "        end"
          lines << "        segments.map(&:to_s).reject(&:empty?)"
          lines << "      end"
          lines << "    end"
          lines << "  end"
          lines << "end"
          body(lines.join("\n") << "\n")
        end

        # The wrapper's chain segments: lowercase words are literals, the
        # column refs read the wrapper (`number`, a date column, or the
        # composed `date`).
        def wrapper_segment_source(segments)
          parts = segments.map do |segment|
            case segment
            when "number" then "id.number"
            when "date" then "(id.respond_to?(:supplement_date) ? id.supplement_date : [id.year, id.month].compact.join(\"-\") )"
            when "year" then "id.year"
            when "month" then "id.month"
            else "\"#{segment}\""
            end
          end
          "[#{parts.join(', ')}]"
        end

        def scheme_urn_schema_file
          atoms = definition.urn.atoms.map do |atom|
            kind = atom.kind == "string" ? "" : ", kind: :#{atom.kind}"
            "        atom #{atom.path.inspect}, #{atom.prefix.inspect}#{kind}"
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

        def scheme_identifiers_file
          rows = definition.types.map { |type| camelize(type.name) }
          if definition.supplements
            rows += ["Supplement"] +
              definition.supplements.wrappers.map { |w| camelize(w.name) }
            rows << "ConsolidatedIdentifier" if definition.supplements.consolidated
            rows << "Fragment" if definition.supplements.fragment
          end
          rows_source = rows.map do |name|
            "          autoload :#{name}, \"#{__dir_placeholder__}/identifiers/#{snake_file(name)}\""
          end.join("\n")
          body(<<~RUBY)
            module Pubid
              module #{module_name}
                module Identifiers
              #{rows_source.chomp}
                end
              end
            end
          RUBY
        end

        # The autoload file name: the camelized constant back to its
        # snake_case file ("ConsolidatedIdentifier" → "consolidated_identifier").
        def snake_file(name)
          name.gsub(/([A-Z\d]+)([A-Z][a-z])/, '\1_\2')
            .gsub(/([a-z\d])([A-Z])/, '\1_\2')
            .downcase
        end

        # One concrete type class: the typed stages (the declared draft
        # stages for the default type, the declared type stage else), the
        # publisher default (feature 5), the scheme-canonical wire tag,
        # and — for the adopted wrapper types (feature 4) — the adopted
        # attribute and the MR/URN hooks the adopted identity reads.
        def scheme_type_file(type)
          stages = if type == default_type
            rows = []
            if (published = type.stage)
              rows << [
                "          ::Pubid::Components::TypedStage.new(",
                "            code: :#{published.code}, stage_code: :#{published.stage_code},",
                "            type_code: :#{type.key}, abbr: #{ruby_array(published.abbr)},",
                "            name: #{type.title.inspect}, harmonized_stages: [],",
                "          ),",
              ]
            end
            definition.stages.each do |stage|
              rows << [
                "          ::Pubid::Components::TypedStage.new(",
                "            code: :#{stage.name}, stage_code: :#{stage.urn},",
                "            type_code: :#{default_type.key}, abbr: #{ruby_array(stage.tokens)},",
                "            name: #{stage.name.inspect}, harmonized_stages: [],",
                "          ),",
              ]
            end
            rows.flatten
          elsif type.stage
            [
              "          ::Pubid::Components::TypedStage.new(",
              "            code: :#{type.stage.code}, stage_code: :#{type.stage.stage_code},",
              "            type_code: :#{type.key}, abbr: #{ruby_array(type.stage.abbr)},",
              "            name: #{type.title.inspect}, harmonized_stages: [],",
              "          ),",
            ]
          else
            []
          end
          typed_stages = ["          TYPED_STAGES = [", *stages, "          ].freeze"].join("\n")

          lines = []
          lines << "module Pubid"
          lines << "  module #{module_name}"
          lines << "    module Identifiers"
          lines << "      # Concrete #{type.title} identifier type (PFS type `#{type.name}`)."
          lines << "      class #{camelize(type.name)} < Identifier"
          lines << typed_stages
          lines << ""
          lines << "        def self.type"
          lines << "          { key: #{symbol_literal(type.key)}, web: #{symbol_literal(type.web)}, title: #{type.title.inspect}, short: #{type.short.inspect} }"
          lines << "        end"
          lines << ""
          lines << "        # The publisher default (feature 5): the type's own token"
          lines << "        # when the type is its designation, else the scheme default."
          lines << "        def self.default_publisher"
          lines << "          ::Pubid::Components::Publisher.new(body: #{(type.publisher_default || definition.organization.publisher).inspect})"
          lines << "        end"
          lines << ""
          lines << "        attribute :publisher, ::Pubid::Components::Publisher, default: -> { self.class.default_publisher }"
          lines << "        attribute :type, ::Pubid::Components::Type, default: -> { self.class.default_type }"
          lines << ""
          lines << "        def self.default_type"
          lines << "          ::Pubid::Components::Type.new(abbr: type[:short])"
          lines << "        end"
          if adopted_type?(type)
            lines << ""
            lines << "        # The adopted document (feature 4): the whole identity lives"
            lines << "        # on the nested ISO/IEC identifier."
            lines << "        attribute :adopted, ::Pubid::Identifier, polymorphic: true"
            lines << ""
            lines << "        def root"
            lines << "          adopted ? adopted.root : self"
            lines << "        end"
            lines << ""
            lines << "        # MR \"cen.iso.ts.21003-7\": the publisher group fused, then the"
            lines << "        # adopted document's own MR string in place of a number."
            lines << "        def mr_publisher"
            lines << "          mr_join(*([publisher] + Array(copublishers)).compact"
            lines << "            .map { |p| p.to_s.downcase })"
            lines << "        end"
            lines << ""
            lines << "        def mr_number_with_part"
            lines << "          adopted ? adopted.to_mr_string : super"
            lines << "        end"
          end
          lines << ""
          lines << "        # The scheme-canonical wire tag declared in the definition:"
          lines << "        # to_hash stays byte-identical with the scheme's coded"
          lines << "        # flavor, and this flavor's own from_hash routes the tag"
          lines << "        # to this class."
          lines << "        def self.polymorphic_name"
          lines << "          #{type.tag.inspect}"
          lines << "        end"
          lines << "      end"
          lines << "    end"
          lines << "  end"
          lines << "end"
          body(lines.join("\n") << "\n")
        end

        # The types the adopted dispatch builds (feature 4): those the
        # definition declares `adopted: true` — the adoption wrapper class
        # and the ENV switch.
        def adopted_type?(type)
          type.adopted == true
        end

        def scheme_wrapper_file(wrapper)
          body(<<~RUBY)
            module Pubid
              module #{module_name}
                module Identifiers
                  # The synthesized #{wrapper.title} wrapper (PFS supplements
                  # declaration, issue #121 feature 3): the kind face
                  # "#{wrapper.face}" is the run's dispatch token and the
                  # printed notation's face.
                  class #{camelize(wrapper.name)} < Supplement
                    FACE = "#{wrapper.face}".freeze

                    def self.face
                      FACE
                    end

                    def self.polymorphic_name
                      #{wrapper.tag.inspect}
                    end
                    #{wrapper_suffix_source(wrapper).strip.empty? ? '' : wrapper_suffix_source(wrapper)}
                  end
                end
              end
            end
          RUBY
        end

        # The wrapper subclass's MR suffix from its declared segments:
        # lowercase words are literals; the column refs read the wrapper.
        def wrapper_suffix_source(wrapper)
          return "" unless wrapper.mr

          segs = wrapper.mr.map do |segment|
            case segment
            when "number" then "number"
            when "date" then "supplement_date"
            when "year" then "year"
            when "month" then "month"
            else "\"#{segment}\""
            end
          end
          [
            "",
            "        # The MR slug's supplement suffix: the shared MrString",
            "        # recurses into base and appends this.",
            "        def mr_supplement_suffix",
            "          mr_join_segments(#{segs.join(', ')})",
            "        end",
          ].join("\n").gsub(/^/, "                    ")
        end

        # The supplement wrapper base: the base identifier, the ordinal
        # (declared kind), the wrapper-owned year/month columns, and the
        # declared MR suffix segments.
        def scheme_supplement_file
          wrappers = definition.supplements.wrappers
          integer = definition.supplements.number_kind == "integer"
          kind_attr = wrappers.any?(&:number_optional) ? "        attribute :number, :#{integer ? 'integer' : 'string'}" : "        attribute :number, :#{integer ? 'integer' : 'string'}"
          lines = []
          lines << "module Pubid"
          lines << "  module #{module_name}"
          lines << "    module Identifiers"
          lines << "      # The supplement wrapper base: the wrapper owns its ordinal"
          lines << "      # and the base identifier; every delegated attribute reads"
          lines << "      # through (the coded SupplementIdentifier shape)."
          lines << "      class Supplement < ::Pubid::#{module_name}::Identifier"
          lines << "        attribute :base, ::Pubid::#{module_name}::Identifier"
          lines << kind_attr
          definition.supplements.date.each do |column|
            lines << "        attribute :#{column}, :#{integer ? 'integer' : 'string'}"
          end
          lines << ""
          lines << "        def base_document"
          lines << "          base&.base_document || self"
          lines << "        end"
          lines << ""
          lines << "        def drop_supplements"
          lines << "          base || self"
          lines << "        end"
          if definition.supplements.date.include?("year") &&
             definition.supplements.date.include?("month")
            lines << ""
            lines << "        # The wrapper's date: \"2016-11\", \"2003\", or nil."
            lines << "        def supplement_date"
            lines << "          return nil unless year"
            lines << ""
            lines << "          [year, month].compact.reject(&:empty?).join(\"-\")"
            lines << "        end"
          end
          lines << ""
          lines << "        # The printed notation: the kind face, the ordinal (absent"
          lines << "        # for an unnumbered corrigendum) and the declared date tail."
          lines << "        # The bare notation; the renderer's walkers add the"
          lines << "        # standalone slash and the consolidated plus themselves."
          lines << "        def supplement_notation"
          lines << "          \"\#{self.class.face}\#{number}#{notation_date_tail}\""
          lines << "        end"
          lines << ""
          lines << "      end"
          lines << "    end"
          lines << "  end"
          lines << "end"
          body(lines.join("\n") << "\n")
        end

        def notation_date_tail
          tail = +""
          if definition.supplements.date.include?("year")
            tail << '#{year ? ":#{year}" : \'\'}'
          end
          if definition.supplements.date.include?("month")
            tail << '#{month ? "-#{month}" : \'\'}'
          end
          tail
        end

        def scheme_consolidated_file
          consolidated = definition.supplements.consolidated
          body(<<~RUBY)
            module Pubid
              module #{module_name}
                module Identifiers
                  # The consolidated (plus-run) bundle: the base document is
                  # the first member; the supplements carry no base.
                  class ConsolidatedIdentifier < ::Pubid::#{module_name}::Identifier
                    attribute :identifiers, ::Pubid::#{module_name}::Identifier,
                              polymorphic: true, collection: true

                    # The origin document. Members live in `identifiers`, so
                    # walk the first member to its root.
                    def root
                      identifiers&.first&.root || self
                    end

                    def base_document
                      identifiers&.first&.base_document || self
                    end

                    def drop_supplements
                      identifiers&.first || self
                    end

                    # The base document, then each member's own supplement
                    # suffix behind the plus marker — the coded shape.
                    def to_mr_string
                      base, *supplements = identifiers
                      return "" unless base

                      ([base.to_mr_string] +
                        supplements.map { |s| "plus-\#{s.mr_supplement_suffix}" })
                        .join(::Pubid::Renderers::MrString::SEPARATOR_SUPPLEMENT)
                    end

                    def self.polymorphic_name
                      #{consolidated.tag.inspect}
                    end
                  end
                end
              end
            end
          RUBY
        end

        def scheme_fragment_file
          fragment = definition.supplements.fragment
          body(<<~RUBY)
            module Pubid
              module #{module_name}
                module Identifiers
                  # The fragment wrapper: a fragment of the amendment it
                  # wraps; the fragment ordinal is its own `number`.
                  class Fragment < ::Pubid::#{module_name}::Identifier
                    attribute :base, ::Pubid::#{module_name}::Identifier
                    attribute :number, :string

                    def base_document
                      base&.base_document || self
                    end

                    def drop_supplements
                      base || self
                    end

                    def mr_supplement_suffix
                      mr_join_segments("frag", number)
                    end

                    def self.polymorphic_name
                      #{fragment.tag.inspect}
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
      end
    end
  end
end
