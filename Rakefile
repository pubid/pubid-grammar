# frozen_string_literal: true

require "rake"

namespace :contracts do
  desc "Regenerate F3 schemas and F4 corpora from grammars/ (Ruby reference)"
  task :regen do
    ruby "scripts/regen-contracts.rb"
  end

  desc "Fail if schemas/ or corpora/ drift from the grammars"
  task check: :regen do
    clean = system("git", "diff", "--quiet", "--", "schemas", "corpora")
    abort "schemas/ or corpora/ are stale — run `rake contracts:regen` and commit" unless clean
  end
end
