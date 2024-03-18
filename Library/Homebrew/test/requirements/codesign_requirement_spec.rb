# frozen_string_literal: true

require "requirements/codesign_requirement"

RSpec.describe CodesignRequirement do
  subject(:requirement) do
    described_class.new([{ identity:, with:, url: }])
  end

  let(:identity) { "lldb_codesign" }
  let(:with) { "LLDB" }
  let(:url) do
    "https://llvm.org/svn/llvm-project/lldb/trunk/docs/code-signing.txt"
  end

  describe "#message" do
    it "includes all parameters" do
      expect(requirement.message).to include(identity)
      expect(requirement.message).to include(with)
      expect(requirement.message).to include(url)
    end
  end
end
