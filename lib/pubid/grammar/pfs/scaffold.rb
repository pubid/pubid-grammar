# frozen_string_literal: true

module Pubid
  module Grammar
    module Pfs
      # `pfs new <org>` — the scaffold (issue #152).
      #
      # Emits the YAML skeleton a composed flavor starts from: the six
      # module bindings (iso.inner, iec.inner, en.overlay, national.prefix,
      # supplements.core, edition.core), the adoption dispatch, the dated
      # supplement wrappers, a minimal type/field/template surface and the
      # REQUIRED examples — stubbed so the generated definition compiles
      # and verifies GREEN immediately. Scaffolding that does not run is
      # debt: the composition here is the proven-green one (the bsi shape),
      # not a sketch.
      #
      # The header comments carry the wiring: the compile/verify command,
      # the derived-contracts round, the lint/doctor entry points and the
      # cutover recipe — so a scaffold is its own runbook.
      module Scaffold
        # The module library version the scaffold binds. Bumped when the
        # library ships a new module major.
        LIBRARY_VERSION = 1

        # The modules a scaffold binds, in declaration order, with the
        # parameter each demands (nil = none).
        MODULES = [
          ["iso.inner", nil],
          ["iec.inner", nil],
          ["en.overlay", nil],
          ["national.prefix", :prefixes],
          ["supplements.core", nil],
          ["edition.core", nil],
        ].freeze

        Finding = Struct.new(:id, :rule, :message, keyword_init: true)

        module_function

        # Derive the scaffold's names from the organization string.
        # @return [Hash{Symbol => String}] scheme:, title:, publisher:
        def derive_names(org)
          scheme = org.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
          unless scheme.match?(Validator::SCHEME)
            raise Error, "organization #{org.inspect} yields no valid scheme " \
                         "key (got #{scheme.inspect}) — pass --scheme explicitly"
          end

          { scheme: scheme, title: org,
            publisher: org.upcase.gsub(/[^A-Z0-9]+/, "") }
        end

        # @param org [String] the organization (positional argument)
        # @param scheme [String] the scheme key
        # @param title [String] the scheme title
        # @param publisher [String] the publisher token
        # @param prefixes [Array<String>] the head-dispatch tokens
        # @return [String] the .pfs definition text
        # @raise [InvalidDefinition] on a reserved or colliding token
        def generate(org:, scheme:, title:, publisher:, prefixes:)
          raise Error, "scheme #{scheme.inspect} must be a lower-case " \
                       "snake_case key" unless scheme.match?(Validator::SCHEME)
          raise Error, "title #{title.inspect} must not contain quotes or " \
                       "backslashes" if title.match?(/["\\]/)
          raise Error, "organization #{org.inspect} must not contain quotes " \
                       "or backslashes" if org.match?(/["\\]/)
          raise Error, "at least one prefix token is required" if prefixes.empty?

          prefixes.each_with_index do |token, i|
            Validator.check_reserved("organization.prefixes[#{i}]", token)
          end
          check_publisher(publisher)
          render(org: org, scheme: scheme, title: title,
                 publisher: publisher, prefixes: prefixes)
        end

        def check_publisher(publisher)
          Validator.check_reserved("organization.publisher", publisher)
          MODULES.each do |name, _param|
            mod_path = File.join(__dir__, "../../../../definitions/modules/#{name}.pfsmod")
            next unless File.file?(mod_path)

            mod = ModuleLibrary.load_one(mod_path).last
            if mod.tokens.map { |t| t.downcase.tr(":-_.", "") }
                    .include?(publisher.downcase.tr(":-_.", ""))
              raise InvalidDefinition.new(
                "organization.publisher",
                "#{publisher.inspect} collides with the #{name.inspect} module's " \
                "claimed token — the module's adoption faces would fight the " \
                "body's own head token; pick a distinct publisher token",
              )
            end
          end
        end

        def render(org:, scheme:, title:, publisher:, prefixes:)
          publisher_pattern = prefixes.map { |p| "\"#{p}\"" }.join(" / ")
          many = prefixes.size > 1
          # The stub examples dispatch on the FIRST head token (the head
          # tokens are what the publisher field captures — the publisher
          # COLUMN may differ from the printed head).
          head = prefixes.first
          module_lines = MODULES.map do |name, param|
            if param == :prefixes
              "  - module: #{name}\n    version: #{LIBRARY_VERSION}\n" \
              "    parameters:\n      prefixes: #{yaml_list(prefixes)}"
            else
              "  - module: #{name}\n    version: #{LIBRARY_VERSION}"
            end
          end.join("\n")

          <<~PFS
            # #{title} — the PFS scaffold (`pfs new`), the composed-flavor starting point.
            #
            # This definition compiled + verified GREEN the moment it was written
            # (the stub examples below pass against the baked artifact). Grow it by
            # replacing the stubs with the body's real scheme, never by editing the
            # generated grammar — the definition file is the SSOT.
            #
            # Composition (the module library, definitions/modules/):
            #   iso.inner        the adopted ISO document face ("BS ISO 8601:2019")
            #   iec.inner        the adopted IEC document face ("BS IEC 60747-8")
            #   en.overlay       the EN adoption face over iso.inner (EN, prEN, FprEN)
            #   national.prefix  THIS body's head token(s) — the prefixes parameter
            #   supplements.core the amendment/corrigendum operators (the /A, /C run)
            #   edition.core     the edition operator — demands `edition_space` below
            # Drop a binding by deleting its entry; the compiler fails closed on
            # the identity bases (en.overlay needs iso.inner bound).
            #
            # The wiring, end to end (run from the pubid-grammar repo root):
            #
            #   # 0. Pre-compile diagnostics — no engine needed:
            #   ruby scripts/pfs lint #{scheme}.pfs
            #
            #   # 1. Compile + bake + verify the REQUIRED examples:
            #   ruby scripts/pfs compile #{scheme}.pfs --as #{scheme}_pfs \\
            #     --parsanol-version <fleet pin, see .github/workflows/parg-conformance.yml>
            #
            #   # 2. The derived contracts round (schemas + F4 corpora):
            #   rake contracts:regen && git diff --exit-code -- schemas corpora
            #
            #   # 3. Drift + readiness, any time:
            #   ruby scripts/pfs doctor
            #
            #   # 4. Graduation to the coded slot (the dev-alias -> canonical
            #   #    cutover): docs/CUTOVER.md, checked by
            #   ruby scripts/pfs cutover #{scheme}_pfs

            pfs: 1

            scheme: #{scheme}
            title: "#{title}"

            organization:
              name: "#{org}"
              publisher: "#{publisher}"
              # The head-dispatch tokens of the scheme.
              prefixes: #{yaml_list(prefixes)}

            modules:
            #{module_lines}

            # Named lexical rules the fields reference. The module fragments
            # (iso_*, iec_*, en_*, supplement_*, edition_*) are merged beside
            # them; edition.core's edition_face demands `edition_space` — the
            # separator THIS body prints between "ed" and the ordinal.
            grammar:
              digit: "%x30-39"
              edition_space: '" "'

            # The default class: no tokens — every reference that captures no
            # type token selects it. Declare the body's own families beside it
            # (see cen.pfs: tokens in type position select the class).
            types:
              standard:
                key: #{scheme}
                title: "#{title} Standard"
                short: "#{publisher}"
                tag: "pubid:#{scheme}:standard"

            fields:
              # The head token(s): the body's own publisher face.
              publisher:
                pattern: '#{many ? "(#{publisher_pattern})" : publisher_pattern}'
                kind: string
              number:
                pattern: "1*digit"
                kind: string
              year:
                pattern: "4digit"
                kind: string
              # The adopted run: an EN/CEN/CLC/ISO/IEC lead token and the rest
              # of the document face, ending before this scheme's supplement
              # run (the item rule the supplements declaration compiles). The
              # run lands on the wrapper's adopted attribute through the
              # coded hook (lib/pubid/#{scheme}_pfs/adopted_base.rb, vendored
              # at cutover — see docs/CUTOVER.md).
              adopted:
                pattern: '((("EN" / "CEN" / "CLC" / "ISO" / "IEC")) *((!(#{scheme}_supplement) (%x01-09 / %x0B-10FFFF))))'
                kind: string
                builder_only: true

            # The scheme's calendar: the publication year of the document.
            date:
              fields: [year]

            templates:
              # The canonical face: the head alternation picks the first
              # alternative whose direct fields captured — the adoption face,
              # else the plain document face. The supplement run follows.
              canonical: '({publisher} " " {adopted} / {publisher} " " {number} [":" {year}]) [{supplements}]'

            # The supplement wrappers (supplements.core, bound): the printed
            # run "/A1:2021" folds into the wrapper chain over the base.
            supplements:
              run: supplements
              item: supplement
              kind: supplement_kind
              number: supplement_number
              date: [year]
              wrappers:
                amendment:
                  face: "A"
                  tag: "pubid:#{scheme}:amendment"
                  title: "Amendment"
                  fields: [year]
                  mr: [amd, number, year]
                  urn: [amd, number, year]
                corrigendum:
                  face: "C"
                  tag: "pubid:#{scheme}:corrigendum"
                  title: "Corrigendum"
                  fields: [year]
                  mr: [cor, number, year]
                  urn: [cor, number, year]

            # The adopted-base dispatch: the generated builder calls the
            # vendored coded hook for the captured adopted run (the bsi/cen
            # §4 escape hatch — explicit, never implicit).
            adopted:
              field: adopted
              hook: coded

            urn:
              # The scheme's own namespace (the wire tag above is the
              # SCHEME-canonical tag, so a dev-alias compiled flavor's
              # to_hash/to_urn stays stable across the cutover).
              namespace: #{scheme}
              schema:
                atoms:
                  - { path: number, prefix: n }
                  - { path: year, prefix: year }
                types:
                  - { type: "pubid:#{scheme}:identifier", token: id, core: [] }
                  - { type: "pubid:#{scheme}:standard", token: standard, core: [] }

            # REQUIRED. The live test panel: each positive must parse and
            # render as declared under the canonical face; each negative must
            # fail to parse. These are the stubs — replace them with the
            # body's real identifiers (ruby scripts/pfs capture captures a
            # specimen list losslessly) as the scheme takes shape.
            examples:
              positives:
                - input: "#{head} 123"
                  renders: "#{head} 123"
                - input: "#{head} 123:2020"
                  renders: "#{head} 123:2020"
                - input: "#{head} EN ISO 9001:2015"
                  renders: "#{head} EN ISO 9001:2015"
                - input: "#{head} 123:2020/A1:2021"
                  renders: "#{head} 123:2020/A1:2021"
                - input: "#{head} 123:2020/C1"
                  renders: "#{head} 123:2020/C1"
              negatives:
                - "nonsense"
                - "#{publisher}"
                - "ISO 9001:2015"
          PFS
        end

        def yaml_list(values)
          "[" + values.map { |v| "\"#{v}\"" }.join(", ") + "]"
        end
      end
    end
  end
end
