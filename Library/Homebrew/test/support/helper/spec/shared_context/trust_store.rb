# typed: strict
# frozen_string_literal: true

require "tmpdir"

# Isolate the `Homebrew::Trust` store in a per-example config home so a parallel worker's teardown
# (which deletes the shared default `trust.json`) cannot clobber it between writing and re-reading.
RSpec.shared_context "trust store" do # rubocop:disable RSpec/ContextWording
  T.bind(self, T.class_of(RSpec::Core::ExampleGroup))

  around do |example|
    Dir.mktmpdir do |config_home|
      with_env(HOMEBREW_USER_CONFIG_HOME: config_home) { example.run }
    end
  end
end

RSpec.configure do |config|
  config.include_context "trust store", :trust_store
end
