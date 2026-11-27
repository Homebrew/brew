# typed: strict
# frozen_string_literal: true

require "dev-cmd/test-bot"

RSpec.describe Homebrew::TestBot do
  describe "::run!" do
    it "trusts a third-party tap and preserves earlier failures when the tests pass", :trust_store do
      tap = Tap.fetch("thirdparty", "foo")
      tap.path.mkpath
      args = Homebrew::Cmd::TestBotCmd.new(["--tap=#{tap.name}"]).args
      allow(Utils).to receive(:safe_popen_read).and_return("revision")
      allow(Homebrew::TestBot::TestRunner).to receive(:run!).and_return(true)
      Homebrew.failed = true

      mktmpdir do |workdir|
        workdir.cd do
          expect { described_class.run!(args) }.to output(%r{==> Trusted tap: thirdparty/foo}).to_stdout
          expect(Homebrew::Trust.trusted?(:tap, "thirdparty/foo")).to be(true)
          expect(Homebrew).to have_failed
        end
      end
    ensure
      Homebrew::Trust.clear!(:tap)
      FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"thirdparty"
    end

    it "trusts a custom-remote third-party tap by its remote URL", :trust_store do
      tap = Tap.fetch("thirdparty", "custom")
      tap.path.mkpath
      system "git", "-C", tap.path.to_s, "init"
      system "git", "-C", tap.path.to_s, "remote", "add", "origin", "https://gitlab.com/other/repo"
      args = Homebrew::Cmd::TestBotCmd.new(["--tap=#{tap.name}"]).args
      allow(Utils).to receive(:safe_popen_read).and_return("revision")
      allow(Homebrew::TestBot::TestRunner).to receive(:run!).and_return(true)

      mktmpdir do |workdir|
        workdir.cd do
          described_class.run!(args)
          expect(Homebrew::Trust.trusted_tap?(tap)).to be(true)
        end
      end
    ensure
      Homebrew::Trust.clear!(:tap)
      FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"thirdparty"
    end

    it "trusts a third-party tap in the local test-bot config home", :trust_store do
      old_umask = T.let(nil, T.nilable(Integer))
      tap = Tap.fetch("thirdparty", "foo")
      tap.path.mkpath
      args = Homebrew::Cmd::TestBotCmd.new(["--local", "--tap=#{tap.name}"]).args
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
  end
end
