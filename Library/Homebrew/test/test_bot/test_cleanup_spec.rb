# typed: strict
# frozen_string_literal: true

require "dev-cmd/test-bot"

RSpec.describe Homebrew::TestBot do
  it "cleans writable paths without sudo when sudo is disabled" do
    ENV["HOMEBREW_NO_SUDO"] = "1"
    ENV["HOMEBREW_GITHUB_ACTIONS"] = "1"
    ENV["GITHUB_ACTIONS_HOMEBREW_SELF_HOSTED"] = "1"
    cleanup = Class.new(Homebrew::TestBot::TestCleanup) do
      public :delete_or_move
    end.new

    expect(cleanup).not_to receive(:test)

    cleanup.delete_or_move([mktmpdir], sudo: true)
  end

  describe Homebrew::TestBot::CleanupAfter do
    # Regression test: checkout_branch_if_needed, reset_if_needed, and clean_if_needed
    # expect a String (repository path). Passing HOMEBREW_REPOSITORY (Pathname) would cause
    # "Parameter 'repository': Expected type String, got type Pathname" in strict typing.
    describe "#run!" do
      it "passes a String to checkout_branch_if_needed, reset_if_needed, and clean_if_needed when tap is set" do
        cleanup = described_class.new(
          tap:       CoreTap.instance,
          git:       "git",
          dry_run:   true,
          fail_fast: false,
          verbose:   false,
        )

        # Stub to avoid actual filesystem and process operations.
        allow(FileUtils).to receive(:chmod_R)
        allow(cleanup).to receive(:info_header)
        allow(cleanup).to receive(:delete_or_move)
        allow(cleanup).to receive(:test)
        allow(cleanup).to receive(:repository).and_return(Pathname.new("/nonexistent_#{SecureRandom.hex(8)}"))
        allow(SystemCommand).to receive(:quiet_system).and_return(false)
        allow(Keg).to receive(:must_be_writable_directories).and_return([])
        allow(Pathname).to receive(:glob).and_return([])

        expect(cleanup).to receive(:checkout_branch_if_needed).with(String)
        expect(cleanup).to receive(:reset_if_needed).with(String)
        expect(cleanup).to receive(:clean_if_needed).with(String)

        args = double(test_default_formula?: false, local?: false)
        with_env("HOMEBREW_GITHUB_ACTIONS" => nil, "GITHUB_ACTIONS" => nil) do
          cleanup.run!(args:)
        end
      end
    end
  end

  describe Homebrew::TestBot::CleanupBefore do
    describe "#run!" do
      it "restores trust for the tap being tested after cleanup" do
        tap = Tap.fetch("thirdparty", "foo")
        tap.path.mkpath
        cleanup = described_class.new(
          tap:       tap,
          git:       "git",
          dry_run:   true,
          fail_fast: false,
          verbose:   false,
        )
        args = double

        allow(cleanup).to receive(:test_header)
        allow(cleanup).to receive(:cleanup_shared) { FileUtils.rm_f Homebrew::Trust.trust_file }

        mktmpdir do |workdir|
          workdir.cd do
            with_env(HOMEBREW_USER_CONFIG_HOME: "#{workdir}/.homebrew") do
              Homebrew::Trust.trust!(:tap, tap)
              cleanup.run!(args:)

              expect(Homebrew::Trust.trust_file).to exist
              expect(Homebrew::Trust.trusted_tap?(tap)).to be(true)
            end
          end
        end
      ensure
        Homebrew::Trust.clear!(:tap)
        FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"thirdparty"
      end
    end

    describe "#untap_untrusted_taps" do
      it "does not untap the tap being tested" do
        current_tap = instance_double(Tap, name: "current/tap", path: HOMEBREW_TAP_DIRECTORY/"current/homebrew-tap")
        other_tap = instance_double(Tap, name: "other/tap")
        cleanup = described_class.new(
          tap:       current_tap,
          git:       "git",
          dry_run:   true,
          fail_fast: false,
          verbose:   false,
        )
        allow(Homebrew::Trust).to receive(:untrusted_taps).and_return([current_tap, other_tap])

        expect(cleanup).to receive(:test).with("brew", "untap", "--force", "other/tap")

        cleanup.untap_untrusted_taps
      end
    end
  end
end
