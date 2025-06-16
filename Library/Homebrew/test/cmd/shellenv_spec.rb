# frozen_string_literal: true

RSpec.describe "brew shellenv", type: :system do
  it "prints export statements", :integration_test do
    expect { brew_sh "shellenv" }
      .to output(/.*/).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end
end
