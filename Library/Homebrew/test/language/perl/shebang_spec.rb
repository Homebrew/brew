# frozen_string_literal: true

require "language/perl"
require "utils/shebang"

RSpec.describe Language::Perl::Shebang do
  let(:file) { Tempfile.new("perl-shebang") }
  let(:f) do
    f = {}

    f[:perl] = formula "perl" do
      url "https://brew.sh/perl-1.0.tgz"
    end

    f[:depends_on] = formula "foo" do
      url "https://brew.sh/foo-1.0.tgz"

      depends_on "perl"
    end

    f[:uses_from_macos] = formula "foo" do
      url "https://brew.sh/foo-1.0.tgz"

      uses_from_macos "perl"
    end

    f[:no_deps] = formula "foo" do
      url "https://brew.sh/foo-1.0.tgz"
    end

    f
  end

  before do
    file.write <<~EOS
      #!/usr/bin/env perl
      a
      b
      c
    EOS
    file.flush
  end

  after { file.unlink }

  describe "#detected_perl_shebang" do
    it "can be used to replace Perl shebangs when depends_on \"perl\" is used" do
      allow(Formulary).to receive(:factory).with(f[:perl].name).and_return(f[:perl])
      Utils::Shebang.rewrite_shebang described_class.detected_perl_shebang(f[:depends_on]), file.path

      expect(File.read(file)).to eq <<~EOS
        #!#{HOMEBREW_PREFIX}/opt/perl/bin/perl
        a
        b
        c
      EOS
    end

    it "can be used to replace Perl shebangs when uses_from_macos \"perl\" is used" do
      allow(Formulary).to receive(:factory).with(f[:perl].name).and_return(f[:perl])
      Utils::Shebang.rewrite_shebang described_class.detected_perl_shebang(f[:uses_from_macos]), file.path

      expected_shebang = if OS.mac?
        "/usr/bin/perl#{MacOS.preferred_perl_version}"
      else
        HOMEBREW_PREFIX/"opt/perl/bin/perl"
      end

      expect(File.read(file)).to eq <<~EOS
        #!#{expected_shebang}
        a
        b
        c
      EOS
    end

    it "errors if formula doesn't depend on perl" do
      expect { Utils::Shebang.rewrite_shebang described_class.detected_perl_shebang(f[:no_deps]), file.path }
        .to raise_error(ShebangDetectionError, "Cannot detect Perl shebang: formula does not depend on Perl.")
    end
  end
end
