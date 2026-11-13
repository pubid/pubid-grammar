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
        # fields.<name>: a capture with its lexical pattern. `item` names the
        # item capture of a `kind: list` field; `render` carries the list's
        # render-face composition; `fold` declares the ed.N-style fold
        # (the capture folds into another field's column plus a boolean
        # flag); `builder_only` marks a capture the builder consumes but
        # the model does not declare.
        Field = Struct.new(:name, :pattern, :kind, :item, :render, :fold,
                           :builder_only, keyword_init: true)
        # fields.<name>.fold: the capture lands on `into` (the model
        # column) with the boolean flag `flag` set — the coded flavors'
        # `ed.N → version + is_edition` shape. Presence of the source
        # capture IS the flag; the target column's render presence is
        # suppressed while the flag holds.
        Fold = Struct.new(:into, :flag, keyword_init: true)
        # fields.<name>.render (list fields): how the capture list renders
        # in the canonical face. `style` is `prefix` (each item glued
        # before: parts "-1-0") or `infix` (items joined: "a-b").
        ListRender = Struct.new(:glue, :style, keyword_init: true)
        # supplements: — the wrapper machinery (pubid#706 phase 3). `run`
        # is the builder-only capture carrying the printed run; `item`,
        # `kind` and `number` are the generated run-internal capture
        # names; `wrappers[]` are the synthesized supplement classes.
        Supplements = Struct.new(:run, :item, :kind, :number, :wrappers,
                                 keyword_init: true)
        # supplements.wrappers[]: one synthesized wrapper class — the
        # printed kind face ("A"), the wire tag it serializes as, and the
        # human title.
        Wrapper = Struct.new(:name, :face, :tag, :title, keyword_init: true)
        # mr: — the MR-slug hooks. A map of segment name → declaration;
        # each declaration is either {field:} or {join:, glue:}.
        Mr = Struct.new(:segments, keyword_init: true)
        # mr.segments[]: one hook declaration.
        MrField = Struct.new(:field, keyword_init: true)
        MrJoin = Struct.new(:join, :glue, keyword_init: true)
        # urn.schema.types[]: one PubidUrn type row. `core` carries bare
        # path strings (string-kind) or [path, kind] pairs (pfs:1 phase 3
        # adds the int kind).
        UrnType = Struct.new(:type, :token, :core, keyword_init: true)
        # urn.schema.atoms[]: one PubidUrn atom row.
        UrnAtom = Struct.new(:path, :prefix, :kind, keyword_init: true)
        # urn.official[]: one ordered segment of the OFFICIAL URN — a bare
        # field (omitted when it did not capture; `lower` downcases it,
        # `affix` prefixes the value, `edition_affix` replaces the affix
        # while the fold flag holds), a fused date group, or a composed
        # code (ordered slots, each glued before the previous rendered).
        UrnField = Struct.new(:name, :lower, :affix, :edition_affix, keyword_init: true)
        UrnDate = Struct.new(:fields, keyword_init: true)
        # urn.official[] compose slot: one field with the glue that
        # precedes it and the join style (`prefix` per item, `infix`
        # between values).
        UrnSlot = Struct.new(:field, :glue, :style, keyword_init: true)
        UrnCompose = Struct.new(:slots, keyword_init: true)
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
          :modules, :module_bindings, :date, :supplements, :mr,
          keyword_init: true,
        )
      end
    end
  end
end
