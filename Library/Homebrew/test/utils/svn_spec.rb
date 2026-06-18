# typed: true
# frozen_string_literal: true

require "utils/svn"

RSpec.describe Utils::Svn do
  def svn_result(stdout = "", success:, stderr: "")
    status = instance_double(Process::Status, success?: success)
    instance_double(SystemCommand::Result, to_a: [stdout, stderr, status])
  end

  def clear_version_cache
    return unless described_class.instance_variable_defined?(:@version)

    described_class.send(:remove_instance_variable,
                         :@version)
  end

  before do
    clear_version_cache
  end

  describe "::available?" do
    it "returns true when svn version is present" do
      allow(described_class).to receive(:version).and_return("1.14.5")
      expect(described_class).to be_available
    end

    it "returns false when svn version is missing" do
      allow(described_class).to receive(:version).and_return(nil)
      expect(described_class).not_to be_available
    end
  end

  describe "::version" do
    it "returns svn version or nil" do
      expect(described_class).to receive(:system_command)
        .with(HOMEBREW_SHIMS_PATH/"shared/svn", args: ["--version"], print_stderr: false)
        .and_return(svn_result("svn, version 1.14.5\n", success: true))

      expect(described_class.version).to eq("1.14.5")

      clear_version_cache
      expect(described_class).to receive(:system_command)
        .with(HOMEBREW_SHIMS_PATH/"shared/svn", args: ["--version"], print_stderr: false)
        .and_return(svn_result("", success: false))

      expect(described_class.version).to be_nil
    end
  end

  describe "::remote_exists?" do
    it "returns true when svn is not available" do
      allow(described_class).to receive(:available?).and_return(false)
      expect(described_class).to be_remote_exists("blah")
    end

    context "when svn is available" do
      before do
        allow(described_class).to receive(:available?).and_return(true)
      end

      it "returns false when remote does not exist" do
        expect(described_class).to receive(:system_command)
          .with("svn", args: ["ls", "blah", "--depth", "empty"], print_stderr: false)
          .and_return(svn_result(success: false))

        expect(described_class).not_to be_remote_exists("blah")
      end

      it "returns true when remote exists", :needs_network, :needs_svn do
        expect(described_class).to be_remote_exists("https://svn.code.sf.net/p/ctags/code/trunk")
      end
    end
  end
end
