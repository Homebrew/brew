# typed: true
# frozen_string_literal: true

require "cmd/fetch"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::FetchCmd do
  it_behaves_like "parseable arguments"

  describe "--test" do
    let(:cmd) { described_class.new(["--test", "foo"]) }
    let(:download_queue) { instance_double(Homebrew::DownloadQueue, fetch: nil, shutdown: nil) }
    let(:downloads) { [] }
    let(:foo) do
      formula("foo") do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/foo-1.0.tar.gz"

        resource "build" do
          url "https://brew.sh/build-1.0.tar.gz"
        end

        resource "fixture", :test do
          url "https://brew.sh/fixture-1.0.tar.gz"
        end
      end
    end

    before do
      allow(Homebrew::DownloadQueue).to receive(:new).and_return(download_queue)
      allow(download_queue).to receive(:enqueue) { |download| downloads << download }
      allow(cmd.args.named).to receive_messages(to_formulae: [foo], to_formulae_and_casks: [foo])
      allow(Formulary).to receive_messages(factory: foo, from_path: foo)
      allow(cmd).to receive(:fetch_bottle?).and_return(false)
      allow(cmd).to receive(:run_fetch_hook)
    end

    it "fetches test resources alongside an available bottle" do
      bottle = instance_double(Bottle, github_packages_manifest_resource: nil)
      allow(foo).to receive(:bottle_for_tag).and_return(bottle)
      allow(cmd).to receive(:fetch_bottle?).and_return(true)

      cmd.run

      expect(downloads).to eq([foo.resource("fixture"), bottle])
    end

    it "loads the formula source to find test resources when using the API" do
      ENV.delete("HOMEBREW_TEST_GENERIC_OS")
      allow(foo).to receive(:loaded_from_api?).and_return(true)
      expect(Homebrew::API::Formula).to receive(:source_download_formula).with(foo).and_return(foo)

      cmd.run
    end

    it "runs the build fetch hook when fetching sources" do
      expect(cmd).to receive(:run_fetch_hook).with(foo)

      cmd.run
    end

    it "resolves named arguments as formulae" do
      expect(cmd.args.named).to receive(:to_formulae).and_return([foo])

      cmd.run
    end

    test_each(%w[--build-from-source --build-bottle --force-bottle --bottle-tag=arm64_tahoe --deps]) do |flag|
      it "combines test resource downloads with #{flag}" do
        cmd = described_class.new(["--test", flag, "foo"])
        allow(cmd.args.named).to receive_messages(to_formulae: [foo], to_formulae_and_casks: [foo])
        allow(cmd).to receive(:fetch_bottle?).and_return(false)
        allow(cmd).to receive(:run_fetch_hook)
        allow(foo).to receive(:recursive_dependencies).and_return([])

        cmd.run

        expect(downloads).to eq([foo.resource("fixture"), foo.resource, foo.resource("build")])
      end
    end
  end

  it "does not run a formula's fetch hook until its dependencies are installed" do
    cmd = described_class.new(["--build-from-source", "foo"])
    dependency = formula("bar") do
      T.bind(self, T.class_of(Formula))
      url "bar-1.0"
    end
    foo = formula("foo") do
      T.bind(self, T.class_of(Formula))
      url "foo-1.0"

      sig { void }
      def fetch; end
    end
    allow(foo).to receive(:recursive_dependencies).and_return([instance_double(Dependency, to_formula: dependency)])
    expect(FormulaInstaller).not_to receive(:new)

    expect { cmd.run_fetch_hook(foo) }.to output(/brew install --only-dependencies foo/).to_stderr
  end

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
      formula_renames: {},
      formula_struct:  formula_struct,
    )
    allow(Homebrew::API::Internal).to receive(:formula_name?) { |name| name == "fast-fetch" }

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
      cask_renames: {},
      cask_struct:  cask_struct,
    )
    allow(Homebrew::API::Internal).to receive(:cask_name?) { |token| token == "fast-cask" }

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
      basenames = cmd.cask_downloads(Cask::CaskLoader.load("sha256-os"))
                     .map { |download| File.basename(download.url.to_s) }
      expect(basenames).to contain_exactly("caffeine-arm-darwin.zip", "caffeine-intel-darwin.zip",
                                           "caffeine-arm-linux.zip", "caffeine-intel-linux.zip")
    end

    it "skips arches the cask's depends_on arch excludes" do
      cmd = described_class.new(["--cask", "--os=macos", "--arch=intel", "depends-on-arch-arm64"])
      expect(cmd.cask_downloads(Cask::CaskLoader.load("depends-on-arch-arm64"))).to be_empty
    end

    it "collapses to a single download for a cask without on_system blocks" do
      cmd = described_class.new(["--cask", "--all-platforms", "local-caffeine"])
      expect(cmd.cask_downloads(Cask::CaskLoader.load("local-caffeine")).length).to eq(1)
    end
  end
end
