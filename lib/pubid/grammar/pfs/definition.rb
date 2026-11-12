# frozen_string_literal: true

module Pubid
  module Grammar
    module Pfs
      # The typed definition tree. This is the in-memory model the
      # validator, the PARG generator and the Ruby generator all read; the
      # YAML file is the SSOT, this tree is its shape-checked projection.
      module Definition
        # organization: section.
        Organization = Struct.new(:name, :publisher, :prefixes, keyword_init: true)
        # types.<name>: a typed identifier class of the scheme.
        Type = Struct.new(:name, :key, :web, :title, :short, :tag, :stage, keyword_init: true)
        # types.<name>.stage: the typed-stage binding
        # (body code → harmonized stage mapping).
        Stage = Struct.new(:code, :stage_code, :abbr, keyword_init: true)
        # fields.<name>: a capture with its lexical pattern.
        Field = Struct.new(:name, :pattern, :kind, keyword_init: true)
        # urn.schema.types[]: one PubidUrn type row.
        UrnType = Struct.new(:type, :token, :core, keyword_init: true)
        # urn.schema.atoms[]: one PubidUrn atom row.
        UrnAtom = Struct.new(:path, :prefix, :kind, keyword_init: true)
        # urn.official[]: one ordered segment of the OFFICIAL URN — a bare
        # field (omitted when it did not capture) or a fused date group.
        UrnField = Struct.new(:name)
        UrnDate = Struct.new(:fields)
        # urn: section. `official` is empty when the definition keeps the
        # shared base URN generator.
        Urn = Struct.new(:namespace, :atoms, :types, :official, keyword_init: true)
        # date: the calendar binding — the declared fields fold into the
        # shared Components::Date (the coded flavors' own shape), the
        # serialized hash stays flat. `fields` order is the printed order.
        Date = Struct.new(:fields, keyword_init: true)
        # examples.positives[]: a REQUIRED parse/render row.
        Positive = Struct.new(:input, :renders, keyword_init: true)
        # The whole definition. `modules` carries the RESOLVED module
        # library modules the definition binds (in declaration order) and
        # `module_bindings` the raw `modules:` entries; `grammar` is the
        # MERGED fragment view (module fragments + the definition's own),
        # the one the templates reference and the PARG generator emits.
        Root = Struct.new(
          :source_path, :source_sha, :scheme, :title, :organization,
          :grammar, :types, :fields, :templates, :urn, :examples,
          :modules, :module_bindings, :date,
          keyword_init: true,
        )
      end
    end
  end
end
