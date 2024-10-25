require_relative 'lib/timescaledb/version'

Gem::Specification.new do |spec|
  spec.name          = "timescaledb"
  spec.version       = Timescaledb::VERSION
  spec.authors       = ["Jônatas Davi Paganini"]
  spec.email         = ["jonatasdp@gmail.com"]

  spec.summary       = %q{TimescaleDB helpers for Ruby ecosystem.}
  spec.description   = %q{Functions from timescaledb available in the ActiveRecord models.}
  spec.homepage      = "https://github.com/timescale/timescaledb-ruby"
  spec.license       = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.3.0")

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = spec.homepage
  #spec.metadata["source_code_uri"] = "TODO: Put your gem's public repo URL here."
  #spec.metadata["changelog_uri"] = "TODO: Put your gem's CHANGELOG.md URL here."

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir["lib/**/*", "LICENSE.txt"]
  spec.bindir        = "bin"
  spec.executables   = ["tsdb"]
  spec.require_paths = ["lib"]

  spec.add_dependency "pg", "~> 1.2"
  spec.add_dependency "activerecord"
  spec.add_dependency "activesupport"

  spec.add_development_dependency "pry"
  spec.add_development_dependency "rspec-its"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "dotenv"
  spec.add_development_dependency "rake", "~> 12.0"
  spec.add_development_dependency "database_cleaner-active_record"
end
