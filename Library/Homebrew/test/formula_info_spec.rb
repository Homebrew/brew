# frozen_string_literal: true

require "formula_info"

RSpec.describe FormulaInfo, :integration_test do
  it "tests the FormulaInfo class" do
    install_test_formula "testball"

    info = described_class.lookup(Formula["testball"].path)
    expect(info).not_to be_nil
    expect(info.revision).to eq(0)
    expect(info.bottle_tags).to eq([])
    expect(info.bottle_info).to be_nil
    expect(info.bottle_info_any).to be_nil
    expect(info.any_bottle_tag).to be_nil
    expect(info.version(:stable).to_s).to eq("0.1")

    version = info.version(:stable)
    expect(info.pkg_version).to eq(PkgVersion.new(version, 0))
  end
end
