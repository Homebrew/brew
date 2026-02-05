# frozen_string_literal: true

RSpec.describe "brew casks", type: :system do
  it "prints all installed Casks", :integration_test do
    expect { brew_sh "casks" }
      .to be_a_success
      .and not_to_output.to_stderr
  end
end
