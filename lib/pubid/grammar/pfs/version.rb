# frozen_string_literal: true

module Pubid
  module Grammar
    module Pfs
      # The compiler release.
      VERSION = "0.1.0"

      # The definition-schema major this compiler speaks. A definition
      # declaring a higher major fails closed: `pfs:` versioning is
      # additive within a major (the engine's `binding_version` precedent),
      # so a newer definition must never be silently mis-read by an
      # older compiler.
      SCHEMA_VERSION = 1
    end
  end
end
