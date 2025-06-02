# frozen_string_literal: true

RSpec.describe Utils do
  describe "ruby_check_version_script" do
    subject do
      homebrew_env = ENV.select { |key, _| key.start_with?("DINRUSBREW_") }
      Bundler.with_unbundled_env do
        ENV.delete_if { |key,| key.start_with?("DINRUSBREW_") }
        ENV.update(homebrew_env)
        quiet_system "#{DINRUSBREW_LIBRARY_PATH}/utils/ruby_check_version_script.rb", required_ruby_version
      end
    end

    before do
      ENV.delete("DINRUSBREW_DEVELOPER")
      ENV.delete("DINRUSBREW_USE_RUBY_FROM_PATH")
    end

    describe "succeeds on the running Ruby version" do
      let(:required_ruby_version) { RUBY_VERSION }

      it { is_expected.to be true }
    end

    describe "succeeds on newer mismatched major/minor required Ruby version and configured environment" do
      let(:required_ruby_version) { "2.0.0" }

      before do
        ENV["DINRUSBREW_DEVELOPER"] = "1"
        ENV["DINRUSBREW_USE_RUBY_FROM_PATH"] = "1"
      end

      it { is_expected.to be true }
    end

    describe "fails on on mismatched major/minor required Ruby version" do
      let(:required_ruby_version) { "1.2.3" }

      it { is_expected.to be false }
    end

    describe "fails on invalid required Ruby version" do
      let(:required_ruby_version) { "fish" }

      it { is_expected.to be false }
    end
  end
end
