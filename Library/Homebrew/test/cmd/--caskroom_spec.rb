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

  it "prints the Caskroom for Casks", :integration_test do
    expect { brew "--caskroom", cask_path("local-transmission"), cask_path("local-caffeine") }
      .to output("#{HOMEBREW_PREFIX/"Caskroom"/"local-transmission"}\n" \
                 "#{HOMEBREW_PREFIX/"Caskroom"/"local-caffeine\n"}").to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end
end
