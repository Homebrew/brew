# frozen_string_literal: true

require "version/parser"

RSpec.describe Version::Parser do
  specify "::new" do
    expect { described_class.new }
      .to raise_error("Version::Parser is declared as abstract; it cannot be instantiated")
  end

  describe Version::RegexParser do
    specify "::new" do
      expect { described_class.new(/[._-](\d+(?:\.\d+)+)/) }
        .to raise_error("Version::RegexParser is declared as abstract; it cannot be instantiated")
    end

    specify "::process_spec" do
      expect { described_class.process_spec(Pathname(TEST_TMPDIR)) }
        .to raise_error("The method `process_spec` on #<Class:Version::RegexParser> is declared as `abstract`. " \
                        "It does not have an implementation.")
    end
  end

  describe Version::UrlParser do
    specify "::new" do
      expect { described_class.new(/[._-](\d+(?:\.\d+)+)/) }.not_to raise_error
    end

    specify "::process_spec" do
      expect(described_class.process_spec(Pathname("#{TEST_TMPDIR}/testdir-0.1.test")))
        .to eq("#{TEST_TMPDIR}/testdir-0.1.test")

      expect(described_class.process_spec(Pathname("https://sourceforge.net/foo_bar-1.21.tar.gz/download")))
        .to eq("https://sourceforge.net/foo_bar-1.21.tar.gz/download")

      expect(described_class.process_spec(Pathname("https://sf.net/foo_bar-1.21.tar.gz/download")))
        .to eq("https://sf.net/foo_bar-1.21.tar.gz/download")

      expect(described_class.process_spec(Pathname("https://brew.sh/testball-0.1")))
        .to eq("https://brew.sh/testball-0.1")

      expect(described_class.process_spec(Pathname("https://brew.sh/testball-0.1.tgz")))
        .to eq("https://brew.sh/testball-0.1.tgz")
    end
  end

  describe Version::StemParser do
    before { Pathname("#{TEST_TMPDIR}/testdir-0.1.test").mkpath }

    after { Pathname("#{TEST_TMPDIR}/testdir-0.1.test").unlink }

    specify "::new" do
      expect { described_class.new(/[._-](\d+(?:\.\d+)+)/) }.not_to raise_error
    end

    describe "::process_spec" do
      it "works with directories" do
        expect(described_class.process_spec(Pathname("#{TEST_TMPDIR}/testdir-0.1.test"))).to eq("testdir-0.1.test")
      end

      it "works with SourceForge URLs with /download suffix" do
        expect(described_class.process_spec(Pathname("https://sourceforge.net/foo_bar-1.21.tar.gz/download")))
          .to eq("foo_bar-1.21")

        expect(described_class.process_spec(Pathname("https://sf.net/foo_bar-1.21.tar.gz/download")))
          .to eq("foo_bar-1.21")
      end

      it "works with URLs without file extension" do
        expect(described_class.process_spec(Pathname("https://brew.sh/testball-0.1"))).to eq("testball-0.1")
      end

      it "works with URLs with file extension" do
        expect(described_class.process_spec(Pathname("https://brew.sh/testball-0.1.tgz"))).to eq("testball-0.1")
      end
    end
  end
end
