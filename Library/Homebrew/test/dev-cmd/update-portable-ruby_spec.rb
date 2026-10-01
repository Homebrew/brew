# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/update-portable-ruby"

RSpec.describe Homebrew::DevCmd::UpdatePortableRuby do
  it_behaves_like "parseable arguments"

  it "prints the target package version without updating portable Ruby" do
    formula = instance_double(Formula, pkg_version: PkgVersion.parse("4.0.6_2"))
    allow(Formulary).to receive(:factory).with("portable-ruby").and_return(formula)

    expect { described_class.new(["--print-target-version"]).run }
      .to output("4.0.6_2\n").to_stdout
  end
end
