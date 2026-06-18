# typed: true
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/tests"

RSpec.describe Homebrew::DevCmd::Tests do
  it_behaves_like "parseable arguments"

  describe "#check_test_environment!", :needs_linux do
    subject(:tests) { described_class.new([]) }

    before do
      require "extend/os/linux/dev-cmd/tests"
      require "sandbox"

      allow(GitHub::Actions).to receive(:env_set?).and_return(false)
    end

    it "does not require the Linux sandbox when Linux sandboxing is disabled" do
      allow(Sandbox).to receive(:available?).and_return(false)
      expect(Sandbox).not_to receive(:ensure_sandbox_installed!)
      expect(Sandbox).not_to receive(:configure!)

      with_env(HOMEBREW_NO_SANDBOX_LINUX: "1") do
        expect { tests.send(:check_test_environment!) }.not_to raise_error
      end
    end

    it "raises when the requested Linux sandbox is unavailable" do
      allow(Sandbox).to receive_messages(available?:     false,
                                         failure_reason: "Bubblewrap is not working.")
      expect(Sandbox).to receive(:ensure_sandbox_installed!).with(install_from_tests: true)

      expect { tests.send(:check_test_environment!) }
        .to raise_error(UsageError, "Invalid usage: Bubblewrap is not working.")
    end

    it "installs and probes sandbox availability when Linux sandboxing is enabled" do
      allow(Sandbox).to receive(:available?).and_return(true)
      expect(Sandbox).to receive(:ensure_sandbox_installed!).with(install_from_tests: true)

      expect { tests.send(:check_test_environment!) }.not_to raise_error
    end

    it "configures the sandbox on GitHub Actions when Linux sandboxing is enabled" do
      allow(GitHub::Actions).to receive(:env_set?).and_return(true)
      allow(Sandbox).to receive(:available?).and_return(true)
      expect(Sandbox).to receive(:configure!)
      expect(Sandbox).not_to receive(:ensure_sandbox_installed!)

      expect { tests.send(:check_test_environment!) }.not_to raise_error
    end
  end

  describe "#changed_test_files" do
    subject(:changed_test_files) { tests.send(:changed_test_files) }

    let(:tests) { described_class.new([]) }

    context "when a spec file changed" do
      let(:changed_file) { "Library/Homebrew/test/cmd/help_spec.rb\n" }

      before do
        allow(Utils::Git).to receive(:changed_files).and_return(changed_file.split("\n"))
      end

      it "includes the changed spec file" do
        expect(changed_test_files).to include("test/cmd/help_spec.rb")
      end
    end

    context "when a non-test Ruby file changed" do
      let(:changed_file) { "Library/Homebrew/cmd/help.rb\n" }

      before do
        allow(Utils::Git).to receive(:changed_files).and_return(changed_file.split("\n"))
      end

      it "maps the file to its corresponding spec" do
        expect(changed_test_files).to include("test/cmd/help_spec.rb")
      end
    end

    context "when integration shared context changed" do
      let(:changed_file) do
        "Library/Homebrew/test/support/helper/spec/shared_context/integration_test.rb\n"
      end

      before do
        allow(Utils::Git).to receive(:changed_files).and_return(changed_file.split("\n"))
      end

      it "includes integration tests and excludes unrelated tests", :aggregate_failures do
        expect(changed_test_files).to include("test/cmd/help_spec.rb")
        expect(changed_test_files).not_to include("test/dev-cmd/tests_spec.rb")
      end
    end

    context "when cask shared context changed" do
      let(:changed_file) do
        "Library/Homebrew/test/support/helper/spec/shared_context/homebrew_cask.rb\n"
      end

      before do
        allow(Utils::Git).to receive(:changed_files).and_return(changed_file.split("\n"))
      end

      it "includes cask tests and excludes non-cask tests", :aggregate_failures do
        expect(changed_test_files).to include("test/cmd/outdated_spec.rb")
        expect(changed_test_files).not_to include("test/cmd/help_spec.rb")
        expect(changed_test_files).not_to include("test/dev-cmd/pr-pull_spec.rb")
        expect(changed_test_files).not_to include("test/cmd/bundle/remove_subcommand_spec.rb")
      end
    end
  end
end
