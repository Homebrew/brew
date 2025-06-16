# frozen_string_literal: true

require "cmd/tab"
require "cmd/shared_examples/args_parse"
require "tab"

RSpec.describe Homebrew::Cmd::TabCmd do
  def installed_on_request?(formula)
    # `brew` subprocesses can change the tab, invalidating the cached values.
    Tab.clear_cache
    Tab.for_formula(formula).installed_on_request
  end

  it_behaves_like "parseable arguments"

  it "marks or unmarks a formula as installed on request", :integration_test do
    setup_test_formula "foo",
                       tab_attributes: { "installed_on_request" => false }
    foo = Formula["foo"]

    expect { brew "tab", "--installed-on-request", "foo" }
      .to be_a_success
      .and output(/foo is now marked as installed on request/).to_stdout
      .and not_to_output.to_stderr
    expect(installed_on_request?(foo)).to be true

    expect { brew "tab", "--no-installed-on-request", "foo" }
      .to be_a_success
      .and output(/foo is now marked as not installed on request/).to_stdout
      .and not_to_output.to_stderr
    expect(installed_on_request?(foo)).to be false
  end
end
