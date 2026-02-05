# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "cmd/upgrade"
require "cmd/shared_examples/reinstall_pkgconf_if_needed"

RSpec.describe Homebrew::Cmd::UpgradeCmd do
  include FileUtils

  it_behaves_like "parseable arguments"

  it "upgrades a Formula", :integration_test do
    formula_name = "testball_bottle"
    formula_rack = HOMEBREW_CELLAR/formula_name

    setup_test_formula formula_name

    (formula_rack/"0.0.1/foo").mkpath

    expect { brew "upgrade" }.to be_a_success

    expect(formula_rack/"0.1").to be_a_directory
    expect(formula_rack/"0.0.1").not_to exist

    uninstall_test_formula formula_name

    # links newer version when upgrade was interrupted
    (formula_rack/"0.1/foo").mkpath

    expect { brew "upgrade" }.to be_a_success

    expect(formula_rack/"0.1").to be_a_directory
    expect(HOMEBREW_PREFIX/"opt/#{formula_name}").to be_a_symlink
    expect(HOMEBREW_PREFIX/"var/homebrew/linked/#{formula_name}").to be_a_symlink

    uninstall_test_formula formula_name

    # upgrades with asking for user prompts
    (formula_rack/"0.0.1/foo").mkpath

    expect { brew "upgrade", "--ask" }
      .to output(/.*Formula\s*\(1\):\s*#{formula_name}.*/).to_stdout
      .and output(/✔︎.*/m).to_stderr

    expect(formula_rack/"0.1").to be_a_directory
    expect(formula_rack/"0.0.1").not_to exist

    uninstall_test_formula formula_name

    # refuses to upgrade a forbidden formula
    (formula_rack/"0.0.1/foo").mkpath

    expect { brew "upgrade", formula_name, { "HOMEBREW_FORBIDDEN_FORMULAE" => formula_name } }
      .to not_to_output(%r{#{formula_rack}/0\.1}o).to_stdout
      .and output(/#{formula_name} was forbidden/).to_stderr
      .and be_a_failure
    expect(formula_rack/"0.1").not_to exist
  end

  it_behaves_like "reinstall_pkgconf_if_needed"
end
