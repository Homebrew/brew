# frozen_string_literal: true

require "cmd/shared_examples/args_parse"

describe "brew --cellar" do
  it_behaves_like "parseable arguments"

  it "prints Homebrew's Cellar", :integration_test do
    expect { brew_sh "--cellar" }
      .to output("#{ENV.fetch("HOMEBREW_CELLAR")}\n").to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end

  it "prints the Cellar for a Formula", :integration_test do
    expect { brew "--cellar", testball }
      .to output(%r{#{HOMEBREW_CELLAR}/testball}o).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end
end
