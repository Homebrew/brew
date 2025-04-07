# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/bump-cask-pr"

RSpec.describe Homebrew::DevCmd::BumpCaskPr do
  subject(:bump_cask_pr) { described_class.new(["test"]) }

  let(:newest_macos) { MacOSVersion::SYMBOLS.keys.first }

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

  it_behaves_like "parseable arguments"

  describe "::shortened_version" do
    context "when `cask.version` is `nil`" do
      let(:c_no_version) do
        Cask::Cask.new("test-no-version") do
          url "https://brew.sh/test-0.0.2.dmg"
          name "Test"
          desc "Test cask"
          homepage "https://brew.sh"
        end
      end

      it "raises an error" do
        expect { bump_cask_pr.send(:shortened_version, c.version, cask: c_no_version) }
          .to raise_error(Cask::CaskInvalidError, /invalid 'version' value: nil/i)
      end
    end

    context "when `version` and `cask.version` have the same `before_comma` value" do
      it "returns the full version" do
        expect(bump_cask_pr.send(:shortened_version, c.version, cask: c)).to eq(c.version)
      end
    end

    context "when `version` and `cask.version` do not have the same `before_comma` value" do
      let(:c_newer_version) do
        Cask::Cask.new("test-different-version") do
          version "0.0.2,3"

          url "https://brew.sh/test-0.0.2.dmg"
          name "Test"
          desc "Test cask"
          homepage "https://brew.sh"
        end
      end

      it "returns the `before_comma` version" do
        expect(bump_cask_pr.send(:shortened_version, c_newer_version.version, cask: c))
          .to eq(c_newer_version.version.before_comma)
      end
    end
  end

  describe "::generate_system_options" do
    # We simulate a macOS version older than the newest, as the method will use
    # the host macOS version instead of the default (the newest macOS version).
    let(:older_macos) { :big_sur }

    context "when cask does not have on_system blocks/calls or `depends_on arch`" do
      it "returns an array only including macOS/ARM" do
        Homebrew::SimulateSystem.with(os: :linux) do
          expect(bump_cask_pr.send(:generate_system_options, c))
            .to eq([[newest_macos, :arm]])
        end

        Homebrew::SimulateSystem.with(os: older_macos) do
          expect(bump_cask_pr.send(:generate_system_options, c))
            .to eq([[older_macos, :arm]])
        end
      end
    end

    context "when cask does not have on_system blocks/calls but has `depends_on arch`" do
      it "returns an array only including macOS/`depends_on arch` value" do
        Homebrew::SimulateSystem.with(os: :linux, arch: :arm) do
          expect(bump_cask_pr.send(:generate_system_options, c_depends_on_intel))
            .to eq([[newest_macos, :intel]])
        end

        Homebrew::SimulateSystem.with(os: older_macos, arch: :arm) do
          expect(bump_cask_pr.send(:generate_system_options, c_depends_on_intel))
            .to eq([[older_macos, :intel]])
        end
      end
    end

    context "when cask has on_system blocks/calls but does not have `depends_on arch`" do
      it "returns an array with combinations of `OnSystem::BASE_OS_OPTIONS` and `OnSystem::ARCH_OPTIONS`" do
        Homebrew::SimulateSystem.with(os: :linux) do
          expect(bump_cask_pr.send(:generate_system_options, c_on_system))
            .to eq([
              [newest_macos, :intel],
              [newest_macos, :arm],
              [:linux, :intel],
              [:linux, :arm],
            ])
        end

        Homebrew::SimulateSystem.with(os: older_macos) do
          expect(bump_cask_pr.send(:generate_system_options, c_on_system))
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
      it "returns an array with combinations of `OnSystem::BASE_OS_OPTIONS` and `depends_on arch` value" do
        Homebrew::SimulateSystem.with(os: :linux, arch: :arm) do
          expect(bump_cask_pr.send(:generate_system_options, c_on_system_depends_on_intel))
            .to eq([
              [newest_macos, :intel],
              [:linux, :intel],
            ])
        end

        Homebrew::SimulateSystem.with(os: older_macos, arch: :arm) do
          expect(bump_cask_pr.send(:generate_system_options, c_on_system_depends_on_intel))
            .to eq([
              [older_macos, :intel],
              [:linux, :intel],
            ])
        end
      end
    end
  end
end
