# typed: strict
# frozen_string_literal: true

require "development_tools"

RSpec.describe DevelopmentTools, :needs_macos do
  describe ".locate" do
    before do
      described_class.remove_instance_variable(:@locate) if described_class.instance_variable_defined?(:@locate)
    end

    it "doesn't call xcrun when Xcode and the CLT are not installed" do
      allow(File).to receive(:executable?).and_call_original
      allow(File).to receive(:executable?).with("/usr/bin/missing-tool").and_return(false)
      allow(OS::Mac::Xcode).to receive(:installed?).and_return(false)
      allow(OS::Mac::CLT).to receive(:installed?).and_return(false)

      expect(Utils).not_to receive(:popen_read)

      expect(described_class.locate("missing-tool")).to be_nil
    end

    it "uses xcrun when developer tools are installed" do
      allow(File).to receive(:executable?).and_call_original
      allow(File).to receive(:executable?).with("/usr/bin/xcode-tool").and_return(false)
      allow(File).to receive(:executable?).with("/Xcode/usr/bin/xcode-tool").and_return(true)
      allow(OS::Mac::Xcode).to receive(:installed?).and_return(true)
      allow(OS::Mac::CLT).to receive(:installed?).and_return(false)
      expect(Utils).to receive(:popen_read)
        .with("/usr/bin/xcrun", "-no-cache", "-find", "xcode-tool", err: :close)
        .and_return("/Xcode/usr/bin/xcode-tool\n")

      expect(described_class.locate("xcode-tool")).to eq(Pathname("/Xcode/usr/bin/xcode-tool"))
    end
  end
end
