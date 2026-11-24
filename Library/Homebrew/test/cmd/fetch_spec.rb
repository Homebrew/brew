# typed: true
# frozen_string_literal: true

require "cmd/fetch"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::FetchCmd do
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

  it_behaves_like "parseable arguments"

  test_each(%w[arm64 x86_64 :arm]) do |arch|
    it "lists the valid --arch values when given #{arch}" do
      expect { described_class.new(["--arch", arch, "foo"]).run }
        .to raise_error(UsageError, /`--arch` does not accept "#{arch}"\.\nUse arm, intel or all\./)
    end
  end

  it "lists the valid --os values when given an unknown OS" do
    expect { described_class.new(["--os", "darwin", "foo"]).run }
      .to raise_error(UsageError, /`--os`.*"darwin".*macos, linux, all.*tahoe/m)
  end

  it "explains why the API might not list a bottle for the requested platform" do
    cmd = described_class.new(%w[--arch arm --os tahoe foo])
    allow(cmd.args.named).to receive(:to_formulae_and_casks).and_return([foo])
    allow(foo).to receive_messages(loaded_from_api?: true, loaded_from_internal_api?: true)
    allow(Formulary).to receive(:factory).and_return(foo)

    expect { cmd.run }.to output(/foo.*arm64_tahoe.*API.*host platform/m).to_stderr
  end

  describe "--test" do
    let(:cmd) { described_class.new(["--test", "foo"]) }
    let(:download_queue) { instance_double(Homebrew::DownloadQueue, fetch: nil, shutdown: nil) }
    let(:downloads) { [] }

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
      source_foo = formula("foo") do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/foo-1.0.tar.gz"
      end
      allow(source_foo).to receive(:loaded_from_api?).and_return(false)
      expect(Homebrew::API::Formula).to receive(:source_download_formula).with(foo).and_return(source_foo)

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

  it "silently skips a formula's fetch hook until its dependencies are installed" do
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

    expect { cmd.run_fetch_hook(foo) }.not_to output.to_stderr
  end

  it "loads the formula source to enqueue its resources when using the API" do
    ENV.delete("HOMEBREW_TEST_GENERIC_OS")
    cmd = described_class.new(["--build-from-source", "foo"])
    api_foo = formula("foo") do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/foo-1.0.tar.gz"
    end
    allow(api_foo).to receive(:loaded_from_api?).and_return(true)
    download_queue = instance_double(Homebrew::DownloadQueue, enqueue: nil, fetch: nil, shutdown: nil)
    allow(Homebrew::DownloadQueue).to receive(:new).and_return(download_queue)
    allow(cmd.args.named).to receive_messages(to_formulae_and_casks: [api_foo])
    allow(Formulary).to receive_messages(factory: api_foo, from_path: api_foo)
    allow(cmd).to receive(:run_fetch_hook)
    allow(Homebrew::API::Formula).to receive(:source_download_formula).with(api_foo).and_return(foo)
    expect(download_queue).to receive(:enqueue).with(foo.resource("build"))

    cmd.run
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

    expect do
      brew "fetch", "--verbose", "testball1", "testball2", "local-caffeine"
    end.to output(include(Formula["testball1"].cached_download.to_s,
                          Formula["testball2"].cached_download.to_s,
                          Cask::Download.new(Cask::CaskLoader.load("local-caffeine")).cached_download.to_s)).to_stdout
      .and be_a_success

    expect(HOMEBREW_CACHE/"testball1--0.1.tbz").to be_a_symlink
    expect(HOMEBREW_CACHE/"testball1--0.1.tbz").to exist
    expect(HOMEBREW_CACHE/"testball2--0.1.tbz").to be_a_symlink
    expect(HOMEBREW_CACHE/"testball2--0.1.tbz").to exist
    expect((HOMEBREW_CACHE/"downloads").glob("*--caffeine.zip")).not_to be_empty
  end

  describe "#cask_downloads", :cask do
    it "reuses the loaded cask source across platforms and languages" do
      cask = Cask::CaskLoader.load("with-many-languages")
      expect(Cask::CaskLoader).not_to receive(:from_path)

      described_class.new(["--cask", "--all-platforms", cask.token]).cask_downloads(cask)
    end

    it "keeps each queued download's platform and language values independent" do
      cask = Cask::CaskLoader.from_content(<<~RUBY)
        cask "localised-platforms" do
          version "1.0"
          arch arm: "arm", intel: "intel"
          os macos: "macos", linux: "linux"
          language "en", default: true do
            sha256 "#{"0" * 64}"
            "en"
          end
          language "fr" do
            sha256 "#{"1" * 64}"
            "fr"
          end
          url "https://example.com/\#{os}-\#{arch}-\#{language}.zip"
        end
      RUBY
      downloads = described_class.new(["--cask", "--all-platforms", cask.token]).cask_downloads(cask)

      expect(downloads.map { |download| [File.basename(download.url.to_s), download.checksum.to_s] })
        .to match_array(%w[macos linux].product(%w[intel arm], %w[en fr]).map do |os, arch, language|
          english = language == "en"
          ["#{os}-#{arch}-#{language}.zip", (english ? "0" : "1") * 64]
        end)
    end

    it "fetches platform-specific artifacts with `--all-platforms` flag" do
      cask = Cask::CaskLoader.from_content(<<~RUBY)
        cask "test-cask" do
          version "1.2.3"
          sha256 "9a1c0967baa46828930ccbbc88668d1b0db07e6edf778800ed4da073c00054f8"

          url "https://example.com/linux-arm64.zip"
          homepage "https://brew.sh/"

          depends_on arch: :arm64
          depends_on :linux
        end
      RUBY

      cmd = described_class.new(["--cask", "--all-platforms", cask.token])
      downloads = cmd.cask_downloads(cask)
                     .map { |download| File.basename(download.url.to_s) }
      expect(downloads).to contain_exactly("linux-arm64.zip")
    end

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
