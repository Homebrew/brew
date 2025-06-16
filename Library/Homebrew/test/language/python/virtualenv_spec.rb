# frozen_string_literal: true

require "language/python"
require "resource"

RSpec.describe Language::Python::Virtualenv, :needs_python do
  describe "#virtualenv_install_with_resources" do
    let(:venv) { instance_double(Language::Python::Virtualenv::Virtualenv) }
    let(:f) do
      formula "foo" do
        # Couldn't find a way to get described_class to work inside formula do
        # rubocop:disable RSpec/DescribedClass
        include Language::Python::Virtualenv
        # rubocop:enable RSpec/DescribedClass

        url "https://brew.sh/foo-1.0.tgz"

        resource "resource-a" do
          url "https://brew.sh/resource1.tar.gz"
          sha256 "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        end

        resource "resource-b" do
          url "https://brew.sh/resource2.tar.gz"
          sha256 "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        end

        resource "resource-c" do
          url "https://brew.sh/resource3.tar.gz"
          sha256 "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
        end

        resource "resource-d" do
          url "https://brew.sh/resource4.tar.gz"
          sha256 "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
        end
      end
    end
    let(:r_a) { f.resource("resource-a") }
    let(:r_b) { f.resource("resource-b") }
    let(:r_c) { f.resource("resource-c") }
    let(:r_d) { f.resource("resource-d") }
    let(:buildpath) { Pathname(TEST_TMPDIR) }

    before { f.instance_variable_set(:@buildpath, buildpath) }

    it "works with `using: \"python\"` and installs resources in order" do
      expect(f).to receive(:virtualenv_create).with(
        f.libexec, "python", { system_site_packages: true, without_pip: true }
      ).and_return(venv)
      expect(venv).to receive(:pip_install).with([r_a, r_b, r_c, r_d])
      expect(venv).to receive(:pip_install_and_link).with(buildpath, { link_manpages: true })
      f.virtualenv_install_with_resources(using: "python")
    end

    it "works with `using: \"python@3.12\"` and installs resources in order" do
      expect(f).to receive(:virtualenv_create).with(
        f.libexec, "python3.12", { system_site_packages: true, without_pip: true }
      ).and_return(venv)
      expect(venv).to receive(:pip_install).with([r_a, r_b, r_c, r_d])
      expect(venv).to receive(:pip_install_and_link).with(buildpath, { link_manpages: true })
      f.virtualenv_install_with_resources(using: "python@3.12")
    end

    it "skips a `without` resource string and installs remaining resources in order" do
      expect(f).to receive(:virtualenv_create).and_return(venv)
      expect(venv).to receive(:pip_install).with([r_a, r_b, r_d])
      expect(venv).to receive(:pip_install_and_link).with(buildpath, { link_manpages: true })
      f.virtualenv_install_with_resources(using: "python", without: r_c.name)
    end

    it "skips all resources in `without` array and installs remaining resources in order" do
      expect(f).to receive(:virtualenv_create).and_return(venv)
      expect(venv).to receive(:pip_install).with([r_b, r_c])
      expect(venv).to receive(:pip_install_and_link).with(buildpath, { link_manpages: true })
      f.virtualenv_install_with_resources(using: "python", without: [r_d.name, r_a.name])
    end

    it "errors if `without` resource string does not exist in formula" do
      expect do
        f.virtualenv_install_with_resources(using: "python", without: "unknown")
      end.to raise_error(ArgumentError)
    end

    it "errors if `without` resource array refers to a resource that does not exist in formula" do
      expect do
        f.virtualenv_install_with_resources(using: "python", without: [r_a.name, "unknown"])
      end.to raise_error(ArgumentError)
    end

    it "installs a `start_with` resource string and then remaining resources in order" do
      expect(f).to receive(:virtualenv_create).and_return(venv)
      expect(venv).to receive(:pip_install).with([r_c, r_a, r_b, r_d])
      expect(venv).to receive(:pip_install_and_link).with(buildpath, { link_manpages: true })
      f.virtualenv_install_with_resources(using: "python", start_with: r_c.name)
    end

    it "installs all resources in `start_with` array and then remaining resources in order" do
      expect(f).to receive(:virtualenv_create).and_return(venv)
      expect(venv).to receive(:pip_install).with([r_d, r_b, r_a, r_c])
      expect(venv).to receive(:pip_install_and_link).with(buildpath, { link_manpages: true })
      f.virtualenv_install_with_resources(using: "python", start_with: [r_d.name, r_b.name])
    end

    it "errors if `start_with` resource string does not exist in formula" do
      expect do
        f.virtualenv_install_with_resources(using: "python", start_with: "unknown")
      end.to raise_error(ArgumentError)
    end

    it "errors if `start_with` resource array refers to a resource that does not exist in formula" do
      expect do
        f.virtualenv_install_with_resources(using: "python", start_with: [r_a.name, "unknown"])
      end.to raise_error(ArgumentError)
    end

    it "installs an `end_with` resource string as last resource" do
      expect(f).to receive(:virtualenv_create).and_return(venv)
      expect(venv).to receive(:pip_install).with([r_a, r_c, r_d, r_b])
      expect(venv).to receive(:pip_install_and_link).with(buildpath, { link_manpages: true })
      f.virtualenv_install_with_resources(using: "python", end_with: r_b.name)
    end

    it "installs all resources in `end_with` array after other resources are installed" do
      expect(f).to receive(:virtualenv_create).and_return(venv)
      expect(venv).to receive(:pip_install).with([r_a, r_d, r_c, r_b])
      expect(venv).to receive(:pip_install_and_link).with(buildpath, { link_manpages: true })
      f.virtualenv_install_with_resources(using: "python", end_with: [r_c.name, r_b.name])
    end

    it "errors if `end_with` resource string does not exist in formula" do
      expect do
        f.virtualenv_install_with_resources(using: "python", end_with: "unknown")
      end.to raise_error(ArgumentError)
    end

    it "errors if `end_with` resource array refers to a resource that does not exist in formula" do
      expect do
        f.virtualenv_install_with_resources(using: "python", end_with: [r_a.name, "unknown"])
      end.to raise_error(ArgumentError)
    end

    it "installs resources in correct order when combining `without`, `start_with` and `end_with" do
      expect(f).to receive(:virtualenv_create).and_return(venv)
      expect(venv).to receive(:pip_install).with([r_d, r_c, r_b])
      expect(venv).to receive(:pip_install_and_link).with(buildpath, { link_manpages: true })
      f.virtualenv_install_with_resources(using: "python", without: r_a.name,
                                          start_with: r_d.name, end_with: r_b.name)
    end
  end

  describe Language::Python::Virtualenv::Virtualenv do
    subject(:virtualenv) { described_class.new(formula, dir, "python") }

    let(:dir) { mktmpdir }

    let(:resource) { instance_double(Resource, "resource", stage: true) }
    let(:formula_bin) { dir/"formula_bin" }
    let(:formula_man) { dir/"formula_man" }
    let(:formula) { instance_double(Formula, "formula", resource:, bin: formula_bin, man: formula_man) }

    describe "#create" do
      it "creates a venv" do
        expect(formula).to receive(:system)
          .with("python", "-m", "venv", "--system-site-packages", "--without-pip", dir)
        virtualenv.create
      end

      it "creates a venv with pip" do
        expect(formula).to receive(:system).with("python", "-m", "venv", "--system-site-packages", dir)
        virtualenv.create(without_pip: false)
      end
    end

    describe "#pip_install" do
      it "accepts a string" do
        expect(formula).to receive(:std_pip_args).with(prefix:          false,
                                                       build_isolation: true).and_return(["--std-pip-args"])
        expect(formula).to receive(:system)
          .with("python", "-m", "pip", "--python=#{dir}/bin/python", "install", "--std-pip-args", "foo")
          .and_return(true)
        virtualenv.pip_install "foo"
      end

      it "accepts a multi-line strings" do
        expect(formula).to receive(:std_pip_args).with(prefix:          false,
                                                       build_isolation: true).and_return(["--std-pip-args"])
        expect(formula).to receive(:system)
          .with("python", "-m", "pip", "--python=#{dir}/bin/python", "install", "--std-pip-args", "foo", "bar")
          .and_return(true)

        virtualenv.pip_install <<~EOS
          foo
          bar
        EOS
      end

      it "accepts an array" do
        expect(formula).to receive(:std_pip_args).with(prefix:          false,
                                                       build_isolation: true).and_return(["--std-pip-args"])
        expect(formula).to receive(:system)
          .with("python", "-m", "pip", "--python=#{dir}/bin/python", "install", "--std-pip-args", "foo")
          .and_return(true)

        expect(formula).to receive(:std_pip_args).with(prefix:          false,
                                                       build_isolation: true).and_return(["--std-pip-args"])
        expect(formula).to receive(:system)
          .with("python", "-m", "pip", "--python=#{dir}/bin/python", "install", "--std-pip-args", "bar")
          .and_return(true)

        virtualenv.pip_install ["foo", "bar"]
      end

      it "accepts a Resource" do
        res = Resource.new("test")

        expect(res).to receive(:stage).and_yield
        expect(formula).to receive(:std_pip_args).with(prefix:          false,
                                                       build_isolation: true).and_return(["--std-pip-args"])
        expect(formula).to receive(:system)
          .with("python", "-m", "pip", "--python=#{dir}/bin/python", "install", "--std-pip-args", Pathname.pwd)
          .and_return(true)

        virtualenv.pip_install res
      end

      it "works without build isolation" do
        expect(formula).to receive(:std_pip_args).with(prefix:          false,
                                                       build_isolation: false).and_return(["--std-pip-args"])
        expect(formula).to receive(:system)
          .with("python", "-m", "pip", "--python=#{dir}/bin/python", "install", "--std-pip-args", "foo")
          .and_return(true)
        virtualenv.pip_install("foo", build_isolation: false)
      end
    end

    describe "#pip_install_and_link" do
      let(:src_bin) { dir/"bin" }
      let(:src_man) { dir/"share/man" }
      let(:dest_bin) { formula.bin }
      let(:dest_man) { formula.man }

      it "can link scripts" do
        src_bin.mkpath

        expect(src_bin/"kilroy").not_to exist
        expect(dest_bin/"kilroy").not_to exist

        FileUtils.touch src_bin/"irrelevant"
        bin_before = Dir.glob(src_bin/"*")
        FileUtils.touch src_bin/"kilroy"
        bin_after = Dir.glob(src_bin/"*")

        expect(virtualenv).to receive(:pip_install).with("foo", { build_isolation: true })
        expect(Dir).to receive(:[]).with(src_bin/"*").twice.and_return(bin_before, bin_after)

        virtualenv.pip_install_and_link("foo", link_manpages: false)

        expect(src_bin/"kilroy").to exist
        expect(dest_bin/"kilroy").to exist
        expect(dest_bin/"kilroy").to be_a_symlink
        expect((src_bin/"kilroy").realpath).to eq((dest_bin/"kilroy").realpath)
        expect(dest_bin/"irrelevant").not_to exist
      end

      it "can link manpages" do
        (src_man/"man1").mkpath
        (src_man/"man3").mkpath

        expect(src_man/"man1/kilroy.1").not_to exist
        expect(dest_man/"man1").not_to exist
        expect(dest_man/"man3").not_to exist
        expect(dest_man/"man5").not_to exist

        FileUtils.touch src_man/"man1/irrelevant.1"
        FileUtils.touch src_man/"man3/irrelevant.3"
        man_before = Dir.glob(src_man/"**/*")
        (src_man/"man5").mkpath
        FileUtils.touch src_man/"man1/kilroy.1"
        FileUtils.touch src_man/"man5/kilroy.5"
        man_after = Dir.glob(src_man/"**/*")

        expect(virtualenv).to receive(:pip_install).with("foo", { build_isolation: true })
        expect(Dir).to receive(:[]).with(src_bin/"*").and_return([])
        expect(Dir).to receive(:[]).with(src_man/"man*/*").and_return(man_before)
        expect(Dir).to receive(:[]).with(src_bin/"*").and_return([])
        expect(Dir).to receive(:[]).with(src_man/"man*/*").and_return(man_after)

        virtualenv.pip_install_and_link("foo", link_manpages: true)

        expect(src_man/"man1/kilroy.1").to exist
        expect(dest_man/"man1/kilroy.1").to exist
        expect(dest_man/"man5/kilroy.5").to exist
        expect(dest_man/"man1/kilroy.1").to be_a_symlink
        expect((src_man/"man1/kilroy.1").realpath).to eq((dest_man/"man1/kilroy.1").realpath)
        expect(dest_man/"man1/irrelevant.1").not_to exist
        expect(dest_man/"man3").not_to exist
      end
    end
  end
end
