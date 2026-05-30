# typed: true
# frozen_string_literal: true

require "utils/output"
require "utils/github/actions"

RSpec.describe Utils::Output do
  let(:klass) { Utils::Output }

  def esc(code)
    /(\e\[\d+m)*\e\[#{code}m/
  end

  describe "#pretty_installed" do
    subject(:pretty_installed_output) { klass.pretty_installed("foo") }

    context "when $stdout is a TTY" do
      before { allow($stdout).to receive(:tty?).and_return(true) }

      context "with HOMEBREW_NO_EMOJI unset" do
        it "returns a string with a colored checkmark" do
          expect(pretty_installed_output)
            .to match(/#{esc 1}foo #{esc 32}✔#{esc 0}/)
        end
      end

      context "with HOMEBREW_NO_EMOJI set" do
        before { ENV["HOMEBREW_NO_EMOJI"] = "1" }

        it "returns a string with colored info" do
          expect(pretty_installed_output)
            .to match(/#{esc 1}foo \(installed\)#{esc 0}/)
        end
      end
    end

    context "when $stdout is not a TTY" do
      before { allow($stdout).to receive(:tty?).and_return(false) }

      it "returns plain text" do
        expect(pretty_installed_output).to eq("foo")
      end
    end
  end

  describe "#pretty_uninstalled" do
    subject(:pretty_uninstalled_output) { klass.pretty_uninstalled("foo") }

    context "when $stdout is a TTY" do
      before { allow($stdout).to receive(:tty?).and_return(true) }

      context "with HOMEBREW_NO_EMOJI unset" do
        it "returns a string with a colored checkmark" do
          expect(pretty_uninstalled_output)
            .to match(/#{esc 1}foo #{esc 31}✘#{esc 0}/)
        end
      end

      context "with HOMEBREW_NO_EMOJI set" do
        before { ENV["HOMEBREW_NO_EMOJI"] = "1" }

        it "returns a string with colored info" do
          expect(pretty_uninstalled_output)
            .to match(/#{esc 1}foo \(uninstalled\)#{esc 0}/)
        end
      end
    end

    context "when $stdout is not a TTY" do
      before { allow($stdout).to receive(:tty?).and_return(false) }

      it "returns plain text" do
        expect(pretty_uninstalled_output).to eq("foo")
      end
    end
  end

  describe "#pretty_deprecated" do
    subject(:pretty_deprecated_output) { klass.pretty_deprecated("foo") }

    context "when $stdout is a TTY" do
      before { allow($stdout).to receive(:tty?).and_return(true) }

      it "returns a string with a colored (deprecated) label" do
        expect(pretty_deprecated_output)
          .to match(/foo #{esc 33}\(deprecated\)#{esc 0}/)
      end
    end

    context "when $stdout is not a TTY" do
      before { allow($stdout).to receive(:tty?).and_return(false) }

      it "returns plain text" do
        expect(pretty_deprecated_output).to eq("foo")
      end
    end
  end

  describe "#pretty_disabled" do
    subject(:pretty_disabled_output) { klass.pretty_disabled("foo") }

    context "when $stdout is a TTY" do
      before { allow($stdout).to receive(:tty?).and_return(true) }

      it "returns a string with a colored (disabled) label" do
        expect(pretty_disabled_output)
          .to match(/foo #{esc 31}\(disabled\)#{esc 0}/)
      end
    end

    context "when $stdout is not a TTY" do
      before { allow($stdout).to receive(:tty?).and_return(false) }

      it "returns plain text" do
        expect(pretty_disabled_output).to eq("foo")
      end
    end
  end

  describe "#pretty_duration" do
    it "converts seconds to a human-readable string" do
      expect(klass.pretty_duration(1)).to eq("1 second")
      expect(klass.pretty_duration(2.5)).to eq("2 seconds")
      expect(klass.pretty_duration(42)).to eq("42 seconds")
      expect(klass.pretty_duration(240)).to eq("4 minutes")
      expect(klass.pretty_duration(252.45)).to eq("4 minutes 12 seconds")
    end
  end

  describe "#ofail" do
    it "sets Homebrew.failed to true" do
      expect do
        klass.ofail "foo"
      end.to output("Error: foo\n").to_stderr

      expect(Homebrew).to have_failed
    end
  end

  describe "#opoo_without_github_actions_annotation" do
    it "prints a warning without a GitHub Actions annotation" do
      with_env(GITHUB_ACTIONS: "true") do
        expect(GitHub::Actions).not_to receive(:puts_annotation_if_env_set!)

        expect do
          klass.opoo_without_github_actions_annotation "foo"
        end.to output("Warning: foo\n").to_stderr
      end
    end
  end

  describe "#odie" do
    it "exits with 1" do
      expect do
        klass.odie "foo"
      end.to output("Error: foo\n").to_stderr.and raise_error SystemExit
    end
  end

  describe "#odeprecated" do
    it "raises a MethodDeprecatedError when `disable` is true" do
      ENV.delete("HOMEBREW_DEVELOPER")
      expect do
        klass.odeprecated(
          "method", "replacement",
          caller:  ["#{HOMEBREW_LIBRARY}/Taps/playbrew/homebrew-play/"],
          disable: true
        )
      end.to raise_error(
        MethodDeprecatedError,
        %r{method.*replacement.*playbrew/homebrew-play.*/Taps/playbrew/homebrew-play/}m,
      )
    end
  end
end
