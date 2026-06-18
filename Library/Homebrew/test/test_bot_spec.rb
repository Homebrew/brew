# typed: strict
# frozen_string_literal: true

require "dev-cmd/test-bot"

RSpec.describe Homebrew::TestBot do
  describe "::run!" do
    it "trusts a third-party tap before running test-bot" do
      tap = Tap.fetch("thirdparty", "foo")
      tap.path.mkpath
      args = double(
        cleanup?:       false,
        local?:         false,
        tap:            tap.name,
        only_formulae?: false,
        git_name:       nil,
        git_email:      nil,
      )

      allow(args).to receive_messages(only_cleanup_before?:  false,
                                      only_setup?:           false,
                                      only_tap_syntax?:      false,
                                      only_formulae_detect?: false,
                                      only_bottles_fetch?:   false,
                                      only_cleanup_after?:   false)
      allow(described_class).to receive(:setup_github_actions_sandbox!)
      allow(Utils).to receive(:safe_popen_read).and_return("revision")
      allow(Homebrew::TestBot::TestRunner).to receive(:run!).and_return(true)

      mktmpdir do |workdir|
        with_env(HOMEBREW_USER_CONFIG_HOME: "#{workdir}/.homebrew") do
          expect { described_class.run!(args) }.to output(%r{==> Trusted tap: thirdparty/foo}).to_stdout
          expect(Homebrew::Trust.trusted?(:tap, "thirdparty/foo")).to be(true)
        end
      end
    ensure
      Homebrew::Trust.clear!(:tap)
      FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"thirdparty"
    end

    it "trusts a third-party tap in the local test-bot config home" do
      old_umask = T.let(nil, T.nilable(Integer))
      tap = Tap.fetch("thirdparty", "foo")
      tap.path.mkpath
      args = double(
        cleanup?:       false,
        local?:         true,
        tap:            tap.name,
        only_formulae?: false,
        git_name:       nil,
        git_email:      nil,
      )

      allow(args).to receive_messages(only_cleanup_before?:  false,
                                      only_setup?:           false,
                                      only_tap_syntax?:      false,
                                      only_formulae_detect?: false,
                                      only_bottles_fetch?:   false,
                                      only_cleanup_after?:   false)
      allow(described_class).to receive(:setup_github_actions_sandbox!)
      allow(Utils).to receive(:safe_popen_read).and_return("revision")
      allow(Homebrew::TestBot::TestRunner).to receive(:run!).and_return(true)

      mktmpdir do |workdir|
        workdir.cd do
          with_env(
            HOMEBREW_USER_CONFIG_HOME: "#{workdir}/original/.homebrew",
            HOME:                      "#{workdir}/original",
            XDG_CONFIG_HOME:           "#{workdir}/xdg",
          ) do
            old_umask = File.umask(0002)

            expect { described_class.run!(args) }.to output(%r{==> Trusted tap: thirdparty/foo}).to_stdout

            trust_file = workdir/"home/.homebrew/trust.json"
            expect(trust_file).to exist
            expect(trust_file.dirname.stat.mode & 0777).to eq(0700)
            expect(JSON.parse(trust_file.read).fetch("trustedtaps")).to include("thirdparty/foo")
          end
        end
      end
    ensure
      File.umask(old_umask) if old_umask
      Homebrew::Trust.clear!(:tap)
      FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"thirdparty"
    end

    it "does not set up the sandbox for only runs without sandboxed code" do
      allow(described_class).to receive(:local?).and_return(false)
      allow(Utils).to receive(:safe_popen_read).and_return("revision")
      allow(Homebrew::TestBot::TestRunner).to receive(:run!).and_return(true)

      expect(described_class).not_to receive(:setup_github_actions_sandbox!)

      [
        :only_cleanup_before?,
        :only_tap_syntax?,
        :only_formulae_detect?,
        :only_bottles_fetch?,
        :only_cleanup_after?,
      ].each do |only_arg|
        args = double(
          cleanup?:       false,
          local?:         false,
          tap:            nil,
          only_formulae?: false,
          git_name:       nil,
          git_email:      nil,
        )
        allow(args).to receive_messages(only_cleanup_before?:  false,
                                        only_setup?:           false,
                                        only_tap_syntax?:      false,
                                        only_formulae_detect?: false,
                                        only_bottles_fetch?:   false,
                                        only_cleanup_after?:   false,
                                        only_arg => true)

        described_class.run!(args)
      end
    end

    it "sets up the sandbox for formulae runs" do
      allow(described_class).to receive(:local?).and_return(false)
      allow(Utils).to receive(:safe_popen_read).and_return("revision")
      allow(Homebrew::TestBot::TestRunner).to receive(:run!).and_return(true)

      expect(described_class).to receive(:setup_github_actions_sandbox!).exactly(3).times

      [:only_setup?, :only_formulae?, :only_formulae_dependents?].each do |only_arg|
        args = double(
          cleanup?:       false,
          local?:         false,
          tap:            nil,
          only_formulae?: only_arg == :only_formulae?,
          git_name:       nil,
          git_email:      nil,
        )

        allow(args).to receive_messages(only_cleanup_before?:      false,
                                        only_setup?:               false,
                                        only_tap_syntax?:          false,
                                        only_formulae_detect?:     false,
                                        only_formulae_dependents?: only_arg == :only_formulae_dependents?,
                                        only_bottles_fetch?:       false,
                                        only_cleanup_after?:       false)

        described_class.run!(args)
      end
    end
  end

  describe "::setup_github_actions_sandbox!" do
    around do |example|
      with_env(HOMEBREW_NO_SANDBOX_LINUX: nil) { example.run }
    end

    before do
      allow(GitHub::Actions).to receive(:env_set?).and_return(true)
      allow(Homebrew::EnvConfig).to receive(:sandbox_linux?).and_return(true)
    end

    it "enables the Linux sandbox for GitHub Actions developers" do
      allow(Homebrew::EnvConfig).to receive(:sandbox_linux?).and_call_original
      expect(described_class).to receive(:configure_sandbox!).and_return(true)

      with_env(HOMEBREW_DEVELOPER: "1", HOMEBREW_SANDBOX_LINUX: nil) do
        described_class.setup_github_actions_sandbox!
      end
    end

    it "configures the Linux sandbox for GitHub Actions" do
      expect(described_class).to receive(:configure_sandbox!).and_return(true)

      described_class.setup_github_actions_sandbox!
    end

    it "disables the Linux sandbox if GitHub Actions cannot configure it" do
      allow(described_class).to receive(:configure_sandbox!).and_return(false)

      described_class.setup_github_actions_sandbox!

      expect(ENV.fetch("HOMEBREW_NO_SANDBOX_LINUX")).to eq("1")
    end

    it "does nothing outside GitHub Actions" do
      allow(GitHub::Actions).to receive(:env_set?).and_return(false)
      expect(described_class).not_to receive(:configure_sandbox!)

      described_class.setup_github_actions_sandbox!
    end

    it "does nothing when the Linux sandbox is disabled" do
      allow(Homebrew::EnvConfig).to receive(:sandbox_linux?).and_return(false)
      expect(described_class).not_to receive(:configure_sandbox!)

      described_class.setup_github_actions_sandbox!
    end
  end
end
