# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/generate-cask-ci-matrix"

RSpec.describe Homebrew::DevCmd::GenerateCaskCiMatrix do
  subject(:generate_matrix) { described_class.new(["test"]) }

  let(:c_on_system_depends_on_mixed) do
    Cask::Cask.new("test-on-system-depends-on-mixed") do
      os macos: "darwin", linux: "linux"

      version "0.0.1,2"

      url "https://brew.sh/test-0.0.1.dmg"
      name "Test"
      desc "Test cask"
      homepage "https://brew.sh"

      on_macos do
        depends_on arch: :x86_64
      end

      on_linux do
        depends_on arch: :arm64
      end
    end
  end
  let(:c_on_macos_depends_on_intel) do
    Cask::Cask.new("test-on-macos-depends-on-intel") do
      os macos: "darwin", linux: "linux"

      version "0.0.1,2"

      url "https://brew.sh/test-0.0.1.dmg"
      name "Test"
      desc "Test cask"
      homepage "https://brew.sh"

      on_macos do
        depends_on arch: :x86_64
      end
    end
  end
  let(:c_on_linux_depends_on_intel) do
    Cask::Cask.new("test-on-linux-depends-on-intel") do
      os macos: "darwin", linux: "linux"

      version "0.0.1,2"

      url "https://brew.sh/test-0.0.1.dmg"
      name "Test"
      desc "Test cask"
      homepage "https://brew.sh"

      on_linux do
        depends_on arch: :x86_64
      end
    end
  end
  let(:c_on_system_depends_on_intel) do
    Cask::Cask.new("test-on-system-depends-on-intel") do
      os macos: "darwin", linux: "linux"

      version "0.0.1,2"

      url "https://brew.sh/test-0.0.1.dmg"
      name "Test"
      desc "Test cask"
      homepage "https://brew.sh"

      depends_on arch: :x86_64
    end
  end
  let(:c_on_system) do
    Cask::Cask.new("test-on-system") do
      os macos: "darwin", linux: "linux"

      version "0.0.1,2"

      url "https://brew.sh/test-0.0.1.dmg"
      name "Test"
      desc "Test cask"
      homepage "https://brew.sh"
    end
  end
  let(:c_depends_macos_on_intel) do
    Cask::Cask.new("test-depends-on-intel") do
      version "0.0.1,2"

      url "https://brew.sh/test-0.0.1.dmg"
      name "Test"
      desc "Test cask"
      homepage "https://brew.sh"

      depends_on arch: :x86_64

      app "Test.app"
    end
  end
  let(:c_app) do
    Cask::Cask.new("test-app") do
      version "0.0.1,2"

      url "https://brew.sh/test-0.0.1.dmg"
      name "Test"
      desc "Test cask"
      homepage "https://brew.sh"

      app "Test.app"
    end
  end
  let(:c_app_only_macos) do
    Cask::Cask.new("test-on-macos-guarded-stanza") do
      os macos: "darwin", linux: "linux"
      version "0.0.1,2"

      url "https://brew.sh/test-0.0.1.dmg"
      name "Test"
      desc "Test cask"
      homepage "https://brew.sh"

      on_macos do
        app "Test.app"
      end
    end
  end
  let(:c) do
    Cask::Cask.new("test-font") do
      version "0.0.1,2"

      url "https://brew.sh/test-0.0.1.dmg"
      name "Test"
      desc "Test cask"
      homepage "https://brew.sh"

      font "Test.ttf"
    end
  end
  let(:newest_macos) { MacOSVersion.new(HOMEBREW_MACOS_NEWEST_SUPPORTED).to_sym }

  it_behaves_like "parseable arguments"

  describe "::filter_runners" do
    # We simulate a macOS version older than the newest, as the method will use
    # the host macOS version instead of the default (the newest macOS version).
    let(:older_macos) { :big_sur }

    context "when cask does not have on_system blocks/calls or `depends_on arch`" do
      it "returns an array including everything" do
        expect(generate_matrix.send(:filter_runners, c))
          .to eq({
            { arch: :arm, name: "macos-14", symbol: :sonoma }          => 0.0,
            { arch: :arm, name: "macos-15", symbol: :sequoia }         => 0.0,
            { arch: :arm, name: "macos-26", symbol: :tahoe }           => 1.0,
            { arch: :arm, name: "ubuntu-22.04-arm", symbol: :linux }   => 1.0,
            { arch: :intel, name: "macos-15-intel", symbol: :sequoia } => 1.0,
            { arch: :intel, name: "ubuntu-22.04", symbol: :linux }     => 1.0,
          })

        expect(generate_matrix.send(:filter_runners, c_app_only_macos))
          .to eq({
            { arch: :arm, name: "macos-14", symbol: :sonoma }          => 0.0,
            { arch: :arm, name: "macos-15", symbol: :sequoia }         => 0.0,
            { arch: :arm, name: "macos-26", symbol: :tahoe }           => 1.0,
            { arch: :arm, name: "ubuntu-22.04-arm", symbol: :linux }   => 1.0,
            { arch: :intel, name: "macos-15-intel", symbol: :sequoia } => 1.0,
            { arch: :intel, name: "ubuntu-22.04", symbol: :linux }     => 1.0,
          })
      end
    end

    context "when cask does not have on_system blocks/calls but has macOS specific stanza" do
      it "returns an array including all macOS" do
        expect(generate_matrix.send(:filter_runners, c_app))
          .to eq({
            { arch: :arm, name: "macos-14", symbol: :sonoma }          => 0.0,
            { arch: :arm, name: "macos-15", symbol: :sequoia }         => 0.0,
            { arch: :arm, name: "macos-26", symbol: :tahoe }           => 1.0,
            { arch: :intel, name: "macos-15-intel", symbol: :sequoia } => 1.0,
          })
      end
    end

    context "when cask does not have on_system blocks/calls but has `depends_on arch`" do
      it "returns an array only including macOS/`depends_on arch` value" do
        expect(generate_matrix.send(:filter_runners, c_depends_macos_on_intel))
          .to eq({ { arch: :intel, name: "macos-15-intel", symbol: :sequoia } => 1.0 })
      end
    end

    context "when cask has on_system blocks/calls but does not have `depends_on arch`" do
      it "returns an array with combinations of OS and architectures" do
        expect(generate_matrix.send(:filter_runners, c_on_system))
          .to eq({
            { arch: :arm, name: "macos-14", symbol: :sonoma }          => 0.0,
            { arch: :arm, name: "macos-15", symbol: :sequoia }         => 0.0,
            { arch: :arm, name: "macos-26", symbol: :tahoe }           => 1.0,
            { arch: :arm, name: "ubuntu-22.04-arm", symbol: :linux }   => 1.0,
            { arch: :intel, name: "macos-15-intel", symbol: :sequoia } => 1.0,
            { arch: :intel, name: "ubuntu-22.04", symbol: :linux }     => 1.0,
          })
      end
    end

    context "when cask has on_system blocks/calls and `depends_on arch`" do
      it "returns an array with combinations of OS and `depends_on arch` value" do
        expect(generate_matrix.send(:filter_runners, c_on_system_depends_on_intel))
          .to eq({
            { arch: :intel, name: "macos-15-intel", symbol: :sequoia } => 1.0,
            { arch: :intel, name: "ubuntu-22.04", symbol: :linux }     => 1.0,
          })

        expect(generate_matrix.send(:filter_runners, c_on_linux_depends_on_intel))
          .to eq({
            { arch: :arm, name: "macos-14", symbol: :sonoma }          => 0.0,
            { arch: :arm, name: "macos-15", symbol: :sequoia }         => 0.0,
            { arch: :arm, name: "macos-26", symbol: :tahoe }           => 1.0,
            { arch: :intel, name: "macos-15-intel", symbol: :sequoia } => 1.0,
            { arch: :intel, name: "ubuntu-22.04", symbol: :linux }     => 1.0,
          })

        expect(generate_matrix.send(:filter_runners, c_on_macos_depends_on_intel))
          .to eq({
            { arch: :intel, name: "macos-15-intel", symbol: :sequoia } => 1.0,
            { arch: :intel, name: "ubuntu-22.04", symbol: :linux }     => 1.0,
            { arch: :arm, name: "ubuntu-22.04-arm", symbol: :linux }   => 1.0,
          })

        expect(generate_matrix.send(:filter_runners, c_on_system_depends_on_mixed))
          .to eq({
            { arch: :arm, name: "ubuntu-22.04-arm", symbol: :linux }   => 1.0,
            { arch: :intel, name: "macos-15-intel", symbol: :sequoia } => 1.0,
          })
      end
    end
  end
end
