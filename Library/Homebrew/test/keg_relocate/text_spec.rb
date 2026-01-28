# frozen_string_literal: true

require "keg_relocate"

RSpec.describe Keg do
  subject(:keg) { described_class.new(HOMEBREW_CELLAR/"foo/1.0.0") }

  let(:dir) { mktmpdir }
  let(:file) { dir/"file.txt" }
  let(:placeholder) { "@@PLACEHOLDER@@" }

  before do
    (HOMEBREW_CELLAR/"foo/1.0.0").mkpath
  end

  def setup_file(placeholders: false)
    path = placeholders ? placeholder : dir
    file.atomic_write <<~EOS
      #{path}/file.txt
      /foo#{path}/file.txt
      foo/bar:#{path}/file.txt
      foo/bar:/foo#{path}/file.txt
      #{path}/bar.txt:#{path}/baz.txt
    EOS
  end

  def setup_relocation(placeholders: false)
    relocation = described_class::Relocation.new

    if placeholders
      relocation.add_replacement_pair :dir, placeholder, dir.to_s
    else
      relocation.add_replacement_pair :dir, dir.to_s, placeholder, path: true
    end

    relocation
  end

  specify "::text_matches_in_file" do
    setup_file

    result = described_class.text_matches_in_file(file, placeholder, [], [], nil)
    expect(result.count).to eq 0

    result = described_class.text_matches_in_file(file, dir.to_s, [], [], nil)
    expect(result.count).to eq 2
  end

  describe "#replace_text_in_files" do
    specify "with paths" do
      setup_file
      relocation = setup_relocation

      keg.replace_text_in_files(relocation, files: [file])
      contents = File.read file

      expect(contents).to eq <<~EOS
        #{placeholder}/file.txt
        /foo#{dir}/file.txt
        foo/bar:#{placeholder}/file.txt
        foo/bar:/foo#{dir}/file.txt
        #{placeholder}/bar.txt:#{placeholder}/baz.txt
      EOS
    end

    specify "with placeholders" do
      setup_file placeholders: true
      relocation = setup_relocation placeholders: true

      keg.replace_text_in_files(relocation, files: [file])
      contents = File.read file

      expect(contents).to eq <<~EOS
        #{dir}/file.txt
        /foo#{dir}/file.txt
        foo/bar:#{dir}/file.txt
        foo/bar:/foo#{dir}/file.txt
        #{dir}/bar.txt:#{dir}/baz.txt
      EOS
    end
  end
end
