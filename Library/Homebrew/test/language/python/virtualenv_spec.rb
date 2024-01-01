# frozen_string_literal: true

require "language/python"
require "resource"

describe Language::Python::Virtualenv::Virtualenv, :needs_python do
  subject(:virtualenv) { described_class.new(formula, dir, "python") }

  let(:dir) { mktmpdir }

  let(:resource) { instance_double(Resource, "resource", stage: true) }
  let(:formula_bin) { dir/"formula_bin" }
  let(:formula_man) { dir/"formula_man" }
  let(:formula) { instance_double(Formula, "formula", resource: resource, bin: formula_bin, man: formula_man) }

  describe "#create" do
    it "creates a venv" do
      expect(formula).to receive(:system).with("python", "-m", "venv", "--system-site-packages", "--without-pip", dir)
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

      virtualenv.pip_install_and_link "foo"

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
