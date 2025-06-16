# frozen_string_literal: true

require "cmd/autoremove"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::Autoremove do
  it_behaves_like "parseable arguments"

  describe "integration test" do
    let(:requested_formula) { Formula["testball1"] }
    let(:unused_formula) { Formula["testball2"] }

    before do
      # Make testball1 poured from a bottle
      install_test_formula "testball1"
      tab = Tab.for_name("testball1")
      tab.poured_from_bottle = true
      tab.write

      # Make testball2 poured from a bottle and an unused dependency
      install_test_formula "testball2"
      tab = Tab.for_name("testball2")
      tab.installed_on_request = false
      tab.installed_as_dependency = true
      tab.poured_from_bottle = true
      tab.write
    end

    it "only removes unused dependencies", :integration_test do
      expect(requested_formula.any_version_installed?).to be true
      expect(unused_formula.any_version_installed?).to be true

      # When there are unused dependencies
      expect { brew "autoremove" }
        .to be_a_success
        .and output(/Autoremoving/).to_stdout
        .and not_to_output.to_stderr

      expect(requested_formula.any_version_installed?).to be true
      expect(unused_formula.any_version_installed?).to be false
    end
  end
end
