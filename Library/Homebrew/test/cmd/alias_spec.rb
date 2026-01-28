# frozen_string_literal: true

require "cmd/alias"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::Alias do
  it_behaves_like "parseable arguments"

  it "sets an alias", :integration_test do
    expect { brew "alias", "foo-test=bar" }
      .to not_to_output.to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
    expect { brew "alias" }
      .to output(/brew alias foo-test='bar'/).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end
end
