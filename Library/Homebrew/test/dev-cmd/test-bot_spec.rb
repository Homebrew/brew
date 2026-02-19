# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/test-bot"

RSpec.describe Homebrew::Cmd::TestBotCmd do
  it_behaves_like "parseable arguments"

  it "rejects dependent shard flags without --only-formulae-dependents", :integration_test do
    expect { brew "test-bot", "--dependent-shard-count=2", "--dependent-shard-index=1" }
      .to output(/(?:can only be used with|cannot be passed without) `--only-formulae-dependents`/).to_stderr
      .and be_a_failure
  end

  it "requires dependent shard flags to be provided together", :integration_test do
    expect { brew "test-bot", "--only-formulae-dependents", "--dependent-shard-count=2" }
      .to output(/must be provided together/).to_stderr
      .and be_a_failure
  end

  it "validates dependent shard index range", :integration_test do
    expect { brew "test-bot", "--only-formulae-dependents", "--dependent-shard-count=2", "--dependent-shard-index=3" }
      .to output(/must be between 1 and `--dependent-shard-count`/).to_stderr
      .and be_a_failure
  end
end
