# frozen_string_literal: true

require "cmd/shared_examples/args_parse"

describe "brew list" do
  let(:formulae) { %w[bar foo qux] }

  it_behaves_like "parseable arguments"

  it "prints all installed Formulae", :integration_test do
    formulae.each do |f|
      (HOMEBREW_CELLAR/f/"1.0/somedir").mkpath
    end

    expect { brew "list", "--formula" }
      .to output("#{formulae.join("\n")}\n").to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end
end
