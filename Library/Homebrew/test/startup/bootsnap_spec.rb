# typed: strict
# frozen_string_literal: true

RSpec.describe Homebrew::Bootsnap do
  sig { params(gem_home: Pathname).returns(String) }
  def bootsnap_key(gem_home)
    stdout, stderr, status = Open3.capture3(
      { "HOMEBREW_NO_BOOTSNAP" => "1" },
      *HOMEBREW_RUBY_EXEC_ARGS,
      "-rrubygems", "-e", <<~RUBY, gem_home, HOMEBREW_LIBRARY_PATH/"startup/bootsnap.rb"
        Gem.paths = { "GEM_HOME" => ARGV.fetch(0), "GEM_PATH" => ARGV.fetch(0) }
        require ARGV.fetch(1)
        puts Homebrew::Bootsnap.key
      RUBY
    )
    raise stderr unless status.success?

    stdout.chomp
  end

  describe "::key" do
    it "ignores profiler gems and changes when a core gem changes" do
      gem_home = mktmpdir
      gems = gem_home/"gems"
      (gems/"sorbet-runtime-1.0").mkpath
      original_key = bootsnap_key(gem_home)

      (gems/"stackprof-1.0").mkpath
      profiler_gem_key = bootsnap_key(gem_home)

      (gems/"sorbet-runtime-1.0").rmdir
      (gems/"sorbet-runtime-2.0").mkpath
      core_gem_key = bootsnap_key(gem_home)

      expect([profiler_gem_key == original_key, core_gem_key == original_key]).to eq([true, false])
    end
  end

  describe "::load!" do
    it "does not error when the configured gem path is unavailable" do
      with_env(HOMEBREW_BOOTSNAP_GEM_PATH: "#{TEST_TMPDIR}/missing-bootsnap", HOMEBREW_NO_BOOTSNAP: nil) do
        expect { described_class.load! }.not_to raise_error
      end
    end

    it "invalidates stale gem load paths without removing compiled files" do
      cache = mktmpdir
      load_path_cache = cache/"bootsnap/load-path-cache"
      gem_directories = cache/"bootsnap/gem-directories"
      compile_cache = cache/"bootsnap/compile-cache-iseq/cache"
      load_path_cache.dirname.mkpath
      load_path_cache.write("stale")
      gem_directories.write("old-gem-1.0")
      compile_cache.dirname.mkpath
      compile_cache.write("")
      allow(described_class).to receive_messages(enabled?: true, cache_dir: cache.to_s)
      allow(Dir).to receive(:children).with(File.join(Gem.paths.path, "gems")).and_return(["new-gem-1.0"])
      allow(Bootsnap).to receive(:setup)

      described_class.load!
      stale_cache_removed = !load_path_cache.exist?
      load_path_cache.write("current")
      described_class.load!

      expect([stale_cache_removed, load_path_cache.read, gem_directories.read, compile_cache.exist?])
        .to eq([true, "current", "new-gem-1.0", true])
    end
  end

  describe "::reset!" do
    it "removes the load path cache and keeps the compile cache" do
      cache = mktmpdir
      load_path_cache = cache/"bootsnap/load-path-cache"
      compile_cache = cache/"bootsnap/compile-cache-iseq/cache"
      load_path_cache.dirname.mkpath
      load_path_cache.write("")
      compile_cache.dirname.mkpath
      compile_cache.write("")
      allow(described_class).to receive_messages(enabled?: true, cache_dir: cache.to_s)
      allow(Bootsnap).to receive(:unload_cache!)
      allow(described_class).to receive(:load!)

      described_class.reset!

      expect([load_path_cache.exist?, compile_cache.exist?]).to eq([false, true])
    end
  end

  describe "::prewarm!" do
    it "compiles caches for common command load graphs in a detached background process" do
      with_env(HOMEBREW_BOOTSNAP_GEM_PATH: "gem/path", HOMEBREW_NO_BOOTSNAP: nil, HOMEBREW_TESTS: nil) do
        expect(Process).to receive(:spawn).with(
          *HOMEBREW_RUBY_EXEC_ARGS, "-I", $LOAD_PATH.join(File::PATH_SEPARATOR),
          "-rglobal", "-rcmd/install", "-rcmd/fetch", "-rcmd/upgrade", "-e", "",
          hash_including(pgroup: true)
        ).and_return(12345)
        expect(Process).to receive(:detach).with(12345)

        described_class.prewarm!
      end
    end

    it "does nothing when Bootsnap is disabled" do
      with_env(HOMEBREW_BOOTSNAP_GEM_PATH: "gem/path", HOMEBREW_NO_BOOTSNAP: "1", HOMEBREW_TESTS: nil) do
        expect(Process).not_to receive(:spawn)

        described_class.prewarm!
      end
    end

    it "does not error when starting the prewarm process fails" do
      with_env(HOMEBREW_BOOTSNAP_GEM_PATH: "gem/path", HOMEBREW_NO_BOOTSNAP: nil, HOMEBREW_TESTS: nil) do
        expect(Process).to receive(:spawn).and_raise(Errno::EAGAIN)
        expect(Process).not_to receive(:detach)

        expect { described_class.prewarm! }.not_to raise_error
      end
    end

    it "does not error when detaching the prewarm process fails" do
      with_env(HOMEBREW_BOOTSNAP_GEM_PATH: "gem/path", HOMEBREW_NO_BOOTSNAP: nil, HOMEBREW_TESTS: nil) do
        expect(Process).to receive(:spawn).and_return(12345)
        expect(Process).to receive(:detach).with(12345).and_raise(Errno::ECHILD)

        expect { described_class.prewarm! }.not_to raise_error
      end
    end

    it "does nothing in tests" do
      with_env(HOMEBREW_BOOTSNAP_GEM_PATH: "gem/path", HOMEBREW_NO_BOOTSNAP: nil, HOMEBREW_TESTS: "1") do
        expect(Process).not_to receive(:spawn)

        described_class.prewarm!
      end
    end
  end
end
