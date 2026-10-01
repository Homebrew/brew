# typed: true
# frozen_string_literal: true

require "test/cask/dsl/shared_examples/base"

RSpec.describe Cask::DSL::Caveats, :cask do
  subject(:caveats) { described_class.new(cask) }

  let(:cask) { Cask::CaskLoader.load(cask_path("with-caveats-everything")) }

  it_behaves_like Cask::DSL::Base

  describe "#to_s" do
    it "includes caveat text for methods and strings" do
      expected_caveats_str = <<~EOS
        Custom caveat text.

        You must log out and log back in for the installation of #{cask} to take effect.
      EOS

      caveats.eval_caveats do
        T.bind(self, Cask::DSL::Caveats)
        logout
        "Custom caveat text."
      end

      expect(caveats.to_s).to eq(expected_caveats_str)
    end
  end

  describe "#to_s_without_conditional" do
    it "excludes requires_rosetta caveat text" do
      expected_caveats_str = <<~EOS
        #{cask} is built for Intel macOS and so requires Rosetta 2 to be installed.
        You can install Rosetta 2 with:
          softwareupdate --install-rosetta --agree-to-license
        Note that it is very difficult to remove Rosetta 2 once it is installed.
      EOS

      allow(Homebrew::SimulateSystem).to receive(:current_arch).and_return(:arm)
      allow(Hardware::CPU).to receive(:rosetta_installed?).and_return(false)
      caveats.eval_caveats do
        T.bind(self, Cask::DSL::Caveats)
        requires_rosetta
      end

      expect(caveats.to_s).to eq(expected_caveats_str)
      expect(caveats.to_s_without_conditional).to be_empty
    end

    it "keeps non-conditional built-in caveats" do
      expected_caveats_str = <<~EOS
        You must reboot for the installation of #{cask} to take effect.
      EOS

      caveats.eval_caveats do
        T.bind(self, Cask::DSL::Caveats)
        reboot
      end

      expect(caveats.to_s_without_conditional).to eq(expected_caveats_str)
    end

    it "keeps custom caveats" do
      caveats.eval_caveats { "Custom caveat text\n" }

      expect(caveats.to_s_without_conditional).to eq("Custom caveat text\n")
    end
  end

  describe "#invoked?" do
    it "returns true for invoked caveats" do
      allow(Homebrew::SimulateSystem).to receive(:current_arch).and_return(:arm)
      caveats.eval_caveats do
        T.bind(self, Cask::DSL::Caveats)
        requires_rosetta
      end

      expect(caveats.invoked?(:requires_rosetta)).to be true
    end

    it "returns true even when caveat condition is false" do
      allow(Homebrew::SimulateSystem).to receive(:current_arch).and_return(:intel)
      caveats.eval_caveats do
        T.bind(self, Cask::DSL::Caveats)
        requires_rosetta
      end

      expect(caveats.invoked?(:requires_rosetta)).to be true
      expect(caveats.to_s).to be_empty
    end

    it "returns false for non-invoked caveats" do
      expect(caveats.invoked?(:requires_rosetta)).to be false
    end
  end

  describe "#eval_caveats" do
    it "returns nil if the block does not return anything" do
      caveats.eval_caveats do
        # Intentionally empty to exercise the `return unless result` guard
      end

      expect(caveats.to_s).to be_empty
    end
  end

  describe "#kext" do
    it "returns System Settings on macOS Sonoma or later" do
      allow(MacOS).to receive(:version).and_return(MacOSVersion.from_symbol(:sonoma))
      expected_caveats_str = <<~EOS
        #{cask} requires a kernel extension to work.
        If the installation fails, retry after you enable it in:
          System Settings → Privacy & Security

        For more information, refer to vendor documentation or this Apple Technical Note:
          https://developer.apple.com/library/content/technotes/tn2459/_index.html
      EOS

      caveats.eval_caveats do
        T.bind(self, Cask::DSL::Caveats)
        kext
      end

      expect(caveats.to_s).to eq(expected_caveats_str)
    end

    it "does not return kext caveat text on Linux" do
      Homebrew::SimulateSystem.with(os: :linux) do
        caveats.eval_caveats do
          T.bind(self, Cask::DSL::Caveats)
          kext
        end
      end

      expect(caveats.to_s).to be_empty
    end

    it "does not return kext caveat text on macOS Ventura and earlier" do
      allow(MacOS).to receive(:version).and_return(MacOSVersion.from_symbol(:ventura))
      caveats.eval_caveats do
        T.bind(self, Cask::DSL::Caveats)
        kext
      end

      expect(caveats.to_s).to be_empty
    end
  end

  describe "#unsigned_accessibility" do
    it "returns System Settings text on macOS Ventura or later" do
      allow(MacOS).to receive(:version).and_return(MacOSVersion.from_symbol(:ventura))
      expected_caveats_str = <<~EOS
        #{cask} is not signed and requires Accessibility access,
        so you will need to re-grant Accessibility access every time the app is updated.

        Enable or re-enable it in:
          System Settings → Privacy & Security → Accessibility
        To re-enable, untick and retick #{cask}.app.
      EOS

      caveats.eval_caveats do
        T.bind(self, Cask::DSL::Caveats)
        unsigned_accessibility
      end

      expect(caveats.to_s).to eq(expected_caveats_str)
    end

    it "returns System Preferences text on macOS Monterey and earlier" do
      allow(MacOS).to receive(:version).and_return(MacOSVersion.from_symbol(:monterey))
      expected_caveats_str = <<~EOS
        #{cask} is not signed and requires Accessibility access,
        so you will need to re-grant Accessibility access every time the app is updated.

        Enable or re-enable it in:
          System Preferences → Security & Privacy → Privacy → Accessibility
        To re-enable, untick and retick #{cask}.app.
      EOS

      caveats.eval_caveats do
        T.bind(self, Cask::DSL::Caveats)
        unsigned_accessibility
      end

      expect(caveats.to_s).to eq(expected_caveats_str)
    end

    it "returns text using default `access` value when the argument is `nil`" do
      expected_caveats_str = <<~EOS
        #{cask} is not signed and requires Accessibility access,
        so you will need to re-grant Accessibility access every time the app is updated.

        Enable or re-enable it in:
          System Settings → Privacy & Security → Accessibility
        To re-enable, untick and retick #{cask}.app.
      EOS

      Homebrew::SimulateSystem.with(os: :ventura) do
        caveats.eval_caveats do
          T.bind(self, Cask::DSL::Caveats)
          unsigned_accessibility nil
        end
      end

      expect(caveats.to_s).to eq(expected_caveats_str)
    end

    it "does not return unsigned_accessibility caveat text on Linux" do
      Homebrew::SimulateSystem.with(os: :linux) do
        caveats.eval_caveats do
          T.bind(self, Cask::DSL::Caveats)
          unsigned_accessibility
        end
      end

      expect(caveats.to_s).to be_empty
    end
  end

  describe "#path_environment_variable" do
    it "returns PATH environment variable caveat text" do
      expected_caveats_str = <<~EOS
        To use #{cask}, you may need to add the /example/path directory
        to your PATH environment variable, e.g. (for Bash shell):
          export PATH=/example/path:"$PATH"
      EOS

      caveats.eval_caveats do
        T.bind(self, Cask::DSL::Caveats)
        path_environment_variable "/example/path"
      end

      expect(caveats.to_s).to eq(expected_caveats_str)
    end
  end

  describe "#zsh_path_helper" do
    it "returns Zsh PATH helper caveat text" do
      expected_caveats_str = <<~EOS
        To use #{cask}, zsh users may need to add the following line to their
        ~/.zprofile. (Among other effects, /example/path will be added to the
        PATH environment variable):
          eval `/usr/libexec/path_helper -s`
      EOS

      caveats.eval_caveats do
        T.bind(self, Cask::DSL::Caveats)
        zsh_path_helper "/example/path"
      end

      expect(caveats.to_s).to eq(expected_caveats_str)
    end
  end

  describe "#files_in_usr_local" do
    it "returns files in /usr/local caveat text when HOMEBREW_PREFIX starts with /usr/local" do
      stub_const("HOMEBREW_PREFIX", "/usr/local")
      expected_caveats_str = <<~EOS
        Cask #{cask} installs files under /usr/local. The presence of such
        files can cause warnings when running `brew doctor`, which is considered
        to be a bug in Homebrew's cask handling.
      EOS

      caveats.eval_caveats do
        T.bind(self, Cask::DSL::Caveats)
        files_in_usr_local
      end

      expect(caveats.to_s).to eq(expected_caveats_str)
    end

    it "does not return caveat text when HOMEBREW_PREFIX does not start /usr/local" do
      stub_const("HOMEBREW_PREFIX", "/opt/homebrew")
      caveats.eval_caveats do
        T.bind(self, Cask::DSL::Caveats)
        files_in_usr_local
      end

      expect(caveats.to_s).to be_empty
    end
  end

  describe "#depends_on_java" do
    it "returns generic required Java caveat text without an argument" do
      expected_caveats_str = <<~EOS
        #{cask} requires Java. You can install the latest version with:
          brew install --cask temurin
      EOS

      caveats.eval_caveats do
        T.bind(self, Cask::DSL::Caveats)
        depends_on_java
      end

      expect(caveats.to_s).to eq(expected_caveats_str)
    end

    it "returns generic required Java caveat text for `:any` value" do
      expected_caveats_str = <<~EOS
        #{cask} requires Java. You can install the latest version with:
          brew install --cask temurin
      EOS

      caveats.eval_caveats do
        T.bind(self, Cask::DSL::Caveats)
        depends_on_java :any
      end

      expect(caveats.to_s).to eq(expected_caveats_str)
    end

    it "returns required Java caveat text with latest temurin for a version string including a plus sign" do
      expected_caveats_str = <<~EOS
        #{cask} requires Java 11+. You can install the latest version with:
          brew install --cask temurin
      EOS

      caveats.eval_caveats do
        T.bind(self, Cask::DSL::Caveats)
        depends_on_java "11+"
      end

      expect(caveats.to_s).to eq(expected_caveats_str)
    end

    it "returns required Java caveat text with versioned temurin for a version string not including a plus sign" do
      expected_caveats_str = <<~EOS
        #{cask} requires Java 11. You can install it with:
          brew install --cask temurin@11
      EOS

      caveats.eval_caveats do
        T.bind(self, Cask::DSL::Caveats)
        depends_on_java "11"
      end

      expect(caveats.to_s).to eq(expected_caveats_str)
    end
  end

  describe "#requires_rosetta" do
    it "returns Rosetta caveat text if the current arch is :arm and Rosetta 2 is not installed" do
      allow(Homebrew::SimulateSystem).to receive(:current_arch).and_return(:arm)
      allow(Hardware::CPU).to receive(:rosetta_installed?).and_return(false)
      expected_caveats_str = <<~EOS
        #{cask} is built for Intel macOS and so requires Rosetta 2 to be installed.
        You can install Rosetta 2 with:
          softwareupdate --install-rosetta --agree-to-license
        Note that it is very difficult to remove Rosetta 2 once it is installed.
      EOS

      caveats.eval_caveats do
        T.bind(self, Cask::DSL::Caveats)
        requires_rosetta
      end

      expect(caveats.to_s).to eq(expected_caveats_str)
    end

    it "does not return a caveat string if the current arch is :arm but Rosetta 2 is already installed" do
      allow(Homebrew::SimulateSystem).to receive(:current_arch).and_return(:arm)
      allow(Hardware::CPU).to receive(:rosetta_installed?).and_return(true)
      caveats.eval_caveats do
        T.bind(self, Cask::DSL::Caveats)
        requires_rosetta
      end

      expect(caveats.to_s).to be_empty
    end

    it "does not return a caveat string if the current arch is not :arm" do
      allow(Homebrew::SimulateSystem).to receive(:current_arch).and_return(:intel)
      caveats.eval_caveats do
        T.bind(self, Cask::DSL::Caveats)
        requires_rosetta
      end

      expect(caveats.to_s).to be_empty
    end

    it "does not return a caveat string on Linux" do
      allow(Hardware::CPU).to receive(:rosetta_installed?).and_return(false)

      Homebrew::SimulateSystem.with(os: :linux, arch: :arm) do
        caveats.eval_caveats do
          T.bind(self, Cask::DSL::Caveats)
          requires_rosetta
        end
      end

      expect(caveats.to_s).to be_empty
    end
  end

  describe "#logout" do
    it "returns log out caveat text" do
      expected_caveats_str = <<~EOS
        You must log out and log back in for the installation of #{cask} to take effect.
      EOS

      caveats.eval_caveats do
        T.bind(self, Cask::DSL::Caveats)
        logout
      end

      expect(caveats.to_s).to eq(expected_caveats_str)
    end
  end

  describe "#reboot" do
    it "returns reboot caveat text" do
      expected_caveats_str = <<~EOS
        You must reboot for the installation of #{cask} to take effect.
      EOS

      caveats.eval_caveats do
        T.bind(self, Cask::DSL::Caveats)
        reboot
      end

      expect(caveats.to_s).to eq(expected_caveats_str)
    end
  end

  describe "#license" do
    it "returns license caveat text" do
      expected_caveats_str = <<~EOS
        Installing #{cask} means you have AGREED to the license at:
          https://brew.sh/test-license/
      EOS

      caveats.eval_caveats do
        T.bind(self, Cask::DSL::Caveats)
        license "https://brew.sh/test-license/"
      end

      expect(caveats.to_s).to eq(expected_caveats_str)
    end
  end

  describe "#free_license" do
    it "returns license caveat text" do
      expected_caveats_str = <<~EOS
        The vendor offers a free license for #{cask} at:
          https://brew.sh/test-free-license/
      EOS

      caveats.eval_caveats do
        T.bind(self, Cask::DSL::Caveats)
        free_license "https://brew.sh/test-free-license/"
      end

      expect(caveats.to_s).to eq(expected_caveats_str)
    end
  end
end
