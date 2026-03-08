# typed: true
# frozen_string_literal: true

require "unlink"

RSpec.describe Homebrew::Unlink do
  describe ".unlink_link_overwrite_formulae" do
    let(:formula) { instance_double(Formula) }
    let(:linked_keg) { instance_double(Keg, directory?: true) }
    let(:linked_formula) { instance_double(Formula, keg_only?: true, linked?: true, any_installed_keg: linked_keg) }
    let(:linked_non_keg_only_keg) { instance_double(Keg, directory?: true) }
    let(:linked_non_keg_only_formula) do
      instance_double(Formula, keg_only?: false, linked?: true, any_installed_keg: linked_non_keg_only_keg)
    end
    let(:unlinked_formula) { instance_double(Formula, keg_only?: true, linked?: false, any_installed_keg: nil) }

    it "unlinks linked sibling formulae returned by link_overwrite_formulae" do
      allow(formula).to receive(:link_overwrite_formulae)
        .and_return([linked_formula, linked_non_keg_only_formula, unlinked_formula])
      expect(described_class).to receive(:unlink).with(linked_keg, verbose: true).once
      expect(described_class).to receive(:unlink).with(linked_non_keg_only_keg, verbose: true).once

      described_class.unlink_link_overwrite_formulae(formula, verbose: true)
    end
  end
end
