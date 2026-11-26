# typed: strict
# frozen_string_literal: true

RSpec.describe Test::Helper::Formula do
  it "creates a formula in the test tap without loading the package API" do
    allow(Homebrew::API::Internal).to receive(:fetch_packages_api!).and_raise("unexpected API lookup")

    expect(formula("testball") do
      T.bind(self, T.class_of(::Formula))
      url "https://example.com/testball-1.0.tgz"
    end.tap).to eq(CoreTap.instance)
  end
end
