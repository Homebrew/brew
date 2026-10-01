# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/formula-python-resources"

RSpec.describe Homebrew::DevCmd::FormulaPythonResources do
  it_behaves_like "parseable arguments"

  it "outputs Python resources for formulae in the requested tap" do
    tap = instance_double(Tap, name: "homebrew/core")
    python_resource = instance_double(
      Resource,
      name: "example-dependency",
      url:  "https://files.pythonhosted.org/packages/example_dependency-1.2.3.tar.gz",
    )
    other_resource = instance_double(
      Resource,
      name: "other-dependency",
      url:  "not a valid URI",
    )
    urlless_resource = instance_double(
      Resource,
      name: "urlless-dependency",
      url:  nil,
    )
    formula = instance_double(
      Formula,
      name:        "example",
      tap:,
      deprecated?: false,
      disabled?:   false,
      resources:   [python_resource, other_resource, urlless_resource],
    )
    command = described_class.new(["--all", "--tap=homebrew/core"])
    allow(Formula).to receive(:all).and_return([formula])
    stdout = StringIO.new
    allow(command).to receive(:puts) { |value| stdout.puts(value) }

    command.run
    output = JSON.parse(stdout.string)

    expect(output).to eq([
      {
        "name"       => "example",
        "tap"        => "homebrew/core",
        "deprecated" => false,
        "disabled"   => false,
        "resources"  => [
          {
            "name" => "example-dependency",
            "url"  => "https://files.pythonhosted.org/packages/example_dependency-1.2.3.tar.gz",
          },
        ],
      },
    ])
  end
end
