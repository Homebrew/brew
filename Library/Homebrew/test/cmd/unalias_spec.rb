# typed: strict
# frozen_string_literal: true

require "cmd/unalias"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::Unalias do
  it_behaves_like "parseable arguments"

  it "unsets an alias", :integration_test do
    (HOMEBREW_PREFIX/"bin").mkpath
    Homebrew::Aliases.init

    expect { Homebrew::Aliases.add("foo", "bar") }
      .to not_to_output.to_stdout
      .and not_to_output.to_stderr
    expect { Homebrew::Aliases.show }
      .to output(/brew alias foo='bar'/).to_stdout
      .and not_to_output.to_stderr

    expect { brew "unalias", "foo" }
      .to not_to_output.to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
    expect { Homebrew::Aliases.show }
      .to not_to_output.to_stdout
      .and not_to_output.to_stderr
  end
end
