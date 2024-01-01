# frozen_string_literal: true

require "cmd/shared_examples/args_parse"

describe "brew edit" do
  it_behaves_like "parseable arguments"

  it "opens a given Formula in an editor", :integration_test do
    HOMEBREW_REPOSITORY.cd do
      system "git", "init"
    end

    setup_test_formula "testball"

    expect { brew "edit", "testball", "HOMEBREW_EDITOR" => "/bin/cat", "HOMEBREW_NO_ENV_HINTS" => "1" }
      .to output(/# something here/).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end
end
