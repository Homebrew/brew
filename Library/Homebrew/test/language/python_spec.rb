# typed: strict
# frozen_string_literal: true

require "language/python"

RSpec.describe Language::Python, :needs_python do
  describe ".direct_dependency_paths", needs_python: false do
    it "returns unique stable paths for tap-qualified direct Python dependencies" do
      f = formula "foo" do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/foo-1.0.tgz"

        depends_on "homebrew/core/python@3.14" => :build
        depends_on "homebrew/core/python@3.14" => :test
        depends_on "python-setuptools"
      end

      expect(described_class.direct_dependency_paths(f)).to eq(
        "python@3.14" => HOMEBREW_PREFIX/"opt/python@3.14/bin/python3.14",
      )
    end

    it "can limit paths to required Python dependencies" do
      f = formula "foo" do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/foo-1.0.tgz"

        depends_on "python@3.13"
        depends_on "python@3.14" => :build
      end

      expect(described_class.direct_dependency_paths(f, required: true)).to eq(
        "python@3.13" => HOMEBREW_PREFIX/"opt/python@3.13/bin/python3.13",
      )
    end
  end

  describe "#major_minor_version" do
    it "returns a Version for Python 2" do
      expect(described_class).to receive(:major_minor_version).and_return(Version)
      described_class.major_minor_version("python")
    end
  end

  describe ".each_python", needs_python: false do
    it "deprecates implicit Python dependency iteration" do
      allow(Formulary).to receive(:factory).and_return(instance_double(Formula, to_s: "python"))

      expect { described_class.each_python(instance_double(BuildOptions, without?: true)) }
        .to raise_error(MethodDeprecatedError, /Language::Python.each_python.*Formula#python3/)
    end
  end

  describe "#site_packages" do
    it "gives a different location between PyPy and Python 2" do
      expect(described_class.site_packages("python")).not_to eql(described_class.site_packages("pypy"))
    end

    it "deprecates the implicit Python interpreter", needs_python: false do
      allow(described_class).to receive(:major_minor_version).and_return(Version.new("3.7"))

      expect { described_class.site_packages }
        .to raise_error(MethodDeprecatedError, /Language::Python.site_packages.*explicit Python interpreter/)
    end
  end

  describe ".homebrew_site_packages", needs_python: false do
    before do
      allow(described_class).to receive(:major_minor_version).and_return(Version.new("3.14"))
    end

    it "deprecates the Homebrew site packages helper" do
      expect { described_class.homebrew_site_packages("python3") }
        .to raise_error(MethodDeprecatedError, %r{Language::Python.homebrew_site_packages.*HOMEBREW_PREFIX/})
    end

    it "still returns the Homebrew site packages location" do
      allow(described_class).to receive(:odeprecated)

      expect(described_class.homebrew_site_packages("python3")).to eq(HOMEBREW_PREFIX/"lib/python3.14/site-packages")
    end
  end

  describe ".reads_brewed_pth_files?", needs_python: false do
    it "deprecates the brewed pth file probe" do
      allow(described_class).to receive(:major_minor_version).and_return(Version.new("3.14"))

      expect { described_class.reads_brewed_pth_files?("python3") }
        .to raise_error(MethodDeprecatedError, /Language::Python.reads_brewed_pth_files\?.*virtualenv/)
    end
  end

  describe ".in_sys_path?", needs_python: false do
    it "deprecates the Python path probe" do
      allow(SystemCommand).to receive(:quiet_system).and_return(true)

      expect { described_class.in_sys_path?("python3", Pathname("/tmp/site-packages")) }
        .to raise_error(MethodDeprecatedError, /Language::Python.in_sys_path\?.*sys.path/)
    end
  end

  describe ".user_site_packages", needs_python: false do
    it "deprecates the user site packages helper" do
      allow(Utils).to receive(:popen_read_text).and_return("/tmp/site-packages\n")

      expect { described_class.user_site_packages("python3") }
        .to raise_error(MethodDeprecatedError, /Language::Python.user_site_packages.*site.getusersitepackages/)
    end

    it "still returns the user site packages path" do
      allow(described_class).to receive(:odeprecated)
      allow(Utils).to receive(:popen_read_text)
        .with("python3", "-c", "import site; print(site.getusersitepackages())", err: :err)
        .and_return("/tmp/site-packages\n")

      expect(described_class.user_site_packages("python3")).to eq(Pathname("/tmp/site-packages"))
    end
  end
end
