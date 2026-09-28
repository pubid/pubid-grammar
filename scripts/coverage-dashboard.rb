#!/usr/bin/env ruby
# frozen_string_literal: true
# P7: flavor coverage dashboard — one row per flavor, derived from the
# committed contracts. Engine gate columns come from the cross-runtime
# runner (CI fills PG_GATE_* env when available).

require "json"

base = File.expand_path("..", __dir__)
artifacts = Dir.glob(File.join(base, "artifacts", "*.json")).sort

rows = artifacts.map do |f|
  name = File.basename(f, ".json")
  envelope = JSON.parse(File.read(f))
  tests = envelope.fetch("tests", [])
  corpus_path = File.join(base, "corpora", name, "corpus.json")
  corpus = File.exist?(corpus_path) ? JSON.parse(File.read(corpus_path))["cases"].size : 0
  {
    flavor: name,
    version: envelope["version"],
    tests: tests.size,
    corpus: corpus,
    bindings: envelope.dig("entries", envelope["default_entry"], "bindings").to_a.size,
    render: envelope.dig("render", "default").to_a.size,
    schema: File.exist?(File.join(base, "schemas", "#{name}.schema.json")),
  }
end

gate = %w[ruby rust ts].map { |e| [e, ENV["PG_GATE_#{e.upcase}"]].join("=") if ENV["PG_GATE_#{e.upcase}"] }.compact

puts "| flavor | version | tests | corpus | bindings | render | schema |"
puts "|---|---|---|---|---|---|---|"
rows.each do |r|
  puts "| #{r[:flavor]} | #{r[:version]} | #{r[:tests]} | #{r[:corpus]} | #{r[:bindings]} | #{r[:render]} | #{r[:schema]} |"
end
puts
puts "flavors: #{rows.size}; corpus cases: #{rows.sum { |r| r[:corpus] }}; " \
       "with render: #{rows.count { |r| r[:render] > 0 }}; " \
       "gates: #{gate.empty? ? 'run scripts/cross-runtime-check.sh' : gate.join(' ')}"
