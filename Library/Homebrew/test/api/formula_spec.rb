# typed: true
# frozen_string_literal: true

require "api"
require "test/support/fixtures/testball"

RSpec.describe Homebrew::API::Formula do
  let(:cache_dir) { mktmpdir }
  let(:source_cache_dir) { mktmpdir }

  before do
    stub_const("HOMEBREW_CACHE", cache_dir)
    stub_const("Homebrew::API::HOMEBREW_CACHE_API", cache_dir)
    stub_const("Homebrew::API::HOMEBREW_CACHE_API_SOURCE", source_cache_dir)
    described_class.clear_cache
  end

  def mock_curl_download(stdout:)
    allow(Utils::Curl).to receive(:curl_download) do |*_args, **kwargs|
      kwargs[:to].write stdout
    end
    allow(Homebrew::API).to receive(:verify_and_parse_jws) do |json_data|
      [true, json_data]
    end
  end

  describe "::all_formulae" do
    let(:formulae_json) do
      <<~EOS
        [{
          "name": "foo",
          "url": "https://brew.sh/foo",
          "aliases": ["foo-alias1", "foo-alias2"],
          "executables": ["foo-bin", "food"]
        }, {
          "name": "bar",
          "url": "https://brew.sh/bar",
          "aliases": ["bar-alias"]
        }, {
          "name": "baz",
          "url": "https://brew.sh/baz",
          "aliases": []
        }]
      EOS
    end
    let(:formulae_hash) do
      {
        "foo" => {
          "url"         => "https://brew.sh/foo",
          "aliases"     => ["foo-alias1", "foo-alias2"],
          "executables" => ["foo-bin", "food"],
        },
        "bar" => { "url" => "https://brew.sh/bar", "aliases" => ["bar-alias"] },
        "baz" => { "url" => "https://brew.sh/baz", "aliases" => [] },
      }
    end
    let(:formulae_aliases) do
      {
        "foo-alias1" => "foo",
        "foo-alias2" => "foo",
        "bar-alias"  => "bar",
      }
    end

    it "returns the expected formula JSON list" do
      mock_curl_download stdout: formulae_json
      formulae_output = described_class.all_formulae
      expect(formulae_output).to eq formulae_hash
    end

    it "returns the expected formula alias list" do
      mock_curl_download stdout: formulae_json
      aliases_output = described_class.all_aliases
      expect(aliases_output).to eq formulae_aliases
    end

    it "writes formula executables from the formula JSON list" do
      mock_curl_download stdout: formulae_json
      described_class.write_names_and_aliases

      expect((cache_dir/"internal/executables.txt").read).to eq("foo:foo-bin food\n")
    end

    it "removes the executables database if formula JSON has no executable entries" do
      allow(Utils::Curl).to receive(:curl_download) do |*args, **kwargs|
        raise "unexpected download URL: #{args.last}" unless args.last.end_with?("formula.jws.json")

        kwargs[:to].write <<~JSON
          [{
            "name": "foo",
            "url": "https://brew.sh/foo",
            "aliases": []
          }]
        JSON
      end
      expect(Homebrew::API).not_to receive(:download_executables_file_from_github_packages!)
      allow(Homebrew::API).to receive(:verify_and_parse_jws) do |json_data|
        [true, json_data]
      end
      (cache_dir/"internal").mkpath
      (cache_dir/"internal/executables.txt").write "foo:foo-bin\n"

      described_class.write_names_and_aliases

      expect(cache_dir/"internal/executables.txt").not_to exist
    end

    it "does not download the executables database while reading formula JSON" do
      allow(Utils::Curl).to receive(:curl_download) do |*args, **kwargs|
        raise "unexpected download URL: #{args.last}" unless args.last.end_with?("formula.jws.json")

        kwargs[:to].write <<~JSON
          [{
            "name": "foo",
            "url": "https://brew.sh/foo",
            "aliases": []
          }]
        JSON
      end
      allow(Homebrew::API).to receive(:verify_and_parse_jws) do |json_data|
        [true, json_data]
      end

      expect(described_class.all_formulae).to eq("foo" => { "url" => "https://brew.sh/foo", "aliases" => [] })
      expect(cache_dir/"internal/executables.txt").not_to exist
    end
  end

  describe "::source_download" do
    let(:f) { Testball.new }

    before do
      allow(Homebrew::API).to receive(:formula_names).and_return([])
      allow(f).to receive_messages(ruby_source_path: "Formula/testball.rb", tap_git_head: "abc123",
                                   ruby_source_checksum: nil)
      allow(f).to receive(:tap).and_return(CoreTap.instance)
    end

    it "forces re-download when symlink_location exists but is not a symlink" do
      regular_file = mktmpdir/"testball.rb"
      regular_file.write("not a symlink")

      allow_any_instance_of(Homebrew::API::SourceDownload).to receive(:symlink_location).and_return(regular_file)
      expect_any_instance_of(Homebrew::API::SourceDownload).to receive(:fetch)

      described_class.source_download(f)
    end

    it "skips download when symlink_location is a valid symlink" do
      target = mktmpdir/"testball_target.rb"
      target.write("content")
      symlink = mktmpdir/"testball.rb"
      FileUtils.ln_s(target, symlink)

      allow_any_instance_of(Homebrew::API::SourceDownload).to receive(:symlink_location).and_return(symlink)
      expect_any_instance_of(Homebrew::API::SourceDownload).not_to receive(:fetch)

      described_class.source_download(f)
    end

    it "verifies a cached source file before trusting its symlink" do
      target = mktmpdir/"testball_target.rb"
      target.write("mismatched")
      symlink = mktmpdir/"testball.rb"
      FileUtils.ln_s(target, symlink)
      allow(f).to receive(:ruby_source_checksum)
        .and_return(Checksum.new(Digest::SHA256.hexdigest("valid")))
      allow_any_instance_of(Homebrew::API::SourceDownload).to receive(:symlink_location).and_return(symlink)

      expect { described_class.source_download(f) }.to raise_error(ChecksumMismatchError)
      expect(symlink).not_to exist
    end

    it "removes a freshly downloaded source file that fails verification" do
      missing = mktmpdir/"testball.rb"
      checksum = Checksum.new(Digest::SHA256.hexdigest("valid"))
      allow(f).to receive(:ruby_source_checksum).and_return(checksum)
      allow_any_instance_of(Homebrew::API::SourceDownload).to receive(:symlink_location).and_return(missing)
      allow_any_instance_of(Homebrew::API::SourceDownload).to receive(:fetch)
        .and_raise(ChecksumMismatchError.new(missing, checksum, Checksum.new(Digest::SHA256.hexdigest("bad"))))
      expect_any_instance_of(Homebrew::API::SourceDownload).to receive(:clear_cache)

      expect { described_class.source_download(f) }.to raise_error(ChecksumMismatchError)
    end

    it "reuses a cached source file that matches its checksum" do
      content = "valid"
      target = mktmpdir/"testball_target.rb"
      target.write(content)
      symlink = mktmpdir/"testball.rb"
      FileUtils.ln_s(target, symlink)
      allow(f).to receive(:ruby_source_checksum).and_return(Checksum.new(Digest::SHA256.hexdigest(content)))
      allow_any_instance_of(Homebrew::API::SourceDownload).to receive(:symlink_location).and_return(symlink)
      expect_any_instance_of(Homebrew::API::SourceDownload).not_to receive(:fetch)

      expect(described_class.source_download(f).symlink_location).to eq(symlink)
    end
  end

  describe "::source_download_formula" do
    let(:f) { Testball.new }

    before do
      allow(Homebrew::API).to receive(:formula_names).and_return([])
      allow(f).to receive_messages(ruby_source_path: "Formula/testball.rb", tap_git_head: "abc123",
                                   ruby_source_checksum: nil)
      allow(f).to receive(:tap).and_return(CoreTap.instance)
    end

    it "raises CannotInstallFormulaError when source file is missing" do
      allow_any_instance_of(Homebrew::API::SourceDownload).to receive(:fetch)
      allow_any_instance_of(Homebrew::API::SourceDownload).to receive(:symlink_location).and_return(
        Pathname("/nonexistent/path/testball.rb"),
      )

      expect do
        described_class.source_download_formula(f)
      end.to raise_error(CannotInstallFormulaError, /source code not found/)
    end

    it "loads formula from symlink_location when source file exists" do
      source_path = (mktmpdir/"testball.rb")
      source_path.write <<~RUBY
        class Testball < Formula
          url "https://brew.sh/testball-0.1.tar.gz"
        end
      RUBY

      allow_any_instance_of(Homebrew::API::SourceDownload).to receive(:fetch)
      allow_any_instance_of(Homebrew::API::SourceDownload).to receive(:symlink_location).and_return(source_path)

      result = described_class.source_download_formula(f)
      expect(result).to be_a(Formula)
      expect(result.name).to eq("testball")
    end

    it "loads local patch files from API source cache" do
      source_path = source_cache_dir/"Homebrew/homebrew-core/abc123/Formula/testball.rb"
      source_path.dirname.mkpath
      cached_source_path = cache_dir/"downloads/testball.rb"
      cached_source_path.dirname.mkpath
      cached_source_path.write <<~RUBY
        class Testball < Formula
          url "https://brew.sh/testball-0.1.tar.gz"

          patch do
            file "patches/noop-a.diff"
          end
        end
      RUBY
      FileUtils.ln_s cached_source_path.relative_path_from(source_path.dirname), source_path

      allow_any_instance_of(Homebrew::API::SourceDownload).to receive(:fetch) do |download|
        next if download.symlink_location.basename.to_s != "noop-a.diff"

        cached_patch_path = download.downloader.cached_location
        cached_patch_path.dirname.mkpath
        cached_patch_path.write("patch contents")
        download.downloader.create_symlink_to_cached_download(cached_patch_path)
      end

      result = described_class.source_download_formula(f)

      expect(result.patchlist.fetch(0).contents).to eq("patch contents")
    end
  end
end
