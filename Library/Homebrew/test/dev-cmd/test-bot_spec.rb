# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/test-bot"

RSpec.describe Homebrew::Cmd::TestBotCmd do
  it_behaves_like "parseable arguments"
  it_behaves_like "a documented command", "test-bot"

  it "prints the padded prefix for the current bottle tag" do
    tag = Utils::Bottles::Tag.from_symbol(:arm64_tahoe)
    allow(Utils::Bottles).to receive(:tag).and_return(tag)

    expect { described_class.new(["--print-padded-prefix"]).run }
      .to output("#{tag.padded_prefix}\n").to_stdout
  end

  it "fails when the current bottle tag has no padded prefix" do
    tag = Utils::Bottles::Tag.from_symbol(:tahoe)
    allow(Utils::Bottles).to receive(:tag).and_return(tag)

    expect { described_class.new(["--print-padded-prefix"]).run }
      .to raise_error(SystemExit)
      .and output(/No padded bottle prefix is available for #{tag}/).to_stderr
  end

  context "when testing casks", :cask do
    test_each([%w[--skip-setup homebrew/cask/local-caffeine], %w[--skip-setup --testing-casks=local-caffeine],
               %w[--only-casks local-caffeine]]) do |selection|
      it "runs the cask lifecycle for #{selection.join(" ")} without running the bottle stages" do
        ENV.delete("GITHUB_ACTIONS")
        args = described_class.new(%w[--dry-run --junit --added-casks=local-caffeine] + selection).args
        mktmpdir.cd do
          expect { Homebrew::TestBot::TestRunner.run!(CoreCaskTap.instance, git: "git", args:) }
            .to output(/local-caffeine --online --new.*uninstall --cask local-caffeine\nAll steps passed!/m).to_stdout
          report = REXML::Document.new(File.read("brew-test-bot.xml"))
          expect(REXML::XPath.first(report, "//testcase[@name='install --cask local-caffeine']/@time").to_s)
            .to eq("0.0")
        end
      end
    end

    test_each([
      [[], "--online --new"],
      [%w[--skip-new], "--online --strict"],
      [%w[--skip-new --skip-new-strict], "--online"],
      [%w[--skip-online-checks], "--strict"],
    ]) do |switches, expected|
      it "audits the selected new cask with #{expected} without detecting packages again" do
        args = described_class.new(%w[--only-casks --dry-run --testing-casks=local-caffeine,local-transmission-zip
                                      --added-casks=local-caffeine --skip-install] + switches).args
        expect(Homebrew::TestBot::PackagesDetect).not_to receive(:new)
        mktmpdir.cd do
          changed = "audit --cask local-transmission-zip"
          changed += " --online" unless switches.include?("--skip-online-checks")
          expect { Homebrew::TestBot::TestRunner.run!(nil, git: "git", args:) }
            .to output(/local-caffeine #{expected}\n.*#{changed}\n/m).to_stdout
        end
      end
    end
  end
end
