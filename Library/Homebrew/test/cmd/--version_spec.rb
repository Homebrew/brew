# frozen_string_literal: true

RSpec.describe "brew --version", type: :system do
  it "prints the Homebrew's version", :integration_test do
    expect { brew_sh "--version" }
      .to output(/^Homebrew #{Regexp.escape(HOMEBREW_VERSION)}\n/o).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end
end
