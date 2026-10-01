#!/usr/bin/env ruby
# frozen_string_literal: true

# Per-flavor R1 probe: compares the PARG artifact's builder-ready shape
# against the pubid monorepo parslet tree for inputs scraped from the
# monorepo's flavor specs. Reports structural parity so a flavor's
# parser swap can be gated before wiring.
#
#   PARSANOL_RUBY=... ruby scripts/parity-probe.rb [flavor ...]
#   (default: every .parg flavor with a monorepo Parser)

require "parsanol"
require "parsanol/parg"
require "json"

BASE = File.expand_path("..", __dir__)
MONO = ENV["PUBID_MONO"] || File.expand_path("../../pubid/pubid", BASE)
$LOAD_PATH.unshift File.join(MONO, "lib")
require "pubid"
LEAF_KEYS = %i[value line column offset length].freeze

# The monorepo flavors whose .parg grammar is independent (sub-grammars
# aiee/ire/nesc and the self-grammar parg are authoring-side; idf rides
# with iso's joint form).
SKIP = %w[aiee ire nesc parg idf].freeze

def normalize(node, top: false)
  case node
  when Parsanol::Slice then node.content
  when Hash
    return node[:value] if node.size == LEAF_KEYS.size && LEAF_KEYS.all? { |k| node.key?(k) }

    node.to_h { |k, v| [k, normalize(v)] }
  when Array
    flat = node.map { |n| normalize(n) }
    top && flat.all?(Hash) ? flat.reduce(:merge) : flat
  else
    node
  end
end

def scrape_inputs(flavor)
  dir = File.join(MONO, "spec", "pubid", flavor)
  dir = File.join(MONO, "lib", "pubid", flavor) unless Dir.exist?(dir)
  text = Dir.exist?(dir) ? Dir.glob("#{dir}/**/*.rb").map { |f| File.read(f) }.join : ""
  strings = text.scan(/"([^"\n]{4,70})"/).map(&:first).uniq
  strings.reject do |s|
    s.match?(/spec|describe|require|def |context|pubid:|expected|parse|_spec|should|it /i)
  end.first(24)
end

flavors = if ARGV.empty?
            Dir.glob("#{BASE}/grammars/*.parg").map { |f| File.basename(f, ".parg") }.sort - SKIP
          else
            ARGV
          end

results = flavors.map do |flavor|
  parser = nil
  begin
    mod = Object.const_get(:Pubid).const_get(flavor.split("_").map(&:capitalize).join)
    parser = mod.const_get(:Parser)
  rescue NameError, StandardError
    puts format("%-14s NO-MONOREPO-PARSER", flavor)
    next [flavor, :no_parser, 0, 0, 0]
  end
  begin
    doc = Parsanol::PARG::Parser.new(File.read("#{BASE}/grammars/#{flavor}.parg")).parse
    Parsanol::PARG::Imports.merge!(doc, ["#{BASE}/grammars"]) if doc.uses.any?
    env = Parsanol::PARG::Compiler.compile(doc, tables_dir: "#{BASE}/tables").envelope
    artifact = Parsanol::PARG::Artifact.new(env, nil, "#{BASE}/tables")
  rescue Parsanol::PARG::Error => e
    puts format("%-14s COMPILE-FAIL %s", flavor, e.message[0, 60])
    next [flavor, :compile_fail, 0, 0, 0]
  end
  # Flavor parsers expose different class-level entries (nist's
  # class_parse_with_preprocessing, etc.); resolve the one that exists.
  parse_entry = if parser.respond_to?(:parse)
                  ->(i) { parser.parse(i) }
                elsif (m = parser.singleton_methods.map(&:to_s).grep(/^class_parse/).first)
                  ->(i) { parser.public_send(m, i) }
                else
                  instance = parser.new
                  if instance.respond_to?(:parse)
                    ->(i) { instance.parse(i) }
                  end
                end
  if parse_entry.nil?
    puts format("%-14s NO-ENTRY", flavor)
    next [flavor, :no_entry, 0, 0, 0]
  end

  ok = 0
  diff = 0
  skip = 0
  shown = 0
  scrape_inputs(flavor).each do |input|
    expected = begin
      parse_entry.call(input)
    rescue StandardError
      skip += 1
      next
    end
    shape = begin
      normalize(artifact.parse("identifier", input), top: true)
    rescue StandardError
      skip += 1
      next
    end
    par_json = JSON.generate(expected)
    if par_json == JSON.generate(shape)
      ok += 1
    else
      diff += 1
      if shown < 2
        puts "  DIFF #{flavor} #{input.inspect[0, 55]}"
        puts "    par: #{par_json[0, 140]}"
        puts "    pg:  #{JSON.generate(shape)[0, 140]}"
        shown += 1
      end
    end
  end
  status = if diff.zero? && ok.positive?
             :CLEAN
           elsif ok.zero? && diff.zero?
             :NO_DATA
           else
             :DELTA
           end
  puts format("%-14s %-12s ok=%-3d diff=%-3d skipped=%d", flavor, status, ok, diff, skip)
  [flavor, status, ok, diff, skip]
end
clean = results.count { |_, st, ok, diff, _| st == :CLEAN }
puts "\nclean: #{clean}/#{results.size} probed flavors"
