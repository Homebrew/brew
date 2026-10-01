# typed: false
# frozen_string_literal: true

require "missing_formula"

RSpec.describe Homebrew::MissingFormula do
  describe "::reason" do
    subject { described_class.reason("gem") }

    it { is_expected.not_to be_nil }
  end

  describe "::disallowed_reason" do
    matcher :disallow do |name|
      match do |expected|
        expected.disallowed_reason(name)
      end
    end

    specify(:aggregate_failures) do
      expect(described_class).to disallow("gem")
      expect(described_class).to disallow("pip")
      expect(described_class).to disallow("pil")
      expect(described_class).to disallow("macruby")
      expect(described_class).to disallow("lzma")
      expect(described_class).to disallow("gsutil")
      expect(described_class).to disallow("gfortran")
      expect(described_class).to disallow("play")
      expect(described_class).to disallow("haskell-platform")
      expect(described_class).to disallow("mysqldump-secure")
      expect(described_class).to disallow("ngrok")
    end

    it("disallows Xcode", :needs_macos) { is_expected.to disallow("xcode") }
  end

  describe "::tap_migration_reason" do
    subject(:reason) { described_class.tap_migration_reason(formula) }

    let(:migration_target) { "homebrew/bar" }

    before do
      tap_path = HOMEBREW_TAP_DIRECTORY/"homebrew/homebrew-foo"
      tap_path.mkpath
      (tap_path/"tap_migrations.json").write <<~JSON
        { "migrated-formula": "#{migration_target}" }
      JSON
    end

    context "with a migrated formula" do
      let(:formula) { "migrated-formula" }

      it { is_expected.not_to be_nil }
    end

    context "with a missing formula" do
      let(:formula) { "missing-formula" }

      it { is_expected.to be_nil }
    end

    context "with a same-tap renamed formula" do
      let(:formula) { "migrated-formula" }
      let(:migration_target) { "renamed-formula" }

      specify(:aggregate_failures) do
        expect(reason).to include("brew install renamed-formula")
        expect(reason).not_to include("brew tap")
      end
    end
  end

  describe "::deleted_reason" do
    subject { described_class.deleted_reason(formula, silent: true) }

    before do
      tap_path = HOMEBREW_TAP_DIRECTORY/"homebrew/homebrew-foo"
      (tap_path/"Formula").mkpath
      (tap_path/"Formula/deleted-formula.rb").write "placeholder"
      ENV.delete "GIT_AUTHOR_DATE"
      ENV.delete "GIT_COMMITTER_DATE"

      tap_path.cd do
        system "git", "init"
        system "git", "add", "--all"
        system "git", "commit", "-m", "initial state"
        system "git", "rm", "Formula/deleted-formula.rb"
        system "git", "commit", "-m", "delete formula 'deleted-formula'"
      end
    end

    shared_examples "it detects deleted formulae" do
      context "with a deleted formula" do
        let(:formula) { "homebrew/foo/deleted-formula" }

        it { is_expected.not_to be_nil }
      end

      context "with a formula that never existed" do
        let(:formula) { "homebrew/foo/missing-formula" }

        it { is_expected.to be_nil }
      end
    end

    include_examples "it detects deleted formulae"

    describe "on the core tap" do
      before do
        allow_any_instance_of(Tap).to receive(:core_tap?).and_return(true)
      end

      include_examples "it detects deleted formulae"
    end
  end

  describe "::cask_reason", :cask do
    subject(:reason) { described_class.cask_reason(formula, show_info:) }

    context "with a formula name that is a cask and show_info: false" do
      let(:formula) { "local-caffeine" }
      let(:show_info) { false }

      specify(:aggregate_failures) do
        expect(reason).to match(/Found a cask named "local-caffeine" instead./)
        expect(reason).to match(/Try\n  brew install --cask local-caffeine/)
      end
    end

    context "with a formula name that is a cask and show_info: true" do
      let(:formula) { "local-caffeine" }
      let(:show_info) { true }

      it { is_expected.to match(/Found a cask named "local-caffeine" instead.\n\n==> local-caffeine: 1.2.3\n/) }
    end

    context "with a formula name that is not a cask" do
      let(:formula) { "missing-formula" }
      let(:show_info) { false }

      it { is_expected.to be_nil }
    end
  end

  describe "::suggest_command", :cask do
    subject(:reason) { described_class.suggest_command(name, command) }

    context "when installing" do
      let(:name) { "local-caffeine" }
      let(:command) { "install" }

      specify(:aggregate_failures) do
        expect(reason).to match(/Found a cask named "local-caffeine" instead./)
        expect(reason).to match(/Try\n  brew install --cask local-caffeine/)
      end
    end

    context "when uninstalling" do
      let(:name) { "local-caffeine" }
      let(:command) { "uninstall" }

      it { is_expected.to be_nil }

      context "with described cask installed" do
        before do
          allow(Cask::Caskroom).to receive(:casks).and_return(["local-caffeine"])
        end

        specify(:aggregate_failures) do
          expect(reason).to match(/Found a cask named "local-caffeine" instead./)
          expect(reason).to match(/Try\n  brew uninstall --cask local-caffeine/)
        end
      end
    end

    context "when getting info" do
      let(:name) { "local-caffeine" }
      let(:command) { "info" }

      specify(:aggregate_failures) do
        expect(reason).to match(/Found a cask named "local-caffeine" instead./)
        expect(reason).to match(/local-caffeine: 1.2.3/)
      end
    end
  end
end
