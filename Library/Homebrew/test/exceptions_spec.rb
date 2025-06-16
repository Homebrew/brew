# frozen_string_literal: true

require "exceptions"

RSpec.describe "Exception" do
  describe MultipleVersionsInstalledError do
    subject(:error) do
      described_class.new <<~EOS
        foo has multiple installed versions
        Run `brew uninstall --force foo` to remove all versions.
      EOS
    end

    it(:to_s) do
      expect(error.to_s).to eq <<~EOS
        foo has multiple installed versions
        Run `brew uninstall --force foo` to remove all versions.
      EOS
    end
  end

  describe NoSuchKegError do
    context "without a tap" do
      subject(:error) { described_class.new("foo") }

      it(:to_s) { expect(error.to_s).to eq("No such keg: #{HOMEBREW_CELLAR}/foo") }
    end

    context "with a tap" do
      subject(:error) { described_class.new("foo", tap:) }

      let(:tap) { instance_double(Tap, to_s: "u/r") }

      it(:to_s) { expect(error.to_s).to eq("No such keg: #{HOMEBREW_CELLAR}/foo from tap u/r") }
    end
  end

  describe FormulaValidationError do
    subject(:error) { described_class.new("foo", "sha257", "magic") }

    it(:to_s) do
      expect(error.to_s).to eq(%q(invalid attribute for formula 'foo': sha257 ("magic")))
    end
  end

  describe TapFormulaOrCaskUnavailableError do
    subject(:error) { described_class.new(tap, "foo") }

    let(:tap) { instance_double(Tap, user: "u", repository: "r", to_s: "u/r", installed?: false) }

    it(:to_s) { expect(error.to_s).to match(%r{Please tap it and then try again: brew tap u/r}) }
  end

  describe FormulaUnavailableError do
    subject(:error) { described_class.new("foo") }

    describe "#dependent_s" do
      it "returns nil if there is no dependent" do
        expect(error.dependent_s).to be_nil
      end

      it "returns nil if it depended on by itself" do
        error.dependent = "foo"
        expect(error.dependent_s).to be_nil
      end

      it "returns a string if there is a dependent" do
        error.dependent = "foobar"
        expect(error.dependent_s).to eq(" (dependency of foobar)")
      end
    end

    context "without a dependent" do
      it(:to_s) { expect(error.to_s).to match(/^No available formula with the name "foo"\./) }
    end

    context "with a dependent" do
      before do
        error.dependent = "foobar"
      end

      it(:to_s) do
        expect(error.to_s).to match(/^No available formula with the name "foo" \(dependency of foobar\)\./)
      end
    end
  end

  describe TapFormulaUnavailableError do
    subject(:error) { described_class.new(tap, "foo") }

    let(:tap) { instance_double(Tap, user: "u", repository: "r", to_s: "u/r", installed?: false) }

    it(:to_s) { expect(error.to_s).to match(%r{Please tap it and then try again: brew tap u/r}) }
  end

  describe FormulaClassUnavailableError do
    subject(:error) { described_class.new("foo", "foo.rb", "Foo", list) }

    let(:mod) do
      Module.new do
        # These are defined within an anonymous module to avoid polluting the global namespace.
        # rubocop:disable RSpec/LeakyConstantDeclaration,Lint/ConstantDefinitionInBlock
        class Bar < Requirement; end

        class Baz < Formula; end
        # rubocop:enable RSpec/LeakyConstantDeclaration,Lint/ConstantDefinitionInBlock
      end
    end

    context "when there are no classes" do
      let(:list) { [] }

      it(:to_s) do
        expect(error.to_s).to match(/Expected to find class Foo, but found no classes\./)
      end
    end

    context "when the class is not derived from Formula" do
      let(:list) { [mod.const_get(:Bar)] }

      it(:to_s) do
        expect(error.to_s).to match(/Expected to find class Foo, but only found: Bar \(not derived from Formula!\)\./)
      end
    end

    context "when the class is derived from Formula" do
      let(:list) { [mod.const_get(:Baz)] }

      it(:to_s) { expect(error.to_s).to match(/Expected to find class Foo, but only found: Baz\./) }
    end
  end

  describe FormulaUnreadableError do
    subject(:error) { described_class.new("foo", formula_error) }

    let(:formula_error) { LoadError.new("bar") }

    it(:to_s) { expect(error.to_s).to eq("foo: bar") }
  end

  describe TapUnavailableError do
    subject(:error) { described_class.new("foo") }

    it(:to_s) { expect(error.to_s).to eq("No available tap foo.\nRun brew tap-new foo to create a new foo tap!\n") }
  end

  describe TapAlreadyTappedError do
    subject(:error) { described_class.new("foo") }

    it(:to_s) { expect(error.to_s).to eq("Tap foo already tapped.\n") }
  end

  describe BuildError do
    subject(:error) { described_class.new(formula, "badprg", ["arg1", 2, Pathname.new("arg3"), :arg4], {}) }

    let(:formula) { instance_double(Formula, name: "foo") }

    it(:to_s) { expect(error.to_s).to eq("Failed executing: badprg arg1 2 arg3 arg4") }
  end

  describe OperationInProgressError do
    subject(:error) { described_class.new(Pathname("foo")) }

    it(:to_s) { expect(error.to_s).to match(/has already locked foo/) }
  end

  describe FormulaInstallationAlreadyAttemptedError do
    subject(:error) { described_class.new(formula) }

    let(:formula) { instance_double(Formula, full_name: "foo/bar") }

    it(:to_s) { expect(error.to_s).to eq("Formula installation already attempted: foo/bar") }
  end

  describe FormulaConflictError do
    subject(:error) { described_class.new(formula, [conflict]) }

    let(:formula) { instance_double(Formula, full_name: "foo/qux") }
    let(:conflict) { instance_double(FormulaConflict, name: "bar", reason: "I decided to") }

    it(:to_s) { expect(error.to_s).to match(/Please `brew unlink bar` before continuing\./) }
  end

  describe CompilerSelectionError do
    subject(:error) { described_class.new(formula) }

    let(:formula) { instance_double(Formula, full_name: "foo") }

    it(:to_s) { expect(error.to_s).to match(/foo cannot be built with any available compilers\./) }
  end

  describe CurlDownloadStrategyError do
    context "when the file does not exist" do
      subject(:error) { described_class.new("file:///tmp/foo") }

      it(:to_s) { expect(error.to_s).to eq("File does not exist: /tmp/foo") }
    end

    context "when the download failed" do
      subject(:error) { described_class.new("https://brew.sh") }

      it(:to_s) { expect(error.to_s).to eq("Download failed: https://brew.sh") }
    end
  end

  describe ErrorDuringExecution do
    subject(:error) { described_class.new(["badprg", "arg1", "arg2"], status:) }

    let(:status) { instance_double(Process::Status, exitstatus: 17, termsig: nil) }

    it(:to_s) { expect(error.to_s).to eq("Failure while executing; `badprg arg1 arg2` exited with 17.") }
  end

  describe ChecksumMismatchError do
    subject(:error) { described_class.new("/file.tar.gz", expected_checksum, actual_checksum) }

    let(:expected_checksum) { instance_double(Checksum, to_s: "deadbeef") }
    let(:actual_checksum) { instance_double(Checksum, to_s: "deadcafe") }

    it(:to_s) { expect(error.to_s).to match(/SHA256 mismatch/) }
  end

  describe ResourceMissingError do
    subject(:error) { described_class.new(formula, resource) }

    let(:formula) { instance_double(Formula, full_name: "bar") }
    let(:resource) { instance_double(Resource, inspect: "<resource foo>") }

    it(:to_s) { expect(error.to_s).to eq("bar does not define resource <resource foo>") }
  end

  describe DuplicateResourceError do
    subject(:error) { described_class.new(resource) }

    let(:resource) { instance_double(Resource, inspect: "<resource foo>") }

    it(:to_s) { expect(error.to_s).to eq("Resource <resource foo> is defined more than once") }
  end

  describe BottleFormulaUnavailableError do
    subject(:error) { described_class.new("/foo.bottle.tar.gz", "foo/1.0/.brew/foo.rb") }

    let(:formula) { instance_double(Formula, full_name: "foo") }

    it(:to_s) { expect(error.to_s).to match(/This bottle does not contain the formula file/) }
  end

  describe BuildFlagsError do
    subject(:error) { described_class.new(["-s"]) }

    it(:to_s) { expect(error.to_s).to match(/flag:\s+-s\nrequires building tools/) }
  end
end
