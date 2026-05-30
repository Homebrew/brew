# typed: false
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "cmd/trust"
require "trust"

RSpec.describe Homebrew::Cmd::Trust do
  it_behaves_like "parseable arguments"

  it "notes official taps are always trusted", :integration_test do
    expect { brew "trust", "homebrew/core" }
      .to output("Official tap homebrew/core is always trusted.\n").to_stdout
      .and be_a_success

    expect(Homebrew::Trust.trusted?(:tap, "homebrew/core")).to be(false)
  end

  it "trusts a command with the plural switch alias" do
    expect { Homebrew::Cmd::Trust.new(["--commands", "thirdparty/foo/hello"]).run }
      .to output("Trusted command: thirdparty/foo/hello\n").to_stdout

    expect(Homebrew::Trust.trusted?(:command, "thirdparty/foo/hello")).to be(true)
  ensure
    Homebrew::Trust.clear!(:command)
  end
end
