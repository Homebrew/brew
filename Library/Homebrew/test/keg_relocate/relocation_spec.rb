# frozen_string_literal: true

require "keg_relocate"

RSpec.describe Keg::Relocation do
  let(:prefix) { HOMEBREW_PREFIX.to_s }
  let(:cellar) { HOMEBREW_CELLAR.to_s }
  let(:repository) { HOMEBREW_REPOSITORY.to_s }
  let(:library) { HOMEBREW_LIBRARY.to_s }
  let(:prefix_placeholder) { "@@HOMEBREW_PREFIX@@" }
  let(:cellar_placeholder) { "@@HOMEBREW_CELLAR@@" }
  let(:repository_placeholder) { "@@HOMEBREW_REPOSITORY@@" }
  let(:library_placeholder) { "@@HOMEBREW_LIBRARY@@" }
  let(:escaped_prefix) { /(?:(?<=-F|-I|-L|-isystem)|(?<![a-zA-Z0-9]))#{Regexp.escape(HOMEBREW_PREFIX)}/o }
  let(:escaped_cellar) { /(?:(?<=-F|-I|-L|-isystem)|(?<![a-zA-Z0-9]))#{HOMEBREW_CELLAR}/o }

  def setup_relocation
    relocation = described_class.new
    relocation.add_replacement_pair :prefix, prefix, prefix_placeholder, path: true
    relocation.add_replacement_pair :cellar, /#{cellar}/o, cellar_placeholder, path: true
    relocation.add_replacement_pair :repository_placeholder, repository_placeholder, repository
    relocation.add_replacement_pair :library_placeholder, library_placeholder, library
    relocation
  end

  specify "#add_replacement_pair" do
    relocation = setup_relocation

    expect(relocation.replacement_pair_for(:prefix)).to eq [escaped_prefix, prefix_placeholder]
    expect(relocation.replacement_pair_for(:cellar)).to eq [escaped_cellar, cellar_placeholder]
    expect(relocation.replacement_pair_for(:repository_placeholder)).to eq [repository_placeholder, repository]
    expect(relocation.replacement_pair_for(:library_placeholder)).to eq [library_placeholder, library]
  end

  specify "#replace_text!" do
    relocation = setup_relocation

    text = +"foo"
    relocation.replace_text!(text)
    expect(text).to eq "foo"

    text = <<~TEXT
      #{prefix}/foo
      #{cellar}/foo
      foo#{prefix}/bar
      foo#{cellar}/bar
      #{repository_placeholder}/foo
      foo#{library_placeholder}/bar
    TEXT
    relocation.replace_text!(text)
    expect(text).to eq <<~REPLACED
      #{prefix_placeholder}/foo
      #{cellar_placeholder}/foo
      foo#{prefix}/bar
      foo#{cellar}/bar
      #{repository}/foo
      foo#{library}/bar
    REPLACED
  end

  specify "::path_to_regex" do
    expect(described_class.path_to_regex(prefix)).to eq escaped_prefix
    expect(described_class.path_to_regex("foo.bar")).to eq(/(?:(?<=-F|-I|-L|-isystem)|(?<![a-zA-Z0-9]))foo\.bar/)
    expect(described_class.path_to_regex(/#{cellar}/o)).to eq escaped_cellar
    expect(described_class.path_to_regex(/foo.bar/)).to eq(/(?:(?<=-F|-I|-L|-isystem)|(?<![a-zA-Z0-9]))foo.bar/)
  end
end
