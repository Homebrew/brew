# typed: strict
# frozen_string_literal: true

require "diagnostic"
require "sandbox"

RSpec.describe Homebrew::Diagnostic::Checks do
  describe "#check_git_config_in_sandbox" do
    sig { returns(Homebrew::Diagnostic::Checks) }
    subject(:checks) { described_class.new }

    sig { returns(Pathname) }
    let(:home) { mktmpdir }

    # Keep each memoised helper with its type signature.
    # rubocop:disable RSpec/ScatteredLet
    sig { returns(T::Array[Pathname]) }
    let(:restricted_paths) { [] }
    # rubocop:enable RSpec/ScatteredLet

    before do
      allow(Utils::Git).to receive(:available?).and_return(true)
      allow(Sandbox).to receive_messages(nested_sandbox?: false, use_for?: true)
      allow(Dir).to receive(:home).with(ENV.fetch("USER")).and_return(home.to_s)
      ENV["GIT_CONFIG_NOSYSTEM"] = "1"
      ENV["GIT_CONFIG_GLOBAL"] = (home/".gitconfig").to_s
      (home/".gitconfig").write("[credential]\nhelper = !false\n")
      allow(Sandbox).to receive(:for_operation).and_wrap_original do |original, **options|
        original.call(**options).tap do |sandbox|
          restricted_paths.each { |path| sandbox.deny_read_path(path) }
          # Exercise Git and environment filtering without nesting the platform sandbox.
          allow(sandbox).to receive(:sandbox_command) { |args, _tmpdir| args }
          allow(sandbox).to receive(:apply_before_exec?).and_return(false)
        end
      end
    end

    it "accepts valid configuration" do
      expect(checks.check_git_config_in_sandbox).to be_nil
    end

    test_each(%w[macos linux]) do |platform|
      it "reads valid configuration in the #{platform} download sandbox",
         needs_linux: platform == "linux", needs_macos: platform == "macos" do
        allow(Sandbox).to receive(:nested_sandbox?).and_call_original
        skip "Nested sandboxing is not supported." if Sandbox.nested_sandbox?
        skip "Sandboxing is unavailable." unless Sandbox.available?
        allow(Sandbox).to receive(:for_operation).and_call_original

        expect(checks.check_git_config_in_sandbox).to be_nil
      end
    end

    it "accepts successful configuration reads with launcher warnings" do
      allow(GitDownloadStrategy).to receive(:sandboxed_git).and_wrap_original do |original, *args, **options|
        original.call(*args, **options).tap do |result|
          allow(result).to receive(:stderr).and_return("git: warning: confstr() failed; using /tmp instead\n")
        end
      end

      expect(checks.check_git_config_in_sandbox).to be_nil
    end

    it "uses just one sandboxed Git call" do
      expect(GitDownloadStrategy).to receive(:sandboxed_git).once.and_call_original

      checks.check_git_config_in_sandbox
    end

    it "does not execute configured credential helpers" do
      (home/".gitconfig").write("[credential]\nhelper = \"!touch '#{home}/helper-ran'\"\n")

      expect([checks.check_git_config_in_sandbox, (home/"helper-ran").exist?]).to eq([nil, false])
    end

    it "accepts an absent global configuration" do
      (home/".gitconfig").unlink

      expect(checks.check_git_config_in_sandbox).to be_nil
    end

    it "accepts readable nested includes and symlinks" do
      (home/".gitconfig").write("[include]\npath = nested\n")
      (home/"nested").make_symlink(home/"included")
      (home/"included").write("[include]\npath = leaf\n")
      (home/"leaf").write("[user]\nname = Example\n")

      expect(checks.check_git_config_in_sandbox).to be_nil
    end

    it "warns about malformed configuration without exposing its contents" do
      (home/".gitconfig").write("[private-token\n")

      expect(checks.check_git_config_in_sandbox&.to_s)
        .to match(/\AGit checks failed(?!.*private-token)/m)
    end

    it "does not warn about configured restricted paths without a Git failure" do
      restricted_paths << (home/"private-config")
      (home/"private-config").mkpath
      (home/".gitconfig").write("[external-tool]\npath = #{home}/private-config/settings\n")

      expect(checks.check_git_config_in_sandbox).to be_nil
    end

    it "uses the normal Git download network permissions" do
      expect(Sandbox).to receive(:for_operation).with(home_read_exception: :git, network_access: true)

      checks.check_git_config_in_sandbox
    end

    test_each([
      [Utils::Git, { available?: false }],
      [Sandbox, { use_for?: false }],
      [Sandbox, { nested_sandbox?: true }],
    ]) do |receiver, settings|
      it "does not probe when #{receiver} reports #{settings}" do
        allow(receiver).to receive_messages(settings)
        expect(Sandbox).not_to receive(:for_operation)

        checks.check_git_config_in_sandbox
      end
    end

    it "warns when reading configuration times out" do
      sandbox = Sandbox.for_operation(home_read_exception: :git, network_access: true)
      allow(Sandbox).to receive(:for_operation).and_return(sandbox)
      allow(sandbox).to receive(:capture).and_raise(Timeout::Error)

      expect(checks.check_git_config_in_sandbox&.to_s).to include("check timed out")
    end

    it "reports sandbox construction failures without exposing their details" do
      allow(Sandbox).to receive(:for_operation).and_raise(RuntimeError, "private-token")

      expect(checks.check_git_config_in_sandbox&.to_s).to match(/\A(?!.*private-token).*check could not run/m)
    end

    it "reports an unavailable temporary directory" do
      stub_const("HOMEBREW_TEMP", home/"missing")

      expect(checks.check_git_config_in_sandbox&.to_s).to include("check could not run")
    end

    it "lists restricted locations from Git's include errors in the remediation" do
      restricted_paths << (home/"private-config")
      (home/"private-config").mkpath
      (home/"private-config/included").write("[user]\nname = Example\n")
      (home/"private-config/included").chmod(0000)
      (home/".gitconfig").write("[include]\npath = ~/private-config/included\n")

      expect(checks.check_git_config_in_sandbox&.to_s)
        .to include("Git failed while reading configuration", "exit 128",
                    "Check your global Git configuration", (home/"private-config").to_s.inspect)
    ensure
      (home/"private-config/included").chmod(0600)
    end

    context "when Git fails with configuration output" do
      before do
        allow(GitDownloadStrategy).to receive(:sandboxed_git).and_wrap_original do |original, *args, **options|
          original.call(*args, **options).tap do |result|
            allow(result).to receive_messages(success?: false, stderr: "fatal: private-token\xFF\n")
          end
        end
      end

      it "lists restricted locations from configuration without exposing raw output" do
        restricted_paths << (home/"private-config")
        (home/"private-config").mkpath
        (home/".gitconfig").write(<<~EOS)
          [external-tool]
            config = #{home}/private-config/settings
            opaque = \xFF
        EOS

        private_config = Regexp.escape((home/"private-config").to_s.inspect)
        expect(checks.check_git_config_in_sandbox&.to_s)
          .to match(/\A(?!.*private-token).*#{private_config}/m)
      end

      it "does not mistake a similarly named location for a restricted path" do
        restricted_paths << (home/"private-config")
        (home/"private-config").mkpath
        (home/".gitconfig").write("[external-tool]\npath = #{home}/private-config-sibling\n")

        expect(checks.check_git_config_in_sandbox&.remediation&.text)
          .not_to include((home/"private-config").to_s.inspect)
      end
    end
  end
end
