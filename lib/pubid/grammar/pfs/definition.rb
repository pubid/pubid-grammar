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
        # types.<name>: a typed identifier class of the scheme. `tokens` are
        # the grammar spellings that SELECT the type (type-position tokens
        # like TR/Guide and publisher-position tokens like CR/ENV); a type
        # with no tokens is the scheme's default class. `publisher_default`
        # names the token the publisher column defaults to when the
        # reference omits a publisher face (publisher-type defaults,
        # issue #121 feature 5); absent, the default is the organization's
        # publisher.
        Type = Struct.new(:name, :key, :web, :title, :short, :tag, :stage,
                          :tokens, :publisher_default, :adopted,
                          keyword_init: true)
        # types.<name>.stage: the typed-stage binding
        # (body code → harmonized stage mapping).
        Stage = Struct.new(:code, :stage_code, :abbr, keyword_init: true)
        # stages.<key>: a declared draft stage of the scheme (issue #121
        # feature 2) — `tokens` are the accepted spellings ("prEN"), `urn`
        # is the official-URN stage code ("proposal"). The stage FIELD
        # serializes its key ("pren").
        StageDecl = Struct.new(:name, :tokens, :urn, keyword_init: true)
        # fields.<name>: a capture with its lexical pattern. `item` names the
        # item capture of a `kind: list` field; `render` carries the list's
        # render-face composition (or, on a string field, the value→face
        # map — the draft-stage spellings); `fold` declares the ed.N-style
        # fold (the capture folds into another field's column plus a
        # boolean flag); `builder_only` marks a capture the builder consumes
        # but the model does not declare; `map` maps the captured token to
        # the stored column value ("prEN" → "pren"); `urn` maps the stored
        # value to its official-URN face ("pren" → "proposal").
        Field = Struct.new(:name, :pattern, :kind, :item, :render, :fold,
                           :builder_only, :map, :urn, keyword_init: true)
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
        # supplements: — the wrapper machinery (pubid#706 phase 3, extended
        # for cen's shapes, issue #121 feature 3). `run` is the builder-only
        # capture carrying the printed run; `item`, `kind` and `number` are
        # the generated run-internal capture names; `wrappers[]` are the
        # synthesized supplement classes. `number_kind` ("integer" default,
        # "string" for cen) types the ordinal column; `number_optional`
        # allows an unnumbered item (cen's "/AC"). `date` names the
        # wrapper-owned calendar columns the run captures (cen's amendment
        # year, corrigendum year+month). `consolidated` synthesizes the
        # plus-run bundle class; `fragment` synthesizes the fragment
        # wrapper.
        Supplements = Struct.new(:run, :item, :kind, :number, :wrappers,
                                 :number_kind, :date,
                                 :consolidated, :fragment, keyword_init: true)
        # supplements.wrappers[]: one synthesized wrapper class — the
        # printed kind face ("A"), the wire tag it serializes as, the
        # human title, the wrapper-owned string columns (`fields`), the
        # optional ordinal flag (`number_optional` — cen's "/AC"),
        # the MR-suffix segments (`mr`: leading kind word + columns), and
        # the official-URN segments (`urn`).
        Wrapper = Struct.new(:name, :face, :tag, :title, :fields,
                             :number_optional, :mr, :urn, keyword_init: true)
        # supplements.consolidated: the plus-run bundle class — the wire
        # tag and the human title. Its members serialize via their own
        # hashes under `identifiers`.
        Consolidated = Struct.new(:tag, :title, keyword_init: true)
        # supplements.fragment: the fragment wrapper — the printed FRAG
        # face, the wire tag, and the builder-only capture carrying the
        # fragment ordinal.
        Fragment = Struct.new(:name, :face, :tag, :title, :field, :mr, :urn,
                              keyword_init: true)
        # adopted: — the adopted-base dispatch (issue #121 feature 4, the
        # §4 coded escape hatch). `field` names the builder-only capture
        # carrying the adopted run; `hook` names the coded hook the
        # generated builder calls (the only declared value is `coded` —
        # the hook is vendored beside the generated flavor and parses the
        # adopted string with the owning schemes' flavors).
        Adopted = Struct.new(:field, :hook, keyword_init: true)
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
        # Issue #121 feature 6 adds the fused shapes: `pub_group` (the
        # publisher column and the copublishers list fused with the glue,
        # downcased), `stage_code` ("stage." + the declared stage URN code,
        # draft rows only) and `adopted_mr` (the adopted document's MR
        # string, its dot/underscore separators fused to colons — the
        # coded generator's own shape).
        UrnField = Struct.new(:name, :lower, :affix, :edition_affix, keyword_init: true)
        UrnDate = Struct.new(:fields, keyword_init: true)
        UrnPubGroup = Struct.new(:glue, :lower, keyword_init: true)
        UrnStageCode = Struct.new(:marker, keyword_init: true)
        UrnAdoptedMr = Struct.new(:marker, keyword_init: true)
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
          :stages, :adopted,
          keyword_init: true,
        )
      end
    end
  end
end
