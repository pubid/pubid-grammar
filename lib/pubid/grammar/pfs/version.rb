# frozen_string_literal: true

module Pubid
  module Grammar
    module Pfs
      # The compiler release (issue #151). The v1 compiler stamped 0.1.0;
      # v2 is the composition release — multi-type emission, the numeric
      # kinds, the declared supplements/stages and the tier-B/C families
      # — and every artifact records the stamp: the generated grammar
      # declares it (`grammar … version "2.0.0"`), the .parg header
      # cites it, and the baked envelope's `version` field (read from
      # the grammar) carries it. The DEFINITION dialect remains
      # `pfs: 1` — v2 is additive within the major (see SCHEMA_VERSION).
      VERSION = "2.0.0"

      # The definition-schema major this compiler speaks. A definition
      # declaring a higher major fails closed: `pfs:` versioning is
      # additive within a major (the engine's `binding_version` precedent),
      # so a newer definition must never be silently mis-read by an
      # older compiler.
      SCHEMA_VERSION = 1
    end
  end
end
