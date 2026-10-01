# typed: true
# frozen_string_literal: true

require "keg"

RSpec.describe Keg, :needs_linux do
  subject(:keg) { described_class.new(keg_path) }

  let(:keg_path) { HOMEBREW_CELLAR/"a/1.0" }
  let(:file) { ELFPathname.wrap(keg_path/"bin/test") }

  before do
    file.dirname.mkpath
    FileUtils.cp(TEST_FIXTURE_DIR/"elf/c.elf", file)
    file.patch!(interpreter: "#{HOMEBREW_PREFIX}/lib/ld.so", rpath: "#{HOMEBREW_PREFIX}/lib")
  end

  after { keg.unlink }

  it "returns changed linkage files relative to the keg" do
    expect(keg.relocate_dynamic_linkage(keg.prepare_relocation_to_placeholders.freeze, with_placeholders: true))
      .to eq([Pathname("bin/test")])
  end

  it "relocates only recorded linkage files without walking the keg" do
    expect(keg).not_to receive(:elf_files)

    relocation = keg.prepare_relocation_to_placeholders.freeze
    expect(keg.relocate_dynamic_linkage(relocation, with_placeholders: true, files: [Pathname("bin/test")]))
      .to eq([Pathname("bin/test")])
  end
end
