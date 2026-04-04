# typed: false
# frozen_string_literal: true

require "cmd/missing"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::Missing do
  it_behaves_like "parseable arguments"

  it "prints missing dependencies", :integration_test, :no_api do
    setup_test_formula "foo"
    setup_test_formula "bar"

    (HOMEBREW_CELLAR/"bar/1.0").mkpath
    (HOMEBREW_CELLAR/"bar/1.0/INSTALL_RECEIPT.json").write(
      JSON.generate({
        "homebrew_version"     => "1.1.6",
        "runtime_dependencies" => [{ "full_name" => "foo", "version" => "1.0" }],
      }),
    )

    expect { brew "missing" }
      .to output("foo\n").to_stdout
      .and not_to_output.to_stderr
      .and be_a_failure
  end

  it "does not report a renamed formula as missing when a stale tab records its old name",
     :integration_test, :no_api do
    # Simulate: "foo" was renamed to "newname"; "bar" depends on it but its tab still records
    # the old dependency name (not yet regenerated after rename).
    setup_test_formula "newname"
    setup_test_formula "bar", tab_attributes: {
      runtime_dependencies: [{ "full_name" => "homebrew/core/foo", "version" => "1.0" }],
    }
    (HOMEBREW_CELLAR/"newname/1.0/somedir").mkpath
    (HOMEBREW_CELLAR/"bar/1.0/somedir").mkpath

    CoreTap.instance.path.join("formula_renames.json").write('{"foo":"newname"}')
    CoreTap.instance.clear_cache

    expect { brew "missing" }
      .to not_to_output.to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end
end
