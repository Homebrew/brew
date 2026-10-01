# typed: strict
# frozen_string_literal: true

require "open3"
require "yaml"

RSpec.describe "RuboCop" do
  context "when calling `rubocop` outside of the Homebrew environment" do
    sig { returns(T::Array[String]) }
    let(:homebrew_env_allowlist) do
      %w[
        HOMEBREW_TESTS
        HOMEBREW_USE_RUBY_FROM_PATH
        HOMEBREW_BUNDLER_VERSION
      ]
    end

    before do
      ENV.each_key do |key|
        ENV.delete(key) if key.start_with?("HOMEBREW_") && homebrew_env_allowlist.exclude?(key)
      end

      ENV["XDG_CACHE_HOME"] = (HOMEBREW_CACHE.realpath/"style").to_s
    end

    it "loads Rubydex from the installed platform gem" do
      script = <<~RUBY
        require ARGV.shift
        $LOAD_PATH.reject! { |path| path.include?("/rubydex-") }
        load ARGV.shift
      RUBY
      stdout, stderr, status = Bundler.with_unbundled_env do
        ENV.delete_if do |key, _|
          key.start_with?("HOMEBREW_") && homebrew_env_allowlist.exclude?(key)
        end
        ENV["XDG_CACHE_HOME"] = (HOMEBREW_CACHE.realpath/"style").to_s

        Open3.capture3(
          RUBY_PATH.to_s,
          "-W0",
          "-e",
          script,
          HOMEBREW_LIBRARY_PATH/"standalone.rb",
          HOMEBREW_LIBRARY_PATH/"utils/rubocop.rb",
          "-V",
          chdir: HOMEBREW_LIBRARY_PATH,
        )
      end

      expect(stderr).to be_empty
      expect(status).to be_a_success
      expect(stdout).to include("+Rubydex")
    end

    it "loads all Formula cops without errors" do
      stdout, stderr, status = Open3.capture3(RUBY_PATH.to_s, "-W0", "-S", "rubocop", TEST_FIXTURE_DIR/"testball.rb")
      expect(stderr).to be_empty
      expect(stdout).to include("no offenses detected")
      expect(status).to be_a_success
    end
  end
end
