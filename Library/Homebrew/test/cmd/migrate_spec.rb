# frozen_string_literal: true

require "cmd/shared_examples/args_parse"

describe "brew migrate" do
  it_behaves_like "parseable arguments"

  it "migrates a renamed Formula", :integration_test do
    setup_test_formula "testball1"
    setup_test_formula "testball2"
    install_and_rename_coretap_formula "testball1", "testball2"

    expect { brew "migrate", "testball1" }
      .to output(/Migrating formula testball1 to testball2/).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end
end
