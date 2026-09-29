ruby_repo = ENV["PARSANOL_RUBY"] ||
            File.expand_path("../../../parsanol/parsanol-ruby", __dir__)
$LOAD_PATH.unshift File.join(ruby_repo, "lib")
require "parsanol"
require "parsanol/parg"
require "json"
require "digest"

base = File.expand_path("..", __dir__)
schemas = "#{base}/schemas"
corpora = "#{base}/corpora"
Dir.mkdir(corpora) unless Dir.exist?(corpora)

Dir.glob("#{base}/grammars/*.parg").sort.each do |f|
  name = File.basename(f, ".parg")
  begin
    document = Parsanol::PARG::Parser.new(File.read(f)).parse
    Parsanol::PARG::Imports.merge!(document, ["#{base}/grammars"])
    envelope = Parsanol::PARG::Compiler.compile(document, tables_dir: "#{base}/tables").envelope
    artifact = Parsanol::PARG::Artifact.new(envelope, nil, "#{base}/tables")
    entry = envelope["default_entry"] || artifact.entries.first
    render_variants = (envelope["render"] || {}).keys
    derive_names = (envelope["derive"] || {}).keys

    # F3: binding-requirements schema, pinned to the artifact checksum
    schema = Parsanol::PARG::Schema.from_artifact(artifact)
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
      row = {
        "input" => input,
        "kind" => test["kind"],
        "parsanol_tree" => JSON.parse(JSON.generate(shape)),
        "bound" => JSON.parse(JSON.generate(bound)),
        "bound_hash" => "sha256:#{Digest::SHA256.hexdigest(JSON.generate(bound))}",
      }
      # F6: render/derive outputs are frozen alongside the bound maps so
      # all three engines replay them as a standing parity gate.
      unless render_variants.empty?
        row["rendered"] = render_variants.to_h do |v|
          [v, artifact.render_string(entry, input, variant: v)]
        end
      end
      unless derive_names.empty?
        row["derived"] = derive_names.to_h do |n|
          [n, artifact.derive_string(entry, input, n)]
        end
      end
      rows << row
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
  rescue Parsanol::PARG::Error => e
    puts "FAIL #{name}: #{e.message[0, 100]}"
  end
end
