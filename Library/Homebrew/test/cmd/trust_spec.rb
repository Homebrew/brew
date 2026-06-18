# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "cmd/trust"
require "trust"

RSpec.describe Homebrew::Cmd::Trust, :trust_store do
  RSpec::Matchers.define :match_json do |expected|
    T.bind(self, T.class_of(RSpec::Matchers::DSL::Matcher))
    match do |actual|
      JSON.parse(actual) == expected
    rescue JSON::ParserError
      false
    end
  end

  it_behaves_like "parseable arguments"

  it "notes official taps are always trusted", :integration_test do
    expect { brew "trust", "homebrew/core" }
      .to output("Official tap homebrew/core is always trusted.\n").to_stdout
      .and be_a_success

    expect(Homebrew::Trust.trusted?(:tap, "homebrew/core")).to be(false)
  end

  it "trusts a command with the plural switch alias" do
    expect { described_class.new(["--commands", "thirdparty/foo/hello"]).run }
      .to output("Trusted command: thirdparty/foo/hello\n").to_stdout

    expect(Homebrew::Trust.trusted?(:command, "thirdparty/foo/hello")).to be(true)
  ensure
    Homebrew::Trust.clear!(:command)
  end

  context "with a custom-remote tap" do
    before do
      tap = Tap.fetch("thirdparty", "custom")
      tap.path.mkpath
      system "git", "-C", tap.path.to_s, "init"
      system "git", "-C", tap.path.to_s, "remote", "add", "origin", "https://gitlab.com/other/repo"
    end

    after do
      Homebrew::Trust.clear!(:tap)
      FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"thirdparty"
    end

    it "trusts the whole tap by its remote URL" do
      expect { described_class.new(["--tap", "thirdparty/custom"]).run }
        .to output("Trusted tap: https://gitlab.com/other/repo\n").to_stdout
      expect(Homebrew::Trust.trusted_entries(:tap)).to contain_exactly("https://gitlab.com/other/repo")
    end

    it "trusts an individual formula by its remote-qualified entry" do
      expect { described_class.new(["--formula", "thirdparty/custom/bar"]).run }
        .to output("Trusted formula: https://gitlab.com/other/repo/bar\n").to_stdout
      expect(Homebrew::Trust.trusted_entries(:formula)).to contain_exactly("https://gitlab.com/other/repo/bar")
    end
  end

  it "trusts a not-yet-installed tap directly by its non-GitHub remote URL" do
    expect { described_class.new(["--tap", "https://gitlab.com/absent/repo"]).run }
      .to output("Trusted tap: https://gitlab.com/absent/repo\n").to_stdout
    expect(Homebrew::Trust.trusted_entries(:tap)).to contain_exactly("https://gitlab.com/absent/repo")
  ensure
    Homebrew::Trust.clear!(:tap)
  end

  it "canonicalises a GitHub default-remote URL to the tap name" do
    expect { described_class.new(["--tap", "https://github.com/thirdparty/homebrew-foo"]).run }
      .to output("Trusted tap: thirdparty/foo\n").to_stdout
    expect(Homebrew::Trust.trusted_entries(:tap)).to contain_exactly("thirdparty/foo")
  ensure
    Homebrew::Trust.clear!(:tap)
  end

  it "rejects a bare @-string instead of trusting it as a tap" do
    expect { described_class.new(["foo@bar"]).run }
      .to raise_error(UsageError, /fully-qualified/)
    expect(Homebrew::Trust.trusted_entries(:tap)).to be_empty
  ensure
    Homebrew::Trust.clear!(:tap)
  end

  it "lists trusted entries with no arguments" do
    allow(Homebrew::Trust).to receive(:trusted_entries).with(:tap).and_return(["thirdparty/foo"])
    allow(Homebrew::Trust).to receive(:trusted_entries).with(:formula).and_return(["thirdparty/foo/bar"])
    allow(Homebrew::Trust).to receive(:trusted_entries).with(:cask).and_return([])
    allow(Homebrew::Trust).to receive(:trusted_entries).with(:command).and_return([])

    expect { described_class.new([]).run }
      .to output(<<~EOS).to_stdout
        All official taps and commands are trusted.
        Trusted taps:
          thirdparty/foo
        Trusted formulae:
          thirdparty/foo/bar
      EOS
  end

  it "lists trusted entries as json with no arguments" do
    allow(Homebrew::Trust).to receive(:trusted_entries).with(:tap).and_return(["thirdparty/foo"])
    allow(Homebrew::Trust).to receive(:trusted_entries).with(:formula).and_return(["thirdparty/foo/bar"])
    allow(Homebrew::Trust).to receive(:trusted_entries).with(:cask).and_return([])
    allow(Homebrew::Trust).to receive(:trusted_entries).with(:command).and_return([])

    expect { described_class.new(["--json=v1"]).run }
      .to output(
        match_json(
          {
            "taps"     => ["thirdparty/foo"],
            "formulae" => ["thirdparty/foo/bar"],
            "casks"    => [],
            "commands" => [],
          },
        ),
      ).to_stdout
  end

  it "lists trusted entries as a json array for a selected type" do
    allow(Homebrew::Trust).to receive(:trusted_entries).with(:formula).and_return(["thirdparty/foo/bar"])

    expect { described_class.new(["--json=v1", "--formula"]).run }
      .to output(match_json(["thirdparty/foo/bar"])).to_stdout
  end

  it "rejects json output with named arguments" do
    expect { described_class.new(["--json=v1", "thirdparty/foo"]).run }
      .to raise_error(UsageError, /requires no named arguments/)
  end

  it "rejects json without an explicit version" do
    expect { described_class.new(["--json"]).run }
      .to raise_error(OptionParser::MissingArgument, /--json/)
  end
end
