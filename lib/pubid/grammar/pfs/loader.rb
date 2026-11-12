# frozen_string_literal: true

require "psych"

module Pubid
  module Grammar
    module Pfs
      # The strict YAML front door of the compiler.
      #
      # A .pfs file is plain data: mappings, sequences, scalars — no
      # anchors/aliases, no tags, no merge keys. The loader rejects
      # everything outside that surface, and it rejects DUPLICATE mapping
      # keys: YAML's silent last-key-wins would hide a copy-pasted field
      # declaration, and a schema that is the wizard's lossless substrate
      # (issue #706 §3.1) must round-trip exactly — a duplicate key is a
      # definition that does not.
      module Loader
        # Classes a definition may contain; everything else is rejected.
        PERMITTED = {
          "Hash" => Hash, "Array" => Array, "String" => String,
          "Integer" => Integer, "Float" => Float,
          "TrueClass" => TrueClass, "FalseClass" => FalseClass,
          "NilClass" => NilClass,
        }.freeze

        class DuplicateKeyError < Error; end
        class UnsupportedValueError < Error; end

        module_function

        # @param path [String] the .pfs file
        # @return [Hash] the parsed definition
        # @raise [Psych::SyntaxError] on malformed YAML
        # @raise [DuplicateKeyError] on a duplicate mapping key, citing its line
        # @raise [UnsupportedValueError] on an anchor/alias/tag/merge key
        def load(path)
          strict_visitor.accept(Psych.parse(File.read(path)))
        end

        def strict_visitor
          class_loader = Psych::ClassLoader::Restricted.new(PERMITTED, [])
          scanner = Psych::ScalarScanner.new(class_loader)
          Visitor.new(scanner, class_loader)
        end

        # ToRuby with the duplicate-key check installed. Keys are checked
        # per mapping BEFORE the children are built, so the error cites the
        # offending line rather than a downstream mystery.
        class Visitor < Psych::Visitors::ToRuby
          def visit_Psych_Nodes_Mapping(node)
            seen = {}
            node.children.each_slice(2).each do |key, _value|
              next unless key.is_a?(Psych::Nodes::Scalar)

              if key.tag && key.tag != "tag:yaml.org,2002:str"
                raise UnsupportedValueError,
                      "tagged mapping key #{key.value.inspect} (line #{key.start_line + 1})"
              end

              if seen.key?(key.value)
                raise DuplicateKeyError,
                      "duplicate key #{key.value.inspect} (line #{key.start_line + 1}, " \
                      "first at line #{seen[key.value] + 1})"
              end

              seen[key.value] = key.start_line
            end
            super
          end

          def visit_Psych_Nodes_Alias(node)
            raise UnsupportedValueError,
                  "anchors/aliases are not part of the PFS surface " \
                  "(#{node.anchor.inspect}, line #{node.start_line + 1})"
          end
        end
      end
    end
  end
end
