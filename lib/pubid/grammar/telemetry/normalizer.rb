# frozen_string_literal: true

module Pubid
  module Grammar
    module Telemetry
      # The consumer-mangling normalizer.
      #
      # Reverses ONLY the mechanical damage a consumer pipeline can inflict
      # on an otherwise well-formed identifier string: leading/trailing
      # whitespace, internal whitespace runs, non-breaking/figure spaces,
      # zero-width and bidirectional control characters, HTML entities, and
      # CR/LF artifacts. Case is never touched and no field is re-spelled:
      # a string that only parses after a case or token change is NOT a
      # consumer bug — it classifies as a grammar gap or a new flavor.
      module Normalizer
        # Non-breaking and figure spaces, zero-width and directional
        # controls, BOM, and the ASCII whitespace artifacts — spelled
        # out as escapes so the set is auditable in plain source.
        #   U+00A0 nbsp; U+1680 ogham; U+2000-200F figure/en spaces,
        #   zero-widths, LRM/RLM; U+2028/2029 line/paragraph separator;
        #   U+202A-202E directional embeddings; U+2060 word joiner;
        #   U+2066-2069 directional isolates; U+FEFF BOM; CR/LF/TAB.
        CONTROL_CHARS =
          /[   -‏  ‪-‮⁠⁦-⁩﻿\r\n\t]/.freeze

        ENTITIES = {
          "&amp;" => "&", "&lt;" => "<", "&gt;" => ">",
          "&quot;" => "\"", "&apos;" => "'", "&nbsp;" => " ",
        }.freeze

        def self.normalize(input)
          text = input.dup
          ENTITIES.each { |entity, char| text = text.gsub(entity, char) }
          text = text.gsub(CONTROL_CHARS, " ")
          text.squeeze(" ").strip
        end

        # True when normalization changed the string (so a normalized-parse
        # success is evidence of consumer mangling, not of grammar coverage).
        def self.mangled?(input)
          normalize(input) != input
        end
      end
    end
  end
end
