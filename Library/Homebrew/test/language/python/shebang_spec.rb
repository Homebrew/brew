# frozen_string_literal: true

require "language/python"
require "utils/shebang"

describe Language::Python::Shebang do
  let(:file) { Tempfile.new("python-shebang") }
  let(:f) do
    f = {}

    f[:python311] = formula "python@3.11" do
      url "https://brew.sh/python-1.0.tgz"
    end

    f[:versioned_python_dep] = formula "foo" do
      url "https://brew.sh/foo-1.0.tgz"

      depends_on "python@3.11"
    end

    f[:no_deps] = formula "foo" do
      url "https://brew.sh/foo-1.0.tgz"
    end

    f[:multiple_deps] = formula "foo" do
      url "https://brew.sh/foo-1.0.tgz"

      depends_on "python"
      depends_on "python@3.11"
    end

    f
  end

  before do
    file.write <<~EOS
      #!/usr/bin/python2
      a
      b
      c
    EOS
    file.flush
  end

  after { file.unlink }

  describe "#detected_python_shebang" do
    it "can be used to replace Python shebangs" do
      allow(Formulary).to receive(:factory)
      allow(Formulary).to receive(:factory).with(f[:python311].name).and_return(f[:python311])
      Utils::Shebang.rewrite_shebang(
        described_class.detected_python_shebang(f[:versioned_python_dep], use_python_from_path: false), file.path
      )

      expect(File.read(file)).to eq <<~EOS
        #!#{HOMEBREW_PREFIX}/opt/python@3.11/bin/python3.11
        a
        b
        c
      EOS
    end

    it "can be pointed to a `python3` in PATH" do
      Utils::Shebang.rewrite_shebang(
        described_class.detected_python_shebang(f[:versioned_python_dep], use_python_from_path: true), file.path
      )

      expect(File.read(file)).to eq <<~EOS
        #!/usr/bin/env python3
        a
        b
        c
      EOS
    end

    it "errors if formula doesn't depend on python" do
      expect do
        Utils::Shebang.rewrite_shebang(
          described_class.detected_python_shebang(f[:no_deps], use_python_from_path: false),
          file.path,
        )
      end.to raise_error(ShebangDetectionError, "Cannot detect Python shebang: formula does not depend on Python.")
    end

    it "errors if formula depends on more than one python" do
      expect do
        Utils::Shebang.rewrite_shebang(
          described_class.detected_python_shebang(f[:multiple_deps], use_python_from_path: false),
          file.path,
        )
      end.to raise_error(
        ShebangDetectionError,
        "Cannot detect Python shebang: formula has multiple Python dependencies.",
      )
    end
  end
end
