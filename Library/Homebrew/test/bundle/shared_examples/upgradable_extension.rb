# typed: true
# frozen_string_literal: true

RSpec.shared_examples "an upgradable extension" do |name|
  let(:entry) { Homebrew::Bundle::Dsl::Entry.new(described_class.type, name.to_s) }

  before do
    allow(described_class).to receive_messages(package_manager_executable: Pathname(described_class.type.to_s),
                                               package_installed?: true, package_outdated?: true)
  end

  it "reports an installed package that needs upgrading" do
    expect(described_class.check([entry])).to eq(["#{described_class.check_label} #{name} needs to be upgraded."])
  end

  it "schedules an outdated package for installation" do
    expect(described_class.preinstall!(name)).to be(true)
  end

  it "does not query updates when checking with no_upgrade" do
    expect(described_class).not_to receive(:package_outdated?)
    described_class.check([entry], no_upgrade: true)
  end

  it "does not query updates when installing with no_upgrade" do
    expect(described_class).not_to receive(:package_outdated?)
    described_class.preinstall!(name, no_upgrade: true)
  end

  it "does not query updates for missing packages" do
    allow(described_class).to receive(:package_installed?).and_return(false)
    expect(described_class).not_to receive(:package_outdated?)
    described_class.check([entry])
  end

  it "does not query updates for an empty Brewfile" do
    expect(described_class).not_to receive(:package_outdated?)
    described_class.check([])
  end

  it "skips an up-to-date package" do
    allow(described_class).to receive(:package_outdated?).and_return(false)
    expect(described_class.preinstall!(name)).to be(false)
  end
end
