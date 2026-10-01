# typed: true
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

  def cask_installed_on_request?(cask)
    # `brew` subprocesses can change the tab, invalidating the cached values.
    Cask::Tab.clear_cache
    cask.tab.installed_on_request
  end

  it_behaves_like "parseable arguments"

  it "marks a Formula and Cask as installed on request", :cask, :integration_test do
    setup_test_formula "foo",
                       tab_attributes: { "installed_on_request" => false }
    foo = Formula["foo"]

    cask = Cask::CaskLoader.load(cask_path("local-caffeine"))
    InstallHelper.install_with_caskfile(cask)
    tab_path = cask.metadata_main_container_path/AbstractTab::FILENAME

    expect(tab_path).not_to exist

    expect { brew "tab", "--installed-on-request", "foo", cask.token }
      .to output(/foo is now marked as installed on request.*local-caffeine is now marked as installed on request/m)
      .to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
    expect(installed_on_request?(foo)).to be true
    expect(tab_path).to exist
    expect(cask_installed_on_request?(cask)).to be true
  end

  it "marks or unmarks a Cask as installed on request with a missing tab", :cask do
    cask = Cask::CaskLoader.load(cask_path("local-caffeine"))
    InstallHelper.install_with_caskfile(cask)
    tab_path = cask.metadata_main_container_path/AbstractTab::FILENAME

    expect(tab_path).not_to exist

    cmd = described_class.new(["--installed-on-request", "--cask", cask.token])
    allow(cmd.args.named).to receive(:to_formulae_to_casks).and_return([[], [cask]])
    expect { cmd.run }
      .to output(/local-caffeine is now marked as installed on request/).to_stdout
      .and not_to_output.to_stderr
    expect(tab_path).to exist
    expect(cask_installed_on_request?(cask)).to be true

    tab_path.delete
    Cask::Tab.clear_cache

    cmd = described_class.new(["--no-installed-on-request", "--cask", cask.token])
    allow(cmd.args.named).to receive(:to_formulae_to_casks).and_return([[], [cask]])
    expect { cmd.run }
      .to output(/local-caffeine is already marked as not installed on request/).to_stdout
      .and not_to_output.to_stderr
    expect(tab_path).to exist
    expect(cask_installed_on_request?(cask)).to be false
  end
end
