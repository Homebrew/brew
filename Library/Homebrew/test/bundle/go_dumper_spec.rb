# frozen_string_literal: true

require "bundle"
require "bundle/go_dumper"

RSpec.describe Homebrew::Bundle::GoDumper do
  subject(:dumper) { described_class }

  context "when go is not installed" do
    before do
      described_class.reset!
      allow(Homebrew::Bundle).to receive(:go_installed?).and_return(false)
    end

    it "returns an empty list" do
      expect(dumper.packages).to be_empty
    end

    it "dumps an empty string" do # rubocop:todo RSpec/AggregateExamples
      expect(dumper.dump).to eql("")
    end
  end

  context "when go is installed" do
    before do
      described_class.reset!
      allow(Homebrew::Bundle).to receive(:which_go).and_return(Pathname.new("go"))
    end

    it "returns package list" do
      allow(described_class).to receive(:`).with("go env GOBIN").and_return("")
      allow(described_class).to receive(:`).with("go env GOPATH").and_return("/Users/test/go")
      allow(File).to receive(:directory?).with("/Users/test/go/bin").and_return(true)
      allow(Dir).to receive(:glob).with("/Users/test/go/bin/*").and_return(["/Users/test/go/bin/crush"])
      allow(File).to receive(:executable?).with("/Users/test/go/bin/crush").and_return(true)
      allow(File).to receive(:directory?).with("/Users/test/go/bin/crush").and_return(false)
      allow(described_class).to receive(:`).with("go version -m \"/Users/test/go/bin/crush\" 2>/dev/null")
                                           .and_return("\tpath\tgithub.com/charmbracelet/crush\n")
      expect(dumper.packages).to eql(["github.com/charmbracelet/crush"])
    end

    it "dumps package list" do
      allow(dumper).to receive(:packages).and_return(["github.com/charmbracelet/crush"])
      expect(dumper.dump).to eql('go "github.com/charmbracelet/crush"')
    end
  end
end
