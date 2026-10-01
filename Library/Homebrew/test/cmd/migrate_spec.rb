# typed: strict
# frozen_string_literal: true

require "cmd/migrate"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::Migrate do
  it_behaves_like "parseable arguments"

  it "migrates a renamed Formula and Cask", :cask, :integration_test, :no_api do
    old_formula_path = setup_test_formula "testball1", tab_attributes: { installed_on_request: true }
    setup_test_formula "testball2"
    Keg.new(::Formula["testball1"].prefix).link
    old_formula_path.unlink
    (CoreTap.instance.path/"formula_renames.json").write(
      JSON.pretty_generate("testball1" => "testball2"),
    )
    CoreTap.instance.clear_cache

    expect { brew "migrate", "testball1", "HOMEBREW_TEST_GENERIC_OS" => "1" }
      .to output(/Migrating formula testball1 to testball2/).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success

    cask = Cask::CaskLoader.load("local-caffeine")
    InstallHelper.stub_cask_installation(cask)
    sourcefile_path = cask.sourcefile_path
    raise "Cask sourcefile path is unavailable" if sourcefile_path.nil?

    sourcefile_path.unlink
    (CoreCaskTap.instance.path/"cask_renames.json").write(
      JSON.pretty_generate("local-caffeine" => "local-transmission-zip"),
    )
    CoreCaskTap.instance.clear_cache

    expect { brew "migrate", "--cask", "--dry-run", cask.token }
      .to output(/Would migrate cask local-caffeine to local-transmission-zip/).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
    expect(HOMEBREW_CELLAR/"testball1").to be_a_symlink
    expect((HOMEBREW_CELLAR/"testball1").realpath).to eq(HOMEBREW_CELLAR/"testball2")
  end
end
