# frozen_string_literal: true

require "cmd/uninstall"

require "cmd/shared_examples/args_parse"

describe "brew uninstall" do
  it_behaves_like "parseable arguments"

  it "uninstalls a given Formula", :integration_test do
    install_test_formula "testball"

    expect { brew "uninstall", "--force", "testball" }
      .to output(/Uninstalling testball/).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end
end
