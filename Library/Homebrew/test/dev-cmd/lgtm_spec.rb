# typed: false
# frozen_string_literal: true

require "open3"

require "cmd/shared_examples/args_parse"
require "dev-cmd/lgtm"
require "utils/tty"

RSpec.describe Homebrew::DevCmd::Lgtm do
  it_behaves_like "parseable arguments"

  describe "cache fallback" do
    let(:repository_root) { Pathname(__dir__).parent.parent.parent.parent }
    let(:test_root) do
      (repository_root/"tmp").mkpath
      Pathname(Dir.mktmpdir("brew-lgtm-cache-fallback-", repository_root/"tmp"))
    end
    let(:isolated_brew) { test_root/"prefix/bin/brew" }
    let(:read_only_cache) { test_root/"readonly-cache" }
    let(:fallback_cache) { test_root/"prefix/tmp/cache" }
    let(:cache_file) { read_only_cache/"api/cask_names.txt" }

    before do
      isolated_brew.dirname.mkpath
      FileUtils.cp repository_root/"bin/brew", isolated_brew
      isolated_brew.chmod(0755)
      FileUtils.ln_s repository_root/"Library", test_root/"prefix/Library"
      cache_file.dirname.mkpath
      cache_file.write("copied-from-cache\n")
      FileUtils.chmod("u-w", read_only_cache)
    end

    after do
      FileUtils.chmod("u+rwx", read_only_cache)
      FileUtils.rm_rf test_root
    end

    it "uses a repository-local cache when HOMEBREW_CACHE is not writable" do
      stdout, stderr, status = Bundler.with_unbundled_env do
        Open3.capture3(
          {
            "HOMEBREW_CACHE"              => read_only_cache.to_s,
            "HOMEBREW_INTEGRATION_TEST"   => "1",
            "HOMEBREW_USE_RUBY_FROM_PATH" => ENV.fetch("HOMEBREW_USE_RUBY_FROM_PATH", nil),
          },
          isolated_brew.to_s,
          "lgtm",
          "--help",
        )
      end

      expect(status.success?).to be true
      expect(Tty.strip_ansi(stdout)).to match(
        /Run brew typecheck, brew style --changed and brew tests --changed in one\s+go\./,
      )
      expect(stderr).to match(
        %r{HOMEBREW_CACHE is not writable at .+; using .+/tmp/cache for Homebrew cache files instead\.},
      )
      expect(fallback_cache/"api/cask_names.txt").to be_a_file
      expect((fallback_cache/"api/cask_names.txt").read).to eq("copied-from-cache\n")
    end
  end
end
