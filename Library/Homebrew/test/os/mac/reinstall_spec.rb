# typed: false
# frozen_string_literal: true

require "reinstall"
require "extend/os/mac/pkgconf"

RSpec.describe Homebrew::Reinstall do
  describe ".reinstall_pkgconf_if_needed!" do
    let(:formula) { instance_double(Formula) }
    let(:formula_installer) do
      instance_double(FormulaInstaller, formula:, prelude_fetch: true, prelude: true, fetch: true)
    end
    let(:context) { instance_double(described_class::InstallationContext, formula_installer:) }

    before do
      allow(Formula).to receive(:[]).with("pkgconf").and_return(formula)
      allow(Homebrew::Install).to receive(:fetch_formulae).with([formula_installer])
      allow(described_class).to receive(:build_install_context).and_return(context)
    end

    context "when there is no macOS SDK mismatch" do
      it "does nothing" do
        allow(Homebrew::Pkgconf).to receive(:macos_sdk_mismatch).and_return(nil)
        expect(described_class).not_to receive(:reinstall_formula)

        described_class.reinstall_pkgconf_if_needed!
      end
    end

    context "when dry_run is true" do
      it "prints a warning and does not reinstall" do
        allow(Homebrew::Pkgconf).to receive_messages(
          macos_sdk_mismatch:       :mismatch,
          mismatch_warning_message: "warning",
        )
        expect(described_class).not_to receive(:reinstall_formula)
        expect(described_class).to receive(:opoo).with(/would be reinstalled/)

        described_class.reinstall_pkgconf_if_needed!(dry_run: true)
      end
    end

    context "when there is a mismatch and reinstall succeeds" do
      it "reinstalls pkgconf and prints success" do
        allow(Homebrew::Pkgconf).to receive(:macos_sdk_mismatch).and_return(:mismatch)
        expect(described_class).to receive(:reinstall_formula).with(context)
        expect(described_class).to receive(:ohai).with(/Reinstalled pkgconf/)

        described_class.reinstall_pkgconf_if_needed!
      end
    end

    context "when reinstall_formula raises an error" do
      it "rescues and prints the mismatch warning" do
        allow(Homebrew::Pkgconf).to receive_messages(
          macos_sdk_mismatch:       :mismatch,
          mismatch_warning_message: "warning",
        )
        allow(described_class).to receive(:reinstall_formula).and_raise(RuntimeError)

        expect(described_class).to receive(:ofail).with("warning")

        described_class.reinstall_pkgconf_if_needed!
      end
    end
  end
end
