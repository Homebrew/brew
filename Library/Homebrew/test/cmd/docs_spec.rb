# frozen_string_literal: true

describe "brew docs" do
  it "opens the docs page", :integration_test do
    expect { brew "docs", "HOMEBREW_BROWSER" => "echo" }
      .to output("https://docs.brew.sh\n").to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end
end
