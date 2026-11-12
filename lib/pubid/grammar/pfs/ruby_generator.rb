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

        def builder_file
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

        # One urn.official segment as the generator's Ruby lines. A field
        # under the date binding reads the calendar component (nil-safe),
        # a plain field reads the attribute.
        def urn_segment_source(segment)
          case segment
          when Definition::UrnField
            "segments << #{urn_field_reader(segment.name)} if #{urn_field_guard(segment.name)}"
          when Definition::UrnDate
            date = segment.fields.map { |f| urn_field_reader(f) }.join(", ")
            "date = [#{date}].compact\n" \
              "        segments << date.join(\"-\") unless date.empty?"
          end
        end

        def urn_field_reader(name)
          if date_binding && date_binding.fields.include?(name)
            "@identifier.date&.#{name}"
          else
            "@identifier.#{name}"
          end
        end

        def urn_field_guard(name)
          if date_binding && date_binding.fields.include?(name)
            "@identifier.date&.#{name}"
          else
            "@identifier.#{name}"
          end
        end

        def urn_schema_file
          atoms = definition.urn.atoms.map do |atom|
            "        atom #{atom.path.inspect}, #{atom.prefix.inspect}"
          end.join("\n")
          types = definition.urn.types.map do |type|
            # the schema reads string paths (it splits them on ".")
            "        type #{type.type.inspect}, #{type.token.inspect}, core: #{ruby_array(type.core)}"
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
