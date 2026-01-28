# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/linkage"

RSpec.describe Homebrew::DevCmd::Linkage do
  it_behaves_like "parseable arguments"

  it "works when no arguments are provided", :integration_test do
    setup_test_formula "testball"
    (HOMEBREW_CELLAR/"testball/0.0.1/foo").mkpath

    expect { brew "linkage" }
      .to be_a_success
      .and not_to_output.to_stdout
      .and not_to_output.to_stderr
  end

  it "accepts no_linkage dependency tag", :integration_test do
    setup_test_formula "testball" do
      url "file://#{TEST_FIXTURE_DIR}/tarballs/testball-0.1.tbz"
      sha256 TESTBALL_SHA256

      depends_on "foo" => :no_linkage
    end

    expect { brew "info", "testball" }
      .to be_a_success
  end
end
