# frozen_string_literal: true

require_relative "lib/ruby_todo/version"

Gem::Specification.new do |spec|
  spec.name = "ruby_todo"
  spec.version = RubyTodo::VERSION
  spec.authors = ["Jeremiah Parrack"]
  spec.email = ["jeremiahlukus1@gmail.com"]

  spec.summary = "A command-line todo application"
  spec.description = "A flexible and powerful todo list management system for the command line"
  spec.homepage = "https://github.com/jeremiahlukus/ruby_todo"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/jeremiahlukus/ruby_todo"
  spec.metadata["changelog_uri"] = "https://github.com/jeremiahlukus/ruby_todo/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .circleci appveyor Gemfile]) ||
        f.end_with?(".gem")
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "activerecord", "~> 7.1"
  spec.add_dependency "colorize", "~> 1.1"
  spec.add_dependency "sqlite3", "~> 1.7"
  spec.add_dependency "thor", "~> 1.3"
  spec.add_dependency "tty-prompt", "~> 0.23"
  spec.add_dependency "tty-table", "~> 0.12"

  # Development dependencies
  spec.add_development_dependency "minitest", "~> 5.19"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rubocop", "~> 1.59"
  spec.add_development_dependency "rubocop-minitest", "~> 0.34"
  spec.add_development_dependency "rubocop-rake", "~> 0.6"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
