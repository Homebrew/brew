# frozen_string_literal: true

require "cmd/shared_examples/args_parse"

describe "brew autoremove" do
  it_behaves_like "parseable arguments"

  describe "integration test" do
    let(:requested_formula) { Formula["testball1"] }
    let(:unused_formula) { Formula["testball2"] }

    before do
      install_test_formula "testball1"
      install_test_formula "testball2"

      # Make testball2 an unused dependency
      tab = Tab.for_name("testball2")
      tab.installed_on_request = false
      tab.installed_as_dependency = true
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
