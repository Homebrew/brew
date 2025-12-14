# frozen_string_literal: true

require "open3"
require "yaml"

RSpec.describe "RuboCop" do
  context "when calling `rubocop` outside of the Homebrew environment" do
    before do
      ENV.each_key do |key|
        allowlist = %w[
          HOMEBREW_TESTS
          HOMEBREW_USE_RUBY_FROM_PATH
          HOMEBREW_BUNDLER_VERSION
        ]
        ENV.delete(key) if key.start_with?("HOMEBREW_") && allowlist.exclude?(key)
      end

      ENV["XDG_CACHE_HOME"] = (HOMEBREW_CACHE.realpath/"style").to_s
    end

    it "loads all Formula cops without errors" do
      # TODO: Remove these args once TestProf fixes their RuboCop plugin.
      test_prof_rubocop_args = [
        # Require "sorbet-runtime" to bring T into scope for warnings.rb
        "-r", "sorbet-runtime",
        # Require "extend/module" to include T::Sig in Module for warnings.rb
        "-r", HOMEBREW_LIBRARY_PATH/"extend/module.rb",
        # Work around TestProf RuboCop plugin issues
        "-r", HOMEBREW_LIBRARY_PATH/"utils/test_prof_rubocop_stub.rb"
      ]

      stdout, stderr, status = Open3.capture3(RUBY_PATH, "-W0", "-S", "rubocop", TEST_FIXTURE_DIR/"testball.rb",
                                              *test_prof_rubocop_args)
      expect(stderr).to be_empty
      expect(stdout).to include("no offenses detected")
      expect(status).to be_a_success
    end
  end

  context "with TargetRubyVersion" do
    it "matches .ruby-version" do
      rubocop_config_path = HOMEBREW_LIBRARY_PATH.parent/".rubocop.yml"
      rubocop_config = YAML.unsafe_load_file(rubocop_config_path)
      target_ruby_version = rubocop_config.dig("AllCops", "TargetRubyVersion")

      ruby_version_path = HOMEBREW_LIBRARY_PATH/".ruby-version"
      ruby_version = ruby_version_path.read.strip.to_f

      expect(target_ruby_version).to eq(ruby_version)
    end
  end
end
