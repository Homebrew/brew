# frozen_string_literal: true

RSpec.describe "brew setup-ruby", type: :system do
  it "installs and configures Homebrew's Ruby", :integration_test do
    expect { brew_sh "setup-ruby" }
      .to output("").to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end
end
