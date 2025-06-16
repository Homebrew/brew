# frozen_string_literal: true

require "language/node"

RSpec.describe Language::Node do
  let(:npm_pack_cmd) { ["npm", "pack", "--ignore-scripts"] }

  describe "#setup_npm_environment" do
    it "calls prepend_path when node formula exists only during the first call" do
      node = formula "node" do
        url "node-test-v1.0"
      end
      stub_formula_loader(node)
      without_partial_double_verification do
        expect(ENV).to receive(:prepend_path)
      end
      described_class.instance_variable_set(:@env_set, false)
      described_class.setup_npm_environment

      expect(described_class.instance_variable_get(:@env_set)).to be(true)
      without_partial_double_verification do
        expect(ENV).not_to receive(:prepend_path)
      end
      described_class.setup_npm_environment
    end

    it "does not call prepend_path when node formula does not exist" do
      without_partial_double_verification do
        expect(ENV).not_to receive(:prepend_path)
      end
      described_class.setup_npm_environment
    end
  end

  describe "#std_pack_for_installation" do
    it "removes prepare and prepack scripts" do
      mktmpdir.cd do
        path = Pathname("package.json")
        path.atomic_write("{\"scripts\":{\"prepare\": \"ls\", \"prepack\": \"ls\", \"test\": \"ls\"}}")
        allow(Utils).to receive(:popen_read).with(*npm_pack_cmd).and_return(`echo pack.tgz`)
        described_class.pack_for_installation
        expect(path.read).not_to include("prepare")
        expect(path.read).not_to include("prepack")
        expect(path.read).to include("test")
      end
    end
  end

  describe "#std_npm_install_args" do
    npm_install_arg = Pathname("libexec")

    it "raises error with non zero exitstatus" do
      allow(Utils).to receive(:popen_read).with(*npm_pack_cmd).and_return(`false`)
      expect { described_class.std_npm_install_args(npm_install_arg) }.to raise_error("npm failed to pack #{Dir.pwd}")
    end

    it "raises error with empty npm pack output" do
      allow(Utils).to receive(:popen_read).with(*npm_pack_cmd).and_return(`true`)
      expect { described_class.std_npm_install_args(npm_install_arg) }.to raise_error("npm failed to pack #{Dir.pwd}")
    end

    it "does not raise error with a zero exitstatus" do
      allow(Utils).to receive(:popen_read).with(*npm_pack_cmd).and_return(`echo pack.tgz`)
      resp = described_class.std_npm_install_args(npm_install_arg)
      expect(resp).to include("--prefix=#{npm_install_arg}", "#{Dir.pwd}/pack.tgz")
    end
  end

  specify "#local_npm_install_args" do
    resp = described_class.local_npm_install_args
    expect(resp).to include("-ddd", "--build-from-source", "--cache=#{HOMEBREW_CACHE}/npm_cache")
  end
end
