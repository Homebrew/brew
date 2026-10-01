# typed: true
# frozen_string_literal: true

require "keg_relocate"
require "stringio"

RSpec.describe Keg do
  subject(:keg) { described_class.new(HOMEBREW_CELLAR/"foo/1.0.0") }

  let(:dir) { HOMEBREW_CELLAR/"foo/1.0.0" }
  let(:file) { dir/"file.txt" }
  let(:placeholder) { "@@PLACEHOLDER@@" }

  before do
    dir.mkpath
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
    relocation = Keg::Relocation.new

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

  specify "::each_candidate_string still yields runs that are not valid UTF-8" do
    setup_file

    # `strings -` uses locale-dependent `isprint()`, so a run can include invalid
    # UTF-8. Detection must not drop it, or the build prefix could go undetected.
    fake_output = "2a53 \xFF\xFE#{dir}/bad\n1000 #{dir}/file.txt\n".b
    allow(Utils).to receive(:popen_read).and_yield(StringIO.new(fake_output))

    candidates = []
    described_class.each_candidate_string(file, dir.to_s) { |candidate| candidates << candidate }

    expect(candidates).to eq [["2a53", "\xFF\xFE#{dir}/bad".b], ["1000", "#{dir}/file.txt"]]
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

    specify "ignores recorded paths that escape the keg" do
      outside = dir.parent/"escape.txt"
      outside.atomic_write "#{placeholder}/file.txt\n"

      changed = keg.replace_text_in_files(setup_relocation(placeholders: true),
                                          files: [Pathname("../escape.txt"), outside])

      expect(outside.read).to eq "#{placeholder}/file.txt\n"
      expect(changed).to be_empty
    end

    specify "ignores recorded paths that escape the keg through a symlinked parent" do
      outside = dir.parent/"outside"
      outside.mkpath
      victim = outside/"victim.txt"
      victim.atomic_write "#{placeholder}/file.txt\n"
      FileUtils.ln_s outside, dir/"linked"

      changed = keg.replace_text_in_files(setup_relocation(placeholders: true),
                                          files: [Pathname("linked/victim.txt")])

      expect(victim.read).to eq "#{placeholder}/file.txt\n"
      expect(changed).to be_empty
    end

    specify "ignores recorded paths that do not exist" do
      expect { keg.replace_text_in_files(setup_relocation, files: [Pathname("missing.txt")]) }
        .not_to raise_error
    end
  end

  specify "#replace_locations_with_placeholders returns its file lists" do
    linkage_files = [Pathname("bin/foo")]
    changed_files = [Pathname("share/foo")]
    allow(keg).to receive_messages(relocate_dynamic_linkage: linkage_files, replace_text_in_files: changed_files)

    expect(keg.replace_locations_with_placeholders).to eq([changed_files, linkage_files])
  end
end
