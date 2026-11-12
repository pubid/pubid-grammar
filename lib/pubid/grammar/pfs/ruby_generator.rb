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
          "#{header}#{<<~RUBY}"
            require "pubid"

            module Pubid
              # #{definition.title || definition.scheme} flavor, compiled from its PFS definition
              # (pubid/pubid#706). A compiled flavor is a peer of the coded
              # flavors: same registry, same input guards, same error
              # namespace, same URN contracts.
              module #{module_name}
                extend Pubid::PrefixesSupport

                PREFIXES = #{ruby_array(definition.organization.prefixes)}.freeze

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
          attrs = definition.fields.map do |field|
            "        attribute :#{field.name}, :#{field.kind}"
          end.join("\n")
          maps = definition.fields.map do |field|
            "          map #{field.name.inspect}, to: :#{field.name}"
          end.join("\n")

          body(identifier_file_body(attrs, maps))
        end

        def identifier_file_body(attrs, maps)
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

                  PUBLISHER = #{definition.organization.publisher.inspect}

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
        end

        def urn_schema_file
          atoms = definition.urn.atoms.map do |atom|
            "        atom #{atom.path.inspect}, #{atom.prefix.inspect}"
          end.join("\n")
          types = definition.urn.types.map do |type|
            "        type #{type.type.inspect}, #{type.token.inspect}, core: #{ruby_array(type.core.map(&:to_sym))}"
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
                      { key: :#{@type.key}, web: :#{@type.key}, title: #{@type.title.inspect}, short: #{@type.short.inspect} }
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
        # identifier's fields: literals + interpolation.
        def render_expression
          parts = definition.templates[:canonical].sequences.first.map do |item|
            case item
            when Template::Lit
              item.text.gsub("\\\\") { "\\\\\\" }.gsub('"') { '\\"' }.gsub('#{') { '\\#{' }
            when Template::Field then "\#{@id.#{item.name}}"
            else raise Error, "render face may only carry literals and fields"
            end
          end
          "\"#{parts.join}\""
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
