# frozen_string_literal: true

require_relative "lib/raclette/version"

Gem::Specification.new do |spec|
  spec.name          = "raclette"
  spec.version       = Raclette::VERSION
  spec.authors       = ["Julik Tarkhanov"]
  spec.email         = ["me@julik.nl"]

  spec.summary       = "Database-based rate limiter using leaky buckets"
  spec.description   = "Raclette allows you to define throttles and rate meters for your metered resources, all through your standard DB"
  spec.homepage      = "https://github.com/cheddar-me/raclette"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 2.4.0"

  # spec.metadata["allowed_push_host"] = "TODO: Set to 'https://mygemserver.com'"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/cheddar-me/raclette"
  spec.metadata["changelog_uri"] = "https://github.com/cheddar-me/raclette/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{\A(?:test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  spec.add_dependency "activerecord", "~> 7"
  spec.add_dependency "pg"
  spec.add_development_dependency "activesupport", "~> 7"
  spec.add_development_dependency "rails", "~> 7"

  # For more information and examples about making a new gem, checkout our
  # guide at: https://bundler.io/guides/creating_gem.html
end
