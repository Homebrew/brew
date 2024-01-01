# frozen_string_literal: true

# TODO: this test should be named after the corresponding class, once
#       that class is abstracted from installer.rb
describe "Satisfy Dependencies and Requirements", :cask do
  subject(:install) do
    Cask::Installer.new(cask).install
  end

  describe "depends_on cask" do
    let(:dependency) { Cask::CaskLoader.load(cask.depends_on.cask.first) }
    let(:cask) { Cask::CaskLoader.load(cask_path("with-depends-on-cask")) }

    it "installs the dependency of a Cask and the Cask itself" do
      expect { install }.not_to raise_error
      expect(cask).to be_installed
      expect(dependency).to be_installed
    end

    context "when depends_on cask is cyclic" do
      let(:cask) { Cask::CaskLoader.load(cask_path("with-depends-on-cask-cyclic")) }

      it {
        expect { install }.to raise_error(
          Cask::CaskCyclicDependencyError,
          "Cask 'with-depends-on-cask-cyclic' includes cyclic dependencies " \
          "on other Casks: with-depends-on-cask-cyclic-helper",
        )
      }
    end
  end

  describe "depends_on macos" do
    context "with an array" do
      let(:cask) { Cask::CaskLoader.load(cask_path("with-depends-on-macos-array")) }

      it "does not raise an error" do
        expect { install }.not_to raise_error
      end
    end

    context "with a comparison" do
      let(:cask) { Cask::CaskLoader.load(cask_path("with-depends-on-macos-comparison")) }

      it "does not raise an error" do
        expect { install }.not_to raise_error
      end
    end

    context "with a symbol" do
      let(:cask) { Cask::CaskLoader.load(cask_path("with-depends-on-macos-symbol")) }

      it "does not raise an error" do
        expect { install }.not_to raise_error
      end
    end

    context "when not satisfied" do
      let(:cask) { Cask::CaskLoader.load(cask_path("with-depends-on-macos-failure")) }

      it "raises an error" do
        expect { install }.to raise_error(Cask::CaskError)
      end
    end
  end

  describe "depends_on arch" do
    context "when satisfied" do
      let(:cask) { Cask::CaskLoader.load(cask_path("with-depends-on-arch")) }

      it "does not raise an error" do
        expect { install }.not_to raise_error
      end
    end
  end
end
