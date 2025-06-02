# frozen_string_literal: true

require "formula"
require "cxxstdlib"

RSpec.describe CxxStdlib do
  let(:clang) { described_class.create(:libstdcxx, :clang) }
  let(:lcxx) { described_class.create(:libcxx, :clang) }

  describe "#type_string" do
    specify "formatting" do
      expect(clang.type_string).to eq("libstdc++")
      expect(lcxx.type_string).to eq("libc++")
    end
  end
end
