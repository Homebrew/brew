# frozen_string_literal: true

require "linux_runner_spec"

RSpec.describe LinuxRunnerSpec do
  let(:spec) do
    described_class.new(
      name:      "Linux",
      runner:    "ubuntu-latest",
      container: { image: "ghcr.io/homebrew/ubuntu22.04:master", options: "--user=linuxbrew" },
      workdir:   "/github/home",
      timeout:   360,
      cleanup:   false,
    )
  end

  it "has immutable attributes" do
    [:name, :runner, :container, :workdir, :timeout, :cleanup].each do |attribute|
      expect(spec.respond_to?(:"#{attribute}=")).to be(false)
    end
  end

  describe "#to_h" do
    it "returns an object that responds to `#to_json`" do
      expect(spec.to_h.respond_to?(:to_json)).to be(true)
    end
  end
end
