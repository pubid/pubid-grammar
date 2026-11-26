#!/usr/bin/env ruby
# frozen_string_literal: true

# Triage a grammar-miss report (JSONL: {input, consumer, context,
# timestamp} — docs/TELEMETRY-INTAKE.md): dedupe, classify each miss
# against the grammar inventory, and emit
#   <name>.report.json      the classified report
#   <name>.candidates.jsonl candidate test rows for the round pipeline
# next to the input file (or the paths given via --report/--candidates).
#
#   ruby scripts/telemetry-triage.rb <misses.jsonl> [options]
#
# The engine is pinned like the specs pin it (PARSANOL_VERSION, the
# bake-one.rb rule) so the parse verdicts match the committed contracts.

version = ENV.fetch("PARSANOL_VERSION", "1.5.1.0")
gem "parsanol", version

require "optparse"
base = File.expand_path("..", __dir__)
$LOAD_PATH.unshift File.join(base, "lib")
require "parsanol"
require "pubid/grammar/telemetry"

file = nil
report_out = nil
candidates_out = nil
OptionParser.new do |opts|
  opts.banner = "usage: telemetry-triage.rb <misses.jsonl> [options]"
  opts.on("--report PATH", "the report output path") { |v| report_out = v }
  opts.on("--candidates PATH", "the candidates output path") { |v| candidates_out = v }
end.parse!(ARGV)
file = ARGV.shift
abort "usage: telemetry-triage.rb <misses.jsonl>" unless file
abort "no such miss file: #{file}" unless File.file?(file)

engine = Pubid::Grammar::Telemetry::Runtime.new(repo_root: base)
result = Pubid::Grammar::Telemetry::Triage.run(
  file, engine: engine, report_out: report_out, candidates_out: candidates_out
)

report = result.report
puts "triaged #{report['source']['file']}: " \
     "#{report['source']['misses']} misses " \
     "(#{report['source']['intake_errors']} intake errors)"
report["summary"]["by_classification"].each do |klass, count|
  puts format("  %-13s %d", "#{klass}:", count)
end
puts "report:     #{result.report_path}"
puts "candidates: #{result.candidates_path}"
