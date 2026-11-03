#!/usr/bin/env ruby
# frozen_string_literal: true

# Bake one PARG flavor artifact at an explicitly pinned compiler.
# Usage: ruby scripts/bake-one.rb <flavor> <version>
# The `parsanol` binstub always resolves the LATEST installed gem, so a
# bake must force the compiler with `gem "<name>", "<version>"` before
# require; the script prints Parsanol::VERSION and verifies the
# compiler_version stamp recorded inside the baked envelope matches.

flavor = ARGV.fetch(0)
version = ARGV.fetch(1)

gem "parsanol", version
require "parsanol"
puts "baking #{flavor} with Parsanol::VERSION=#{Parsanol::VERSION}"

require "parsanol/parg"
require "json"

base = File.expand_path("..", __dir__)
source = File.join(base, "grammars", "#{flavor}.parg")
out = File.join(base, "artifacts", "#{flavor}.json")

document = Parsanol::PARG::Parser.new(File.read(source)).parse
Parsanol::PARG::Imports.merge!(document, [File.join(base, "grammars")])
envelope = Parsanol::PARG::Compiler.compile(document,
                                            tables_dir: File.join(base, "tables")).envelope

stamp = envelope["compiler_version"]
abort "compiler stamp #{stamp.inspect} != requested #{version.inspect}" unless stamp == version

File.binwrite(out, JSON.generate(envelope))
puts "wrote #{out} (checksum #{envelope["checksum"][0, 12]}..., " \
     "compiler_version #{stamp})"
