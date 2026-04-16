# typed: false
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/bump-cask-pr"
require "bump_version_parser"

RSpec.describe Homebrew::DevCmd::BumpCaskPr do
  subject(:bump_cask_pr) { described_class.new(["test"]) }

  let(:newest_macos) { MacOSVersion.new(HOMEBREW_MACOS_NEWEST_SUPPORTED).to_sym }

  let(:c) do
    Cask::Cask.new("test") do
      version "0.0.1,2"

      url "https://brew.sh/test-0.0.1.dmg"
      name "Test"
      desc "Test cask"
      homepage "https://brew.sh"
    end
  end

  let(:c_depends_on_intel) do
    Cask::Cask.new("test-depends-on-intel") do
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

  let(:c_arm_intel) do
    Cask::Cask.new("test") do
      on_arm do
        version "0.0.2,3"
      end
      on_intel do
        version "0.0.1,2"
      end

      url "https://brew.sh/test-#{version}.dmg"
      name "Test"
      desc "Test cask"
      homepage "https://brew.sh"
    end
  end

  it_behaves_like "parseable arguments"

  describe "::generate_system_options" do
    # We simulate a macOS version older than the newest, as the method will use
    # the host macOS version instead of the default (the newest macOS version).
    let(:older_macos) { :big_sur }

    let(:new_version) { Homebrew::BumpVersionParser.new(general: "1.2.3") }

    context "when cask does not have on_system blocks/calls or `depends_on arch`" do
      it "returns an array only including macOS/ARM" do
        Homebrew::SimulateSystem.with(os: :linux) do
          expect(bump_cask_pr.send(:generate_system_options, c, new_version))
            .to eq([[newest_macos, :arm]])
        end

        Homebrew::SimulateSystem.with(os: older_macos) do
          expect(bump_cask_pr.send(:generate_system_options, c, new_version))
            .to eq([[older_macos, :arm]])
        end
      end
    end

    context "when cask does not have on_system blocks/calls but has `depends_on arch`" do
      it "returns an array only including macOS/`depends_on arch` value" do
        Homebrew::SimulateSystem.with(os: :linux, arch: :arm) do
          expect(bump_cask_pr.send(:generate_system_options, c_depends_on_intel, new_version))
            .to eq([[newest_macos, :intel]])
        end

        Homebrew::SimulateSystem.with(os: older_macos, arch: :arm) do
          expect(bump_cask_pr.send(:generate_system_options, c_depends_on_intel, new_version))
            .to eq([[older_macos, :intel]])
        end
      end
    end

    context "when cask has on_system blocks/calls but does not have `depends_on arch`" do
      it "returns an array with combinations of `OnSystem::BASE_OS_OPTIONS` and `OnSystem::ARCH_OPTIONS`" do
        Homebrew::SimulateSystem.with(os: :linux) do
          expect(bump_cask_pr.send(:generate_system_options, c_on_system, new_version))
            .to eq([
              [newest_macos, :intel],
              [newest_macos, :arm],
              [:linux, :intel],
              [:linux, :arm],
            ])
        end

        Homebrew::SimulateSystem.with(os: older_macos) do
          expect(bump_cask_pr.send(:generate_system_options, c_on_system, new_version))
            .to eq([
              [older_macos, :intel],
              [older_macos, :arm],
              [:linux, :intel],
              [:linux, :arm],
            ])
        end
      end
    end

    context "when cask has on_system blocks/calls and `depends_on arch`" do
      it "returns an array with combinations of `OnSystem::BASE_OS_OPTIONS` and `OnSystem::ARCH_OPTIONS`" do
        Homebrew::SimulateSystem.with(os: :linux, arch: :arm) do
          expect(bump_cask_pr.send(:generate_system_options, c_on_system_depends_on_intel, new_version))
            .to eq([
              [newest_macos, :intel],
              [newest_macos, :arm],
              [:linux, :intel],
              [:linux, :arm],
            ])
        end

        Homebrew::SimulateSystem.with(os: older_macos, arch: :arm) do
          expect(bump_cask_pr.send(:generate_system_options, c_on_system_depends_on_intel, new_version))
            .to eq([
              [older_macos, :intel],
              [older_macos, :arm],
              [:linux, :intel],
              [:linux, :arm],
            ])
        end
      end
    end

    context "when cask has `depends_on arch` scoped to an `on_os` block" do
      it "returns all arch combinations for `OnSystem::BASE_OS_OPTIONS`" do
        Homebrew::SimulateSystem.with(os: older_macos, arch: :arm) do
          cask = Cask::Cask.new("test-on-macos-scoped-depends-on-arm") do
            os macos: "darwin", linux: "linux"

            version "0.0.1,2"

            url "https://brew.sh/test-0.0.1.dmg"
            name "Test"
            desc "Test cask"
            homepage "https://brew.sh"

            on_macos do
              depends_on arch: :arm64
            end
          end

          expect(cask.depends_on.arch).to eq([{ type: :arm, bits: 64 }])
          expect(bump_cask_pr.send(:generate_system_options, cask, new_version))
            .to eq([
              [older_macos, :intel],
              [older_macos, :arm],
              [:linux, :intel],
              [:linux, :arm],
            ])
        end
      end
    end

    context "when cask has arch-specific versions" do
      let(:new_version_arm) { Homebrew::BumpVersionParser.new(arm: "1.2.3") }
      let(:new_version_intel) { Homebrew::BumpVersionParser.new(intel: "1.2.3") }
      let(:new_version_arm_intel) { Homebrew::BumpVersionParser.new(arm: "1.2.3", intel: "1.2.2") }
      let(:new_version_intel_arm) { Homebrew::BumpVersionParser.new(arm: "1.2.2", intel: "1.2.3") }

      it "returns an array only using archs of arch-specific versions" do
        Homebrew::SimulateSystem.with(os: :linux) do
          expect(bump_cask_pr.send(:generate_system_options, c_arm_intel, new_version_arm))
            .to eq([
              [newest_macos, :arm],
              [:linux, :arm],
            ])
          expect(bump_cask_pr.send(:generate_system_options, c_arm_intel, new_version_intel))
            .to eq([
              [newest_macos, :intel],
              [:linux, :intel],
            ])
          expect(bump_cask_pr.send(:generate_system_options, c_arm_intel, new_version_arm_intel))
            .to eq([
              [newest_macos, :arm],
              [newest_macos, :intel],
              [:linux, :arm],
              [:linux, :intel],
            ])
          expect(bump_cask_pr.send(:generate_system_options, c_arm_intel, new_version_intel_arm))
            .to eq([
              [newest_macos, :intel],
              [newest_macos, :arm],
              [:linux, :intel],
              [:linux, :arm],
            ])
        end

        Homebrew::SimulateSystem.with(os: older_macos) do
          expect(bump_cask_pr.send(:generate_system_options, c_arm_intel, new_version_arm))
            .to eq([
              [older_macos, :arm],
              [:linux, :arm],
            ])
          expect(bump_cask_pr.send(:generate_system_options, c_arm_intel, new_version_intel))
            .to eq([
              [older_macos, :intel],
              [:linux, :intel],
            ])
          expect(bump_cask_pr.send(:generate_system_options, c_arm_intel, new_version_arm_intel))
            .to eq([
              [older_macos, :arm],
              [older_macos, :intel],
              [:linux, :arm],
              [:linux, :intel],
            ])
          expect(bump_cask_pr.send(:generate_system_options, c_arm_intel, new_version_intel_arm))
            .to eq([
              [older_macos, :intel],
              [older_macos, :arm],
              [:linux, :intel],
              [:linux, :arm],
            ])
        end
      end
    end
  end

  describe "::check_throttle" do
    let(:c_throttle) do
      Cask::Cask.new("throttle-test") do
        version "1.2.3"

        url "https://brew.sh/test-#{version}.dmg"
        name "Test"
        desc "Test cask"
        homepage "https://brew.sh"

        livecheck do
          throttle 5
        end
      end
    end
    let(:new_version) { Homebrew::BumpVersionParser.new(general: "1.2.5") }
    let(:throttle_error) { "Error: throttle-test should only be updated every 5 releases on multiples of 5\n" }
    let(:tap) { Tap.fetch("test", "tap") }

    context "when cask is not in a tap" do
      it "outputs nothing" do
        expect { bump_cask_pr.send(:check_throttle, c, new_version:) }.not_to output.to_stderr
      end
    end

    context "when a livecheck throttle value isn't present" do
      it "does not throttle" do
        allow(c).to receive(:tap).and_return(tap)
        expect { bump_cask_pr.send(:check_throttle, c, new_version:) }.not_to output.to_stderr
      end
    end

    context "when new_version has no version values" do
      let(:empty_version) do
        version = new_version.clone
        version.remove_instance_variable(:@general)
        version
      end

      it "does not throttle" do
        allow(c_throttle).to receive(:tap).and_return(tap)
        expect do
          bump_cask_pr.send(:check_throttle, c_throttle, new_version: empty_version)
        end.not_to output.to_stderr
      end
    end

    context "when patch version is a multiple of throttle_rate" do
      it "does not throttle" do
        allow(c_throttle).to receive(:tap).and_return(tap)
        expect do
          bump_cask_pr.send(:check_throttle, c_throttle, new_version:)
        end.not_to output.to_stderr
      end
    end

    context "when patch version is not a multiple of throttle_rate" do
      let(:new_version_indivisible) { Homebrew::BumpVersionParser.new(general: "1.2.4") }

      it "throttles version" do
        allow(c_throttle).to receive(:tap).and_return(tap)
        expect do
          bump_cask_pr.send(:check_throttle, c_throttle, new_version: new_version_indivisible)
        rescue SystemExit
          next
        end.to output(throttle_error).to_stderr
      end
    end
  end
end
