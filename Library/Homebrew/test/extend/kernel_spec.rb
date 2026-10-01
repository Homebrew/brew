# typed: true
# frozen_string_literal: true

require "utils/shell"

RSpec.describe Kernel do
  let(:dir) { mktmpdir }

  describe "#which" do
    let(:cmd) { dir/"foo" }

    before { FileUtils.touch cmd }

    it "returns the first executable that is found" do
      cmd.chmod 0744
      expect(which(File.basename(cmd), File.dirname(cmd))).to eq(cmd)
    end

    it "skips non-executables" do
      expect(which(File.basename(cmd), File.dirname(cmd))).to be_nil
    end

    it "skips malformed path and doesn't fail" do
      # 'which' should not fail if a path is malformed
      # see https://github.com/Homebrew/legacy-homebrew/issues/32789 for an example
      cmd.chmod 0744

      # ~~ will fail because ~foo resolves to foo's home and there is no '~' user
      path = ["~~", File.dirname(cmd)].join(File::PATH_SEPARATOR)
      expect(which(File.basename(cmd), path)).to eq(cmd)
    end
  end

  describe "#with_env" do
    it "sets environment variables within the block" do
      expect(ENV.fetch("PATH")).not_to eq("/bin")
      with_env(PATH: "/bin") do
        expect(ENV.fetch("PATH", nil)).to eq("/bin")
      end
    end

    it "restores ENV after the block" do
      with_env(PATH: "/bin") do
        expect(ENV.fetch("PATH", nil)).to eq("/bin")
      end
      path = ENV.fetch("PATH", nil)
      expect(path).not_to be_nil
      expect(path).not_to eq("/bin")
    end

    it "restores ENV if an exception is raised" do
      expect do
        with_env(PATH: "/bin") do
          raise StandardError, "boom"
        end
      end.to raise_error(StandardError)

      path = ENV.fetch("PATH", nil)
      expect(path).not_to be_nil
      expect(path).not_to eq("/bin")
    end
  end
end
