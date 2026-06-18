# typed: strict
# frozen_string_literal: true

require "cmd/fetch"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::FetchCmd do
  it_behaves_like "parseable arguments"

  it "uses API bottle metadata before loading simple core formulae" do
    cmd = described_class.new(["fast-fetch"])
    download_queue = instance_double(Homebrew::DownloadQueue, fetch: nil, shutdown: nil)
    bottle_tag = with_env(HOMEBREW_TEST_GENERIC_OS: nil) { Utils::Bottles.tag }
    formula_struct = Homebrew::API::FormulaStruct.from_hash(
      "bottle_checksums"     => [
        {
          cellar:            :any_skip_relocation,
          bottle_tag.to_sym => "d7b9f4e8bf83608b71fe958a99f19f2e5e68bb2582965d32e41759c24f1aef97",
        },
      ],
      "bottle_present"       => true,
      "desc"                 => "fast fetch",
      "homepage"             => "https://brew.sh",
      "license"              => "MIT",
      "ruby_source_checksum" => "abc123",
      "stable_present"       => true,
      "stable_version"       => "1.0",
    )
    enqueued_downloads = []

    allow(Homebrew::DownloadQueue).to receive(:new).and_return(download_queue)
    allow(download_queue).to receive(:enqueue) { |download| enqueued_downloads << download }
    allow(Homebrew::API::Internal).to receive_messages(
      formula_aliases: {},
      formula_hashes:  { "fast-fetch" => {} },
      formula_renames: {},
      formula_struct:  formula_struct,
    )

    expect(cmd.args.named).not_to receive(:to_formulae_and_casks)
    expect(Formulary).not_to receive(:factory)
    expect(download_queue).to receive(:shutdown)

    with_env(HOMEBREW_TEST_GENERIC_OS: nil) { cmd.run }

    expect(enqueued_downloads).to include(an_instance_of(Bottle))
  end

  it "uses API cask metadata before loading simple core casks" do
    cmd = described_class.new(["--cask", "fast-cask"])
    download_queue = instance_double(Homebrew::DownloadQueue, fetch: nil, shutdown: nil)
    cask_struct = Homebrew::API::CaskStruct.new(
      sha256:   "d7b9f4e8bf83608b71fe958a99f19f2e5e68bb2582965d32e41759c24f1aef97",
      url_args: ["https://example.com/fast-cask.zip"],
      version:  "1.0",
    )
    enqueued_downloads = []

    allow(Homebrew::DownloadQueue).to receive(:new).and_return(download_queue)
    allow(download_queue).to receive(:enqueue) { |download| enqueued_downloads << download }
    allow(Homebrew::API::Internal).to receive_messages(
      cask_hashes:  { "fast-cask" => {} },
      cask_renames: {},
      cask_struct:  cask_struct,
    )

    expect(cmd.args.named).not_to receive(:to_formulae_and_casks)
    expect(Cask::CaskLoader).not_to receive(:load)
    expect(download_queue).to receive(:shutdown)

    with_env(HOMEBREW_TEST_GENERIC_OS: nil) { cmd.run }

    expect(enqueued_downloads).to include(an_instance_of(Cask::Download))
  end

  it "downloads Formula and Cask URLs concurrently", :cask, :integration_test do
    setup_test_formula "testball1"
    setup_test_formula "testball2"

    expect { brew "fetch", "testball1", "testball2", "local-caffeine" }.to be_a_success

    expect(HOMEBREW_CACHE/"testball1--0.1.tbz").to be_a_symlink
    expect(HOMEBREW_CACHE/"testball1--0.1.tbz").to exist
    expect(HOMEBREW_CACHE/"testball2--0.1.tbz").to be_a_symlink
    expect(HOMEBREW_CACHE/"testball2--0.1.tbz").to exist
    expect((HOMEBREW_CACHE/"downloads").glob("*--caffeine.zip")).not_to be_empty
  end

  describe "#cask_downloads", :cask do
    it "collects one download per distinct URL across all platforms" do
      cmd = described_class.new(["--cask", "--all-platforms", "sha256-os"])
      basenames = cmd.send(:cask_downloads, Cask::CaskLoader.load("sha256-os"))
                     .map { |download| File.basename(download.url.to_s) }
      expect(basenames).to contain_exactly("caffeine-arm-darwin.zip", "caffeine-intel-darwin.zip",
                                           "caffeine-arm-linux.zip", "caffeine-intel-linux.zip")
    end

    it "collapses to a single download for a cask without on_system blocks" do
      cmd = described_class.new(["--cask", "--all-platforms", "local-caffeine"])
      expect(cmd.send(:cask_downloads, Cask::CaskLoader.load("local-caffeine")).length).to eq(1)
    end
  end
end
