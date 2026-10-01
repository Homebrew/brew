# typed: true
# frozen_string_literal: true

require_relative "shared_examples"

RSpec.describe UnpackStrategy::Gzip do
  subject(:path) { TEST_FIXTURE_DIR/"cask/container.gz" }

  include_examples "UnpackStrategy::detect"
  include_examples "#extract", children: ["container"], verbose: true

  it "preserves the temporary directory through nested decompression" do
    temporary_directory = mktmpdir
    unpack_dir = mktmpdir
    archive = mktmpdir/"container.gz"
    FileUtils.cp(path, archive)
    system "bzip2", archive.to_s
    strategy = UnpackStrategy::Bzip2.new(Pathname("#{archive}.bz2"), temporary_directory:)
    temporary_parents = []
    allow(Dir).to receive(:mktmpdir).and_wrap_original do |original, *args, &block|
      temporary_parents << Pathname(args.fetch(1)) if args.first.to_s.start_with?("homebrew-unpack")
      original.call(*args, &block)
    end

    strategy.extract_nestedly(to: unpack_dir)

    expect([temporary_parents, (unpack_dir/"container").file?, temporary_directory.children])
      .to eq([[temporary_directory, temporary_directory], true, []])
  end
end
