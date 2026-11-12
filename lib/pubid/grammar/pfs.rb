# frozen_string_literal: true

# PFS — the PubID Format Schema compiler (pubid/pubid#706).
#
# One data file (`.pfs`, YAML) per body declares its identifier scheme:
# organization/publishers, type tokens, field patterns, canonical/alternate
# templates, stage bindings, the URN schema, and REQUIRED examples
# (positive + negative). This compiler generates the PARG edition-2 grammar
# from those declarations, bakes it through the existing parsanol pipeline,
# verifies the declared examples against the baked artifact, and (optionally)
# emits the Ruby flavor module that vendors it.
#
# The compiled flavor is a peer of the coded flavors: same registry, same
# input guards, same error namespace, same URN contracts — inherited by
# construction because the generated flavor enters through the same doors.
#
# Layout (this repo is the grammar SSOT, pubid/pubid#669):
#   definitions/*.pfs   the scheme definitions (the SSOT input)
#   grammars/<key>.parg generated, committed (PFS header marks it)
#   artifacts/<key>.json baked by the existing pipeline
#   scripts/pfs         the CLI: compile + bake + verify + emit

module Pubid
  module Grammar
    module Pfs
      autoload :VERSION, "#{__dir__}/pfs/version"
      autoload :SCHEMA_VERSION, "#{__dir__}/pfs/version"
      autoload :Error, "#{__dir__}/pfs/errors"
      autoload :InvalidDefinition, "#{__dir__}/pfs/errors"
      autoload :ExampleFailure, "#{__dir__}/pfs/errors"
      autoload :Loader, "#{__dir__}/pfs/loader"
      autoload :Definition, "#{__dir__}/pfs/definition"
      autoload :ModuleLibrary, "#{__dir__}/pfs/module"
      autoload :Template, "#{__dir__}/pfs/template"
      autoload :Validator, "#{__dir__}/pfs/validator"
      autoload :PargGenerator, "#{__dir__}/pfs/parg_generator"
      autoload :RubyGenerator, "#{__dir__}/pfs/ruby_generator"
      autoload :Compiler, "#{__dir__}/pfs/compiler"
    end
  end
end
