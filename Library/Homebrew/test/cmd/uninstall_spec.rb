# frozen_string_literal: true

require "cmd/uninstall"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::UninstallCmd do
  it_behaves_like "parseable arguments"

  it "uninstalls a given Formula", :integration_test do
    setup_test_formula "testball", tab_attributes: { installed_on_request: true }

    expect(HOMEBREW_CELLAR/"testball").to exist
    expect { brew "uninstall", "--force", "testball" }
      .to output(/Uninstalling testball/).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
    expect(HOMEBREW_CELLAR/"testball").not_to exist
  end
end
