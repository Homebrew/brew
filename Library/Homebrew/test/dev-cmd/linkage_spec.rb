# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/linkage"

RSpec.describe Homebrew::DevCmd::Linkage do
  it_behaves_like "parseable arguments"

  it "works when no arguments are provided", :integration_test do
    expect { brew "linkage" }
      .to be_a_success
      .and not_to_output.to_stdout
      .and not_to_output.to_stderr
  end

  it "accepts no_linkage dependency tag" do
    expect(formula("testball") do
      T.bind(self, T.class_of(Formula))
      url "file://#{TEST_FIXTURE_DIR}/tarballs/testball-0.1.tbz"
      sha256 TESTBALL_SHA256

      depends_on "foo" => :no_linkage
    end.deps.first).to be_no_linkage
  end
end
