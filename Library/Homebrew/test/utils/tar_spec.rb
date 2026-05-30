# typed: true
# frozen_string_literal: true

require "utils/tar"

RSpec.describe Utils::Tar do
  let(:klass) { Utils::Tar }

  before do
    klass.clear_executable_cache
  end

  describe ".available?" do
    it "returns true if tar or gnu-tar is available" do
      if klass.executable.present?
        expect(klass).to be_available
      else
        expect(klass).not_to be_available
      end
    end
  end

  describe ".validate_file" do
    it "does not raise an error when tar and gnu-tar are unavailable" do
      allow(klass).to receive(:available?).and_return false
      expect { klass.validate_file "blah" }.not_to raise_error
    end

    context "when tar or gnu-tar is available" do
      let(:testball_resource) { "#{TEST_FIXTURE_DIR}/tarballs/testball-0.1.tbz" }
      let(:invalid_resource) { "#{TEST_TMPDIR}/invalid.tgz" }

      before do
        allow(klass).to receive(:available?).and_return true
      end

      it "does not raise an error if file is not a tar file" do
        expect { klass.validate_file "blah" }.not_to raise_error
      end

      it "does not raise an error if file is valid tar file" do
        expect { klass.validate_file testball_resource }.not_to raise_error
      end

      it "raises an error if file is an invalid tar file" do
        FileUtils.touch invalid_resource
        expect { klass.validate_file invalid_resource }.to raise_error SystemExit
        FileUtils.rm_f invalid_resource
      end
    end
  end
end
