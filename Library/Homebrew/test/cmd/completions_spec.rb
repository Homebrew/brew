# frozen_string_literal: true

require "cmd/shared_examples/args_parse"

describe "brew completions" do
  it_behaves_like "parseable arguments"

  it "runs the status subcommand correctly", :integration_test do
    HOMEBREW_REPOSITORY.cd do
      system "git", "init"
    end

    brew "completions", "link"
    expect { brew "completions" }
      .to output(/Completions are linked/).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end
end
