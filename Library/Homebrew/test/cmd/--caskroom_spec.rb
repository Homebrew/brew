# typed: strict
# frozen_string_literal: true

require "cmd/--caskroom"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::Caskroom do
  it_behaves_like "parseable arguments"

  it "prints Homebrew's Caskroom", :integration_test do
    expect { brew_sh "--caskroom" }
      .to output("#{ENV.fetch("HOMEBREW_PREFIX")}/Caskroom\n").to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end

  it "prints the Caskroom for Casks" do
    cmd = described_class.new(%w[local-transmission local-caffeine])
    allow(cmd.args.named).to receive(:to_casks).and_return([
      instance_double(Cask::Cask, token: "local-transmission"),
      instance_double(Cask::Cask, token: "local-caffeine"),
    ])

    expect { cmd.run }
      .to output("#{HOMEBREW_PREFIX/"Caskroom"/"local-transmission"}\n" \
                 "#{HOMEBREW_PREFIX/"Caskroom"/"local-caffeine"}\n").to_stdout
      .and not_to_output.to_stderr
  end
end
