# frozen_string_literal: true

require "cmd/services"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::Services, :needs_daemon_manager do
  it_behaves_like "parseable arguments"

  it "allows controlling services", :integration_test do
    expect { brew "services", "list" }
      .to not_to_output.to_stderr
      .and not_to_output.to_stdout
      .and be_a_success
  end
end
