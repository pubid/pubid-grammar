# frozen_string_literal: true

# Pubid::Grammar — the grammar SSOT namespace (pubid/pubid-grammar).
#
# Children are autoloaded here (the immediate parent namespace's file) so
# requiring this file never eagerly loads the engines underneath.
module Pubid
  module Grammar
    autoload :Pfs, "#{__dir__}/grammar/pfs"
    autoload :Telemetry, "#{__dir__}/grammar/telemetry"
  end
end
