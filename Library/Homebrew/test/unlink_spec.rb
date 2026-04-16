# typed: false
# frozen_string_literal: true

require "unlink"

RSpec.describe Homebrew::Unlink do
  describe ".unlink_link_overwrite_formulae" do
    let(:formula) { instance_double(Formula, keg_only?: false) }
    let(:linked_keg_only_keg) { instance_double(Keg, directory?: true) }
    let(:linked_keg_only_formula) do
      instance_double(Formula, linked?: true, keg_only?: true, any_installed_keg: linked_keg_only_keg)
    end
    let(:linked_non_keg_only_keg) { instance_double(Keg, directory?: true) }
    let(:linked_non_keg_only_formula) do
      instance_double(Formula, linked?: true, keg_only?: false,
                               any_installed_keg: linked_non_keg_only_keg)
    end
    let(:unlinked_formula) do
      instance_double(Formula, linked?: false, keg_only?: true, any_installed_keg: nil)
    end

    it "only unlinks linked keg-only sibling formulae for non-keg-only formulae" do
      allow(formula).to receive(:link_overwrite_formulae)
        .and_return([linked_keg_only_formula, linked_non_keg_only_formula, unlinked_formula])
      expect(described_class).to receive(:unlink).with(linked_keg_only_keg, verbose: true).once
      expect(described_class).not_to receive(:unlink).with(linked_non_keg_only_keg, verbose: true)

      described_class.unlink_link_overwrite_formulae(formula, verbose: true)
    end

    it "unlinks all linked sibling formulae for keg-only formulae" do
      allow(formula).to receive_messages(keg_only?:               true,
                                         link_overwrite_formulae: [linked_keg_only_formula,
                                                                   linked_non_keg_only_formula,
                                                                   unlinked_formula])
      expect(described_class).to receive(:unlink).with(linked_keg_only_keg, verbose: true).once
      expect(described_class).to receive(:unlink).with(linked_non_keg_only_keg, verbose: true).once

      described_class.unlink_link_overwrite_formulae(formula, verbose: true)
    end
  end
end
