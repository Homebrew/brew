# typed: false
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "cmd/untrust"
require "trust"

RSpec.describe Homebrew::Cmd::Untrust do
  it_behaves_like "parseable arguments"

  it "untrusts a given tap", :integration_test do
    Homebrew::Trust.trust!(:tap, "thirdparty/foo")

    expect { brew "untrust", "thirdparty/foo" }
      .to output(%r{Untrusted tap: thirdparty/foo}).to_stdout
      .and be_a_success

    expect(Homebrew::Trust.trusted?(:tap, "thirdparty/foo")).to be(false)
  ensure
    Homebrew::Trust.clear!(:tap)
  end

  it "notes official taps are always trusted" do
    expect { Homebrew::Cmd::Untrust.new(["homebrew/core"]).run }
      .to output("Official tap homebrew/core is always trusted.\n").to_stdout
  end

  it "untrusts a command with the plural switch alias" do
    Homebrew::Trust.trust!(:command, "thirdparty/foo/hello")

    expect { Homebrew::Cmd::Untrust.new(["--commands", "thirdparty/foo/hello"]).run }
      .to output("Untrusted command: thirdparty/foo/hello\n").to_stdout

    expect(Homebrew::Trust.trusted?(:command, "thirdparty/foo/hello")).to be(false)
  ensure
    Homebrew::Trust.clear!(:command)
  end
end
