# frozen_string_literal: true

require "cmd/list"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::List do
  let(:formulae) { %w[bar foo qux] }

  it_behaves_like "parseable arguments"

  it "prints all installed formulae", :integration_test do
    formulae.each do |f|
      (HOMEBREW_CELLAR/f/"1.0/somedir").mkpath
    end

    expect { brew "list", "--formula" }
      .to output("#{formulae.join("\n")}\n").to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end

  it "prints all installed formulae and casks", :integration_test do
    expect { brew_sh "list" }
      .to be_a_success
      .and not_to_output.to_stderr
  end
end
