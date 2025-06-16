# frozen_string_literal: true

RSpec.describe "brew formulae", type: :system do
  it "prints all installed Formulae", :integration_test do
    expect { brew_sh "formulae" }
      .to be_a_success
      .and not_to_output.to_stderr
  end
end
