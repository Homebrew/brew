# frozen_string_literal: true

require "language/node"
require "utils/shebang"

RSpec.describe Language::Node::Shebang do
  let(:file) { Tempfile.new("node-shebang") }
  let(:f) do
    f = {}

    f[:node18] = formula "node@18" do
      url "https://brew.sh/node-18.0.0.tgz"
    end

    f[:versioned_node_dep] = formula "foo" do
      url "https://brew.sh/foo-1.0.tgz"

      depends_on "node@18"
    end

    f[:no_deps] = formula "foo" do
      url "https://brew.sh/foo-1.0.tgz"
    end

    f[:multiple_deps] = formula "foo" do
      url "https://brew.sh/foo-1.0.tgz"

      depends_on "node"
      depends_on "node@18"
    end

    f
  end

  before do
    file.write <<~EOS
      #!/usr/bin/env node
      a
      b
      c
    EOS
    file.flush
  end

  after { file.unlink }

  describe "#detected_node_shebang" do
    it "can be used to replace Node shebangs" do
      allow(Formulary).to receive(:factory).with(f[:node18].name).and_return(f[:node18])
      Utils::Shebang.rewrite_shebang described_class.detected_node_shebang(f[:versioned_node_dep]), file.path

      expect(File.read(file)).to eq <<~EOS
        #!#{HOMEBREW_PREFIX/"opt/node@18/bin/node"}
        a
        b
        c
      EOS
    end

    it "errors if formula doesn't depend on node" do
      expect { Utils::Shebang.rewrite_shebang described_class.detected_node_shebang(f[:no_deps]), file.path }
        .to raise_error(ShebangDetectionError, "Cannot detect Node shebang: formula does not depend on Node.")
    end

    it "errors if formula depends on more than one node" do
      expect { Utils::Shebang.rewrite_shebang described_class.detected_node_shebang(f[:multiple_deps]), file.path }
        .to raise_error(ShebangDetectionError, "Cannot detect Node shebang: formula has multiple Node dependencies.")
    end
  end
end
