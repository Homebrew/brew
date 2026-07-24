# typed: true
# frozen_string_literal: true

require "cask/auditor"

RSpec.describe Cask::Auditor, :cask do
  subject(:auditor) { described_class }

  describe "audit" do
    it "returns an empty Set if there are no audit errors" do
      basic_cask = Cask::CaskLoader.load(cask_path("basic-cask"))
      expect(auditor.audit(basic_cask)).to eq(Set.new)

      with_languages_cask = Cask::CaskLoader.load(cask_path("with-languages"))
      expect(auditor.audit(with_languages_cask)).to eq(Set.new)

      with_many_languages_cask = Cask::CaskLoader.load(cask_path("with-many-languages"))
      expect(auditor.audit(with_many_languages_cask)).to eq(Set.new)
    end

    it "returns a Set of Audit::Error hashes if there are audit errors" do
      error_hash = {
        message:   "sha256 string must be of 64 hexadecimal characters",
        location:  nil,
        corrected: false,
      }

      invalid_sha256_cask = Cask::CaskLoader.load(cask_path("invalid-sha256"))
      expect(auditor.audit(invalid_sha256_cask)).to eq(Set[error_hash])

      with_many_languages_and_error_cask = Cask::CaskLoader.load(cask_path("with-many-languages-and-invalid-sha256"))
      expect(auditor.audit(with_many_languages_and_error_cask)).to eq(Set[error_hash])
      expect(auditor.audit(with_many_languages_and_error_cask, audit_strict: true)).to eq(Set[error_hash])
    end
  end

  describe "output_summary?" do
    let(:cask) { Cask::CaskLoader.load(cask_path("basic-cask")) }

    it "returns true if @any_named_args is true" do
      auditor_obj = auditor.new(cask, any_named_args: true)
      expect(auditor_obj.output_summary?).to be(true)
    end

    it "returns true if @audit_strict is true" do
      auditor_obj = auditor.new(cask, audit_strict: true)
      expect(auditor_obj.output_summary?).to be(true)
    end

    it "returns false if the audit argument is nil" do
      auditor_obj = auditor.new(cask)
      expect(auditor_obj.output_summary?).to be(false)
      expect(auditor_obj.output_summary?(nil)).to be(false)
    end

    it "returns false if there are no audit errors" do
      auditor_obj = auditor.new(cask)
      audit = Cask::Audit.new(cask)
      expect(auditor_obj.output_summary?(audit)).to be(false)
    end

    it "returns true if there are audit errors" do
      auditor_obj = auditor.new(cask)
      audit = Cask::Audit.new(cask)
      audit.add_error(nil)
      expect(auditor_obj.output_summary?(audit)).to be(true)
    end
  end
end
