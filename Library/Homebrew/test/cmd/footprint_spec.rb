# typed: false
# frozen_string_literal: true

require "cmd/footprint"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::Footprint do
  it_behaves_like "parseable arguments"

  describe "footprint analysis", :integration_test do
    before do
      setup_test_formula "testball", tab_attributes: {
        installed_on_request: true,
        runtime_dependencies: [{ "full_name" => "testball2", "version" => "0.1" }],
      }

      setup_test_formula "testball2", tab_attributes: {
        installed_on_request: false,
        runtime_dependencies: [],
      }
    end

    it "shows footprint for a named formula" do
      expect { brew "footprint", "testball" }
        .to be_a_success
        .and output(/testball/).to_stdout
    end

    it "shows footprint with --installed" do
      expect { brew "footprint", "--installed" }
        .to be_a_success
        .and output(/testball/).to_stdout
    end

    it "excludes dependencies from --installed by default" do
      expect { brew "footprint", "--installed" }
        .to be_a_success
        .and not_to_output(/testball2/).to_stdout
    end

    it "includes dependencies with --installed --all" do
      expect { brew "footprint", "--installed", "--all" }
        .to be_a_success
        .and output(/testball2/).to_stdout
    end

    it "errors for a formula that is not installed" do
      expect { brew "footprint", "notinstalled" }
        .to be_a_failure
    end
  end
end
