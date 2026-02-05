# frozen_string_literal: true

require "language/php"
require "utils/shebang"

RSpec.describe Language::PHP::Shebang do
  let(:file) { Tempfile.new("php-shebang") }
  let(:broken_file) { Tempfile.new("php-shebang") }
  let(:f) do
    f = {}

    f[:php81] = formula "php@8.1" do
      url "https://brew.sh/node-18.0.0.tgz"
    end

    f[:versioned_php_dep] = formula "foo" do
      url "https://brew.sh/foo-1.0.tgz"

      depends_on "php@8.1"
    end

    f[:no_deps] = formula "foo" do
      url "https://brew.sh/foo-1.0.tgz"
    end

    f[:multiple_deps] = formula "foo" do
      url "https://brew.sh/foo-1.0.tgz"

      depends_on "php"
      depends_on "php@8.1"
    end

    f
  end

  before do
    file.write <<~EOS
      #!/usr/bin/env php
      a
      b
      c
    EOS
    file.flush

    broken_file.write <<~EOS
      #!php
      a
      b
      c
    EOS
    broken_file.flush
  end

  after { [file, broken_file].each(&:unlink) }

  describe "#detected_php_shebang" do
    it "can be used to replace PHP shebangs" do
      allow(Formulary).to receive(:factory).with(f[:php81].name).and_return(f[:php81])
      Utils::Shebang.rewrite_shebang described_class.detected_php_shebang(f[:versioned_php_dep]), file.path

      expect(File.read(file)).to eq <<~EOS
        #!#{HOMEBREW_PREFIX/"opt/php@8.1/bin/php"}
        a
        b
        c
      EOS
    end

    it "can fix broken shebang like `#!php`" do
      allow(Formulary).to receive(:factory).with(f[:php81].name).and_return(f[:php81])
      Utils::Shebang.rewrite_shebang described_class.detected_php_shebang(f[:versioned_php_dep]), broken_file.path

      expect(File.read(broken_file)).to eq <<~EOS
        #!#{HOMEBREW_PREFIX/"opt/php@8.1/bin/php"}
        a
        b
        c
      EOS
    end

    it "errors if formula doesn't depend on PHP" do
      expect { Utils::Shebang.rewrite_shebang described_class.detected_php_shebang(f[:no_deps]), file.path }
        .to raise_error(ShebangDetectionError, "Cannot detect PHP shebang: formula does not depend on PHP.")
    end

    it "errors if formula depends on more than one php" do
      expect { Utils::Shebang.rewrite_shebang described_class.detected_php_shebang(f[:multiple_deps]), file.path }
        .to raise_error(ShebangDetectionError, "Cannot detect PHP shebang: formula has multiple PHP dependencies.")
    end
  end
end
