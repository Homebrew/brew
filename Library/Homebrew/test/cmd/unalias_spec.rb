# frozen_string_literal: true

require "cmd/unalias"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::Unalias do
  it_behaves_like "parseable arguments"

  it "unsets an alias", :integration_test do
    expect { brew "alias", "foo=bar" }
      .to not_to_output.to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
    expect { brew "alias" }
      .to output(/brew alias foo='bar'/).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
    expect { brew "unalias", "foo" }
      .to not_to_output.to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
    expect { brew "alias" }
      .to not_to_output.to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end
end
