# frozen_string_literal: true

RSpec.describe "brew --version", type: :system do
  it "prints the DinrusBrew's version", :integration_test do
    expect { brew_sh "--version" }
      .to output(/^DinrusBrew #{Regexp.escape(DINRUSBREW_VERSION)}\n/o).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end
end
