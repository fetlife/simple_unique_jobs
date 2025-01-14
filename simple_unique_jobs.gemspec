# frozen_string_literal: true

require_relative "lib/simple_unique_jobs/version"

Gem::Specification.new do |spec|
  spec.name = "simple_unique_jobs"
  spec.version = SimpleUniqueJobs::VERSION
  spec.authors = ["Julien Letessier"]
  spec.email = ["julien@fetlife.com"]

  spec.summary = "Sidekiq middleware to prevent duplicate jobs."
  spec.description = "A much, much simpler version of the (great) sidekiq-unique-jobs gem."
  spec.homepage = "https://github.com/fetlife/simple_unique_jobs"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.5"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .circleci appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "murmurhash3", "~> 0.1.6"
  spec.metadata["rubygems_mfa_required"] = "true"
end
