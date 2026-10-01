# typed: true
# frozen_string_literal: true

require_relative "shared_examples"

RSpec.describe UnpackStrategy::Tar do
  subject(:path) { TEST_FIXTURE_DIR/"cask/container.tar.gz" }

  include_examples "UnpackStrategy::detect"
  include_examples "#extract", children: ["container"]

  it "keeps decompression intermediates in the configured temporary directory" do
    temporary_directory = mktmpdir
    unpack_dir = mktmpdir
    strategy = described_class.new(TEST_FIXTURE_DIR/"tarballs/testball-0.1.tbz", temporary_directory:)
    allow(DependencyCollector).to receive(:tar_needs_bzip2_dependency?).and_return(true)
    temporary_parents = []
    allow(Dir).to receive(:mktmpdir).and_wrap_original do |original, *args, &block|
      temporary_parents << Pathname(args.fetch(1)) if args.first.to_s.start_with?("homebrew-tar")
      original.call(*args, &block)
    end

    strategy.extract(to: unpack_dir)

    expect([temporary_parents, (unpack_dir/"test-0.1/libexec/NOOP").file?, temporary_directory.children])
      .to eq([[temporary_directory], true, []])
  end

  context "when TAR archive is corrupted" do
    subject(:path) do
      (mktmpdir/"test.tar").tap do |path|
        FileUtils.touch path
      end
    end

    include_examples "UnpackStrategy::detect"
  end
end
