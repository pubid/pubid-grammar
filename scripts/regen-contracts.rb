ruby_repo = ENV["PARSANOL_RUBY"] || File.expand_path("../../parsanol/parsanol-ruby", __dir__)
$LOAD_PATH.unshift File.join(ruby_repo, "lib")
require "parsanol"
require "parsanol/pg"
require "json"
require "digest"

base = File.expand_path("..", __dir__)
schemas = "#{base}/schemas"
corpora = "#{base}/corpora"
Dir.mkdir(corpora) unless Dir.exist?(corpora)

Dir.glob("#{base}/grammars/*.pg").sort.each do |f|
  name = File.basename(f, ".pg")
  begin
    document = Parsanol::PG::Parser.new(File.read(f)).parse
    Parsanol::PG::Imports.merge!(document, ["#{base}/grammars"])
    envelope = Parsanol::PG::Compiler.compile(document, tables_dir: "#{base}/tables").envelope
    artifact = Parsanol::PG::Artifact.new(envelope, nil, "#{base}/tables")
    entry = envelope["default_entry"] || artifact.entries.first

    # F3: binding-requirements schema, pinned to the artifact checksum
    schema = Parsanol::PG::Schema.from_artifact(artifact)
    file = {
      "grammar" => name,
      "artifact_checksum" => envelope["checksum"],
      "schema" => schema,
    }
    File.binwrite("#{schemas}/#{name}.schema.json", JSON.generate(file))

    # F4: corpora — frozen cross-runtime conformance triples from the Ruby
    # reference. Promotion rule: an artifact test input that parses on the
    # reference becomes a corpus case.
    rows = []
    envelope.fetch("tests", []).each do |test|
      input = test["input"]
      shape = artifact.parse(entry, input)
      bound = artifact.apply_bindings(entry, shape)
      rows << {
        "input" => input,
        "kind" => test["kind"],
        "parsanol_tree" => JSON.parse(JSON.generate(shape)),
        "bound" => JSON.parse(JSON.generate(bound)),
        "bound_hash" => "sha256:#{Digest::SHA256.hexdigest(JSON.generate(bound))}",
      }
    rescue Parsanol::ParseFailed
      next # reject inputs: parse failure IS the expected outcome
    end
    Dir.mkdir("#{corpora}/#{name}") unless Dir.exist?("#{corpora}/#{name}")
    File.binwrite("#{corpora}/#{name}/corpus.json", JSON.generate({
      "grammar" => name,
      "artifact_checksum" => envelope["checksum"],
      "cases" => rows,
    }))
    puts "#{name}: schema + #{rows.size} corpus cases"
  rescue Parsanol::PG::Error => e
    puts "FAIL #{name}: #{e.message[0, 100]}"
  end
end
