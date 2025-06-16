# frozen_string_literal: true

require "test_runner_formula"
require "test/support/fixtures/testball"

RSpec.describe TestRunnerFormula do
  let(:testball) { Testball.new }
  let(:xcode_helper) { setup_test_formula("xcode-helper", [:macos]) }
  let(:linux_kernel_requirer) { setup_test_formula("linux-kernel-requirer", [:linux]) }
  let(:old_non_portable_software) { setup_test_formula("old-non-portable-software", [arch: :x86_64]) }
  let(:fancy_new_software) { setup_test_formula("fancy-new-software", [arch: :arm64]) }
  let(:needs_modern_compiler) { setup_test_formula("needs-modern-compiler", [macos: :ventura]) }

  describe "#initialize" do
    it "enables the Formulary factory cache" do
      described_class.new(testball)
      expect(Formulary.factory_cached?).to be(true)
    end
  end

  describe "#name" do
    it "returns the wrapped Formula's name" do
      expect(described_class.new(testball).name).to eq(testball.name)
    end
  end

  describe "#eval_all" do
    it "is false by default" do
      expect(described_class.new(testball).eval_all).to be(false)
    end

    it "can be instantiated to be `true`" do
      expect(described_class.new(testball, eval_all: true).eval_all).to be(true)
    end

    it "takes the value of `HOMEBREW_EVAL_ALL` at instantiation time if not specified" do
      allow(Homebrew::EnvConfig).to receive(:eval_all?).and_return(true)
      expect(described_class.new(testball).eval_all).to be(true)

      allow(Homebrew::EnvConfig).to receive(:eval_all?).and_return(false)
      expect(described_class.new(testball).eval_all).to be(false)
    end
  end

  describe "#formula" do
    it "returns the wrapped Formula" do
      expect(described_class.new(testball).formula).to eq(testball)
    end
  end

  describe "#macos_only?" do
    context "when a formula requires macOS" do
      it "returns true" do
        expect(described_class.new(xcode_helper).macos_only?).to be(true)
      end
    end

    context "when a formula does not require macOS" do
      it "returns false" do
        expect(described_class.new(testball).macos_only?).to be(false)
        expect(described_class.new(linux_kernel_requirer).macos_only?).to be(false)
        expect(described_class.new(old_non_portable_software).macos_only?).to be(false)
        expect(described_class.new(fancy_new_software).macos_only?).to be(false)
      end
    end

    context "when a formula requires only a minimum version of macOS" do
      it "returns false" do
        expect(described_class.new(needs_modern_compiler).macos_only?).to be(false)
      end
    end
  end

  describe "#macos_compatible?" do
    context "when a formula is compatible with macOS" do
      it "returns true" do
        expect(described_class.new(testball).macos_compatible?).to be(true)
        expect(described_class.new(xcode_helper).macos_compatible?).to be(true)
        expect(described_class.new(old_non_portable_software).macos_compatible?).to be(true)
        expect(described_class.new(fancy_new_software).macos_compatible?).to be(true)
      end
    end

    context "when a formula requires only a minimum version of macOS" do
      it "returns false" do
        expect(described_class.new(needs_modern_compiler).macos_compatible?).to be(true)
      end
    end

    context "when a formula is not compatible with macOS" do
      it "returns false" do
        expect(described_class.new(linux_kernel_requirer).macos_compatible?).to be(false)
      end
    end
  end

  describe "#linux_only?" do
    context "when a formula requires Linux" do
      it "returns true" do
        expect(described_class.new(linux_kernel_requirer).linux_only?).to be(true)
      end
    end

    context "when a formula does not require Linux" do
      it "returns false" do
        expect(described_class.new(testball).linux_only?).to be(false)
        expect(described_class.new(xcode_helper).linux_only?).to be(false)
        expect(described_class.new(old_non_portable_software).linux_only?).to be(false)
        expect(described_class.new(fancy_new_software).linux_only?).to be(false)
        expect(described_class.new(needs_modern_compiler).linux_only?).to be(false)
      end
    end
  end

  describe "#linux_compatible?" do
    context "when a formula is compatible with Linux" do
      it "returns true" do
        expect(described_class.new(testball).linux_compatible?).to be(true)
        expect(described_class.new(linux_kernel_requirer).linux_compatible?).to be(true)
        expect(described_class.new(old_non_portable_software).linux_compatible?).to be(true)
        expect(described_class.new(fancy_new_software).linux_compatible?).to be(true)
        expect(described_class.new(needs_modern_compiler).linux_compatible?).to be(true)
      end
    end

    context "when a formula is not compatible with Linux" do
      it "returns false" do
        expect(described_class.new(xcode_helper).linux_compatible?).to be(false)
      end
    end
  end

  describe "#x86_64_only?" do
    context "when a formula requires an Intel architecture" do
      it "returns true" do
        expect(described_class.new(old_non_portable_software).x86_64_only?).to be(true)
      end
    end

    context "when a formula requires a non-Intel architecture" do
      it "returns false" do
        expect(described_class.new(fancy_new_software).x86_64_only?).to be(false)
      end
    end

    context "when a formula does not require a specific architecture" do
      it "returns false" do
        expect(described_class.new(testball).x86_64_only?).to be(false)
        expect(described_class.new(xcode_helper).x86_64_only?).to be(false)
        expect(described_class.new(linux_kernel_requirer).x86_64_only?).to be(false)
        expect(described_class.new(needs_modern_compiler).x86_64_only?).to be(false)
      end
    end
  end

  describe "#x86_64_compatible?" do
    context "when a formula is compatible with the Intel architecture" do
      it "returns true" do
        expect(described_class.new(testball).x86_64_compatible?).to be(true)
        expect(described_class.new(xcode_helper).x86_64_compatible?).to be(true)
        expect(described_class.new(linux_kernel_requirer).x86_64_compatible?).to be(true)
        expect(described_class.new(old_non_portable_software).x86_64_compatible?).to be(true)
        expect(described_class.new(needs_modern_compiler).x86_64_compatible?).to be(true)
      end
    end

    context "when a formula is not compatible with the Intel architecture" do
      it "returns false" do
        expect(described_class.new(fancy_new_software).x86_64_compatible?).to be(false)
      end
    end
  end

  describe "#arm64_only?" do
    context "when a formula requires an ARM64 architecture" do
      it "returns true" do
        expect(described_class.new(fancy_new_software).arm64_only?).to be(true)
      end
    end

    context "when a formula requires a non-ARM64 architecture" do
      it "returns false" do
        expect(described_class.new(old_non_portable_software).arm64_only?).to be(false)
      end
    end

    context "when a formula does not require a specific architecture" do
      it "returns false" do
        expect(described_class.new(testball).arm64_only?).to be(false)
        expect(described_class.new(xcode_helper).arm64_only?).to be(false)
        expect(described_class.new(linux_kernel_requirer).arm64_only?).to be(false)
        expect(described_class.new(needs_modern_compiler).arm64_only?).to be(false)
      end
    end
  end

  describe "#arm64_compatible?" do
    context "when a formula is compatible with an ARM64 architecture" do
      it "returns true" do
        expect(described_class.new(testball).arm64_compatible?).to be(true)
        expect(described_class.new(xcode_helper).arm64_compatible?).to be(true)
        expect(described_class.new(linux_kernel_requirer).arm64_compatible?).to be(true)
        expect(described_class.new(fancy_new_software).arm64_compatible?).to be(true)
        expect(described_class.new(needs_modern_compiler).arm64_compatible?).to be(true)
      end
    end

    context "when a formula is not compatible with an ARM64 architecture" do
      it "returns false" do
        expect(described_class.new(old_non_portable_software).arm64_compatible?).to be(false)
      end
    end
  end

  describe "#versioned_macos_requirement" do
    let(:requirement) { described_class.new(needs_modern_compiler).versioned_macos_requirement }

    it "returns a MacOSRequirement with a specified version" do
      expect(requirement).to be_a(MacOSRequirement)
      expect(requirement.version_specified?).to be(true)
    end

    context "when a formula has an unversioned MacOSRequirement" do
      it "returns nil" do
        expect(described_class.new(xcode_helper).versioned_macos_requirement).to be_nil
      end
    end

    context "when a formula has no declared MacOSRequirement" do
      it "returns nil" do
        expect(described_class.new(testball).versioned_macos_requirement).to be_nil
        expect(described_class.new(linux_kernel_requirer).versioned_macos_requirement).to be_nil
        expect(described_class.new(old_non_portable_software).versioned_macos_requirement).to be_nil
        expect(described_class.new(fancy_new_software).versioned_macos_requirement).to be_nil
      end
    end
  end

  describe "#compatible_with?" do
    context "when a formula has a versioned MacOSRequirement" do
      context "when passed a compatible macOS version" do
        it "returns true" do
          expect(described_class.new(needs_modern_compiler).compatible_with?(MacOSVersion.new("13")))
            .to be(true)
        end
      end

      context "when passed an incompatible macOS version" do
        it "returns false" do
          expect(described_class.new(needs_modern_compiler).compatible_with?(MacOSVersion.new("11")))
            .to be(false)
        end
      end
    end

    context "when a formula has an unversioned MacOSRequirement" do
      it "returns true" do
        MacOSVersion::SYMBOLS.each_value do |v|
          version = MacOSVersion.new(v)
          expect(described_class.new(xcode_helper).compatible_with?(version)).to be(true)
        end
      end
    end

    context "when a formula has no declared MacOSRequirement" do
      it "returns true" do
        MacOSVersion::SYMBOLS.each_value do |v|
          version = MacOSVersion.new(v)
          expect(described_class.new(testball).compatible_with?(version)).to be(true)
          expect(described_class.new(linux_kernel_requirer).compatible_with?(version)).to be(true)
          expect(described_class.new(old_non_portable_software).compatible_with?(version)).to be(true)
          expect(described_class.new(fancy_new_software).compatible_with?(version)).to be(true)
        end
      end
    end
  end

  describe "#dependents" do
    let(:current_system) do
      current_arch = case Homebrew::SimulateSystem.current_arch
      when :arm then :arm64
      when :intel then :x86_64
      end

      current_platform = case Homebrew::SimulateSystem.current_os
      when :generic then :linux
      else Homebrew::SimulateSystem.current_os
      end

      {
        platform:      current_platform,
        arch:          current_arch,
        macos_version: nil,
      }
    end

    context "when a formula has no dependents" do
      it "returns an empty array" do
        expect(described_class.new(testball).dependents(**current_system)).to eq([])
        expect(described_class.new(xcode_helper).dependents(**current_system)).to eq([])
        expect(described_class.new(linux_kernel_requirer).dependents(**current_system)).to eq([])
        expect(described_class.new(old_non_portable_software).dependents(**current_system)).to eq([])
        expect(described_class.new(fancy_new_software).dependents(**current_system)).to eq([])
        expect(described_class.new(needs_modern_compiler).dependents(**current_system)).to eq([])
      end
    end

    context "when a formula has dependents" do
      let(:testball_user) { setup_test_formula("testball_user", ["testball"]) }
      let(:recursive_testball_dependent) { setup_test_formula("recursive_testball_dependent", ["testball_user"]) }

      it "returns an array of direct dependents" do
        allow(Formula).to receive(:all).and_return([testball_user, recursive_testball_dependent])

        expect(
          described_class.new(testball, eval_all: true).dependents(**current_system).map(&:name),
        ).to eq(["testball_user"])

        expect(
          described_class.new(testball_user, eval_all: true).dependents(**current_system).map(&:name),
        ).to eq(["recursive_testball_dependent"])
      end

      context "when called with arguments" do
        let(:testball_user_intel) { setup_test_formula("testball_user-intel", intel: ["testball"]) }
        let(:testball_user_arm) { setup_test_formula("testball_user-arm", arm: ["testball"]) }
        let(:testball_user_macos) { setup_test_formula("testball_user-macos", macos: ["testball"]) }
        let(:testball_user_linux) { setup_test_formula("testball_user-linux", linux: ["testball"]) }
        let(:testball_user_ventura) do
          setup_test_formula("testball_user-ventura", ventura: ["testball"])
        end
        let(:testball_and_dependents) do
          [
            testball_user,
            testball_user_intel,
            testball_user_arm,
            testball_user_macos,
            testball_user_linux,
            testball_user_ventura,
          ]
        end

        context "when given { platform: :linux, arch: :x86_64 }" do
          it "returns only the dependents for the requested platform and architecture" do
            allow(Formula).to receive(:all).and_wrap_original { testball_and_dependents }

            expect(
              described_class.new(testball, eval_all: true).dependents(
                platform: :linux, arch: :x86_64, macos_version: nil,
              ).map(&:name).sort,
            ).to eq(["testball_user", "testball_user-intel", "testball_user-linux"].sort)
          end
        end

        context "when given { platform: :macos, arch: :x86_64 }" do
          it "returns only the dependents for the requested platform and architecture" do
            allow(Formula).to receive(:all).and_wrap_original { testball_and_dependents }

            expect(
              described_class.new(testball, eval_all: true).dependents(
                platform: :macos, arch: :x86_64, macos_version: nil,
              ).map(&:name).sort,
            ).to eq(["testball_user", "testball_user-intel", "testball_user-macos"].sort)
          end
        end

        context "when given `{ platform: :macos, arch: :arm64 }`" do
          it "returns only the dependents for the requested platform and architecture" do
            allow(Formula).to receive(:all).and_wrap_original { testball_and_dependents }

            expect(
              described_class.new(testball, eval_all: true).dependents(
                platform: :macos, arch: :arm64, macos_version: nil,
              ).map(&:name).sort,
            ).to eq(["testball_user", "testball_user-arm", "testball_user-macos"].sort)
          end
        end

        context "when given `{ platform: :macos, arch: :x86_64, macos_version: :mojave }`" do
          it "returns only the dependents for the requested platform and architecture" do
            allow(Formula).to receive(:all).and_wrap_original { testball_and_dependents }

            expect(
              described_class.new(testball, eval_all: true).dependents(
                platform: :macos, arch: :x86_64, macos_version: :mojave,
              ).map(&:name).sort,
            ).to eq(["testball_user", "testball_user-intel", "testball_user-macos"].sort)
          end
        end

        context "when given `{ platform: :macos, arch: :arm64, macos_version: :ventura }`" do
          it "returns only the dependents for the requested platform and architecture" do
            allow(Formula).to receive(:all).and_wrap_original { testball_and_dependents }

            expect(
              described_class.new(testball, eval_all: true).dependents(
                platform: :macos, arch: :arm64, macos_version: :ventura,
              ).map(&:name).sort,
            ).to eq(%w[testball_user testball_user-arm testball_user-macos testball_user-ventura].sort)
          end
        end
      end
    end
  end

  def setup_test_formula(name, dependencies = [], **kwargs)
    formula name do
      url "https://brew.sh/#{name}-1.0.tar.gz"
      dependencies.each { |dependency| depends_on dependency }

      kwargs.each do |k, v|
        send(:"on_#{k}") do
          v.each do |dep|
            depends_on dep
          end
        end
      end
    end
  end
end
