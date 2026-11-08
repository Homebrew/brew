# typed: true
# frozen_string_literal: true

require "install"

# TODO: this test should be named after the corresponding class, once
#       that class is abstracted from installer.rb
# rubocop:disable RSpec/DescribeClass
RSpec.describe "Satisfy Dependencies and Requirements", :cask do
  # rubocop:enable RSpec/DescribeClass
  subject(:install) do
    Cask::Installer.new(cask).install
  end

  let(:cask) { Cask::CaskLoader.from_path(cask_path("with-depends-on-cask")) }

  describe "depends_on cask" do
    let(:dependency) { Cask::CaskLoader.load(cask.depends_on.cask.first) }

    it "installs the dependency of a Cask and the Cask itself" do
      expect { install }.not_to raise_error
      expect(cask).to be_installed
      expect(dependency).to be_installed
    end

    test_each([:enqueue_dependency_downloads, :satisfy_cask_and_formula_dependencies]) do |method|
      it "leaves nested dependency handling to the parent during #{method}" do
        nested_installer = Cask::Installer.new(cask).dependency_installers.fetch(0).fetch(0)

        expect(nested_installer).not_to receive(:cask_and_formula_dependencies)

        nested_installer.public_send(method)
      end
    end

    context "when depends_on cask is cyclic" do
      let(:cask) { Cask::CaskLoader.from_path(cask_path("with-depends-on-cask-cyclic")) }

      it {
        expect { install }.to raise_error(
          Cask::CaskCyclicDependencyError,
          "Cask 'with-depends-on-cask-cyclic' includes cyclic dependencies " \
          "on other Casks: with-depends-on-cask-cyclic-helper",
        )
      }
    end
  end

  describe "depends_on formula when not installed on request" do
    let(:installer) { Cask::Installer.new(cask, installed_on_request: false) }
    let(:dependency) do
      formula("dependency") do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/dependency-1.0.tar.gz"
      end
    end
    let(:formula_installer) { installer.dependency_installers.fetch(1).fetch(0) }

    before do
      allow(installer).to receive(:cask_and_formula_dependencies).and_return([dependency])
      allow(formula_installer).to receive(:finish)
      allow(Homebrew::Install).to receive(:perform_preinstall_checks_once)
    end

    it "enqueues missing formula dependencies" do
      expect(Homebrew::Install).to receive(:enqueue_formulae)
        .with([formula_installer], download_queue: Homebrew::DownloadQueue.default).and_return([formula_installer])

      installer.enqueue_dependency_downloads
    end

    it "installs missing formula dependencies" do
      allow(Homebrew::Install).to receive(:fetch_formulae).with([formula_installer]).and_return([formula_installer])
      expect(formula_installer).to receive(:install)

      installer.satisfy_cask_and_formula_dependencies
    end
  end

  describe "depends_on macos" do
    context "with an array" do
      let(:cask) { Cask::CaskLoader.from_path(cask_path("with-depends-on-macos-array")) }

      it "does not raise an error" do
        expect { install }.not_to raise_error
      end
    end

    context "with a comparison" do
      let(:cask) { Cask::CaskLoader.from_path(cask_path("with-depends-on-macos-comparison")) }

      it "does not raise an error" do
        expect { install }.not_to raise_error
      end
    end

    context "with a symbol" do
      let(:cask) { Cask::CaskLoader.from_path(cask_path("with-depends-on-macos-symbol")) }

      it "does not raise an error" do
        expect { install }.not_to raise_error
      end
    end

    context "when not satisfied" do
      let(:cask) { Cask::CaskLoader.from_path(cask_path("with-depends-on-macos-failure")) }

      it "raises an error" do
        allow(OS::Mac).to receive(:version).and_return(MacOSVersion.new(HOMEBREW_MACOS_NEWEST_SUPPORTED))
        expect { install }.to raise_error(Cask::CaskError)
      end
    end
  end

  describe "depends_on arch" do
    context "when satisfied" do
      let(:cask) { Cask::CaskLoader.from_path(cask_path("with-depends-on-arch")) }

      it "does not raise an error" do
        expect { install }.not_to raise_error
      end
    end
  end
end
