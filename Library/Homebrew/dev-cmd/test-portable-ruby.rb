# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "digest"
require "fileutils"
require "tmpdir"
require "utils/bottles"
require "utils/portable_ruby"

module Homebrew
  module DevCmd
    class TestPortableRuby < AbstractCommand
      TRACKED_VENDOR_FILES = T.let([
        ".ruby-version",
        "Gemfile.lock",
        "utils/ruby.sh",
        "vendor/portable-ruby-version",
        "vendor/bundle",
        "sorbet/rbi",
      ].freeze, T::Array[String])

      cmd_args do
        description <<~EOS
          Swap in a locally-built `portable-ruby` bottle and run the same checks
          that gate a Homebrew/brew pull request against it. Used to validate a
          new `portable-ruby` version before its bottle is published, so nothing
          first surfaces on the follow-up Homebrew/brew bump PR.

          The argument is the bottle for the current platform (`.bottle.tar.gz`)
          or a test-bot artifact (`.zip`) containing one.
        EOS
        switch "--no-test",
               description: "Do the vendor swap only; skip running the validation suite."
        switch "--no-revert",
               description: "Leave the swapped-in `portable-ruby` and updated vendor files in place after the run."
        switch "--revert",
               description: "Restore the vendored `portable-ruby` files to their git state and exit."

        named_args :artifact, max: 1
      end

      sig { override.void }
      def run
        if args.revert?
          odie "`--revert` does not take an argument." if args.named.any?
          odie "`--revert` cannot be combined with `--no-revert` or `--no-test`." if args.no_revert? || args.no_test?
          revert!
          return
        end

        artifact = args.named.first
        odie "Pass a `portable-ruby` bottle (.tar.gz) or test-bot artifact (.zip)." if artifact.blank?

        artifact_path = Pathname(artifact).expand_path
        odie "#{artifact_path} does not exist." unless artifact_path.exist?

        succeeded = T.let(false, T::Boolean)
        begin
          setup!(artifact_path)
          run_validation_suite! unless args.no_test?
          succeeded = true
        ensure
          if args.no_revert?
            opoo "Leaving the swapped portable-ruby in place (--no-revert)."
          else
            revert!
          end
        end

        ohai "test-portable-ruby completed successfully." if succeeded
      end

      private

      sig { params(artifact_path: Pathname).void }
      def setup!(artifact_path)
        Dir.mktmpdir("test-portable-ruby") do |tmpdir|
          bottle_path = locate_bottle(artifact_path, Pathname(tmpdir))
          pkg_version, tag_symbol, sha256 = parse_bottle(bottle_path)

          ohai "Staging portable-ruby #{pkg_version} (#{tag_symbol})"
          write_vendor_files!(pkg_version:, tag_symbol:, sha256:)
          seed_cache!(bottle_path:, pkg_version:, tag_symbol:)

          ohai "brew vendor-install ruby"
          safe_system HOMEBREW_BREW_FILE, "vendor-install", "ruby"

          Utils::PortableRuby.refresh_vendored_gems_and_rbis!(pkg_version:, dry_run: false)
        end
      end

      sig { params(artifact_path: Pathname, tmpdir: Pathname).returns(Pathname) }
      def locate_bottle(artifact_path, tmpdir)
        return artifact_path if artifact_path.to_s.end_with?(".bottle.tar.gz") ||
                                artifact_path.to_s.match?(/\.bottle\.\d+\.tar\.gz\z/)

        odie "Expected a `.bottle.tar.gz` bottle or a `.zip` artifact." if artifact_path.extname != ".zip"

        ohai "Unzipping #{artifact_path}"
        safe_system "unzip", "-q", "-o", artifact_path.to_s, "-d", tmpdir.to_s

        current_tag = Utils::Bottles.tag
        bottle = Pathname.glob(tmpdir/"**/portable-ruby--*.bottle*.tar.gz").find do |path|
          _, tag_string, = Utils::Bottles.extname_tag_rebuild(path.basename.to_s)
          next false if tag_string.blank?

          bottle_tag = Utils::Bottles::Tag.from_symbol(tag_string.to_sym)
          bottle_tag.standardized_arch == current_tag.standardized_arch &&
            bottle_tag.linux? == current_tag.linux?
        end
        odie "No portable-ruby bottle for #{current_tag.to_sym} found in #{artifact_path}." unless bottle

        bottle
      end

      sig { params(bottle_path: Pathname).returns([String, Symbol, String]) }
      def parse_bottle(bottle_path)
        filename = bottle_path.basename.to_s
        _, tag_string, = Utils::Bottles.extname_tag_rebuild(filename)
        odie "Cannot parse bottle filename #{filename}." if tag_string.blank?

        prefix = "portable-ruby--"
        odie "Bottle #{filename} is not a portable-ruby bottle." unless filename.start_with?(prefix)

        pkg_version = filename.delete_prefix(prefix).sub(/\.#{Regexp.escape(tag_string)}\.bottle.*\.tar\.gz\z/, "")
        odie "Cannot parse portable-ruby version from #{filename}." if pkg_version.empty?

        tag_symbol = tag_string.to_sym
        bottle_tag = Utils::Bottles::Tag.from_symbol(tag_symbol)
        current_tag = Utils::Bottles.tag

        # Portable-ruby bottles are tagged at the minimum supported macOS
        # version (e.g. `arm64_big_sur`) so they work on every newer release.
        compatible = bottle_tag.standardized_arch == current_tag.standardized_arch &&
                     bottle_tag.linux? == current_tag.linux?
        odie "Bottle is for #{tag_symbol} but this machine is #{current_tag.to_sym}." unless compatible

        sha256 = Digest::SHA256.file(bottle_path).hexdigest
        [pkg_version, tag_symbol, sha256]
      end

      sig { params(pkg_version: String, tag_symbol: Symbol, sha256: String).void }
      def write_vendor_files!(pkg_version:, tag_symbol:, sha256:)
        version = pkg_version.split("_").first.to_s
        version = pkg_version if version.empty?

        Utils::PortableRuby.portable_ruby_version_file.atomic_write("#{pkg_version}\n")
        Utils::PortableRuby.ruby_version_file.atomic_write("#{version}\n")

        tag = Utils::Bottles::Tag.from_symbol(tag_symbol)
        os = tag.linux? ? "linux" : "darwin"
        platform_file = Utils::PortableRuby.vendor_dir/"portable-ruby-#{tag.standardized_arch}-#{os}"
        platform_file.atomic_write("ruby_TAG=#{tag_symbol}\nruby_SHA=#{sha256}\n")
      end

      sig { params(bottle_path: Pathname, pkg_version: String, tag_symbol: Symbol).void }
      def seed_cache!(bottle_path:, pkg_version:, tag_symbol:)
        cached_filename = "portable-ruby-#{pkg_version}.#{tag_symbol}.bottle.tar.gz"
        cached_path = HOMEBREW_CACHE/cached_filename
        HOMEBREW_CACHE.mkpath
        FileUtils.cp(bottle_path, cached_path)
      end

      sig { void }
      def run_validation_suite!
        run_check("brew style") { safe_system HOMEBREW_BREW_FILE, "style" }
        run_check("brew typecheck") { safe_system HOMEBREW_BREW_FILE, "typecheck" }

        run_check("brew install-bundler-gems --groups=all") do
          safe_system HOMEBREW_BREW_FILE, "install-bundler-gems", "--groups=all"
        end
        ensure_clean!("vendor/bundle", reason: "brew install-bundler-gems modified vendored gems")

        run_check("brew vendor-gems --non-bundler-gems --no-commit") do
          safe_system HOMEBREW_BREW_FILE, "vendor-gems", "--non-bundler-gems", "--no-commit"
        end
        ensure_clean!("vendor/bundle", reason: "brew vendor-gems modified vendored gems")

        run_check("brew tests --online --coverage") do
          safe_system HOMEBREW_BREW_FILE, "tests", "--online", "--coverage"
        end
        run_check("brew tests --generic --coverage") do
          safe_system HOMEBREW_BREW_FILE, "tests", "--generic", "--coverage"
        end

        run_check("brew update-test") { safe_system HOMEBREW_BREW_FILE, "update-test" }
        run_check("brew update-test --to-tag") { safe_system HOMEBREW_BREW_FILE, "update-test", "--to-tag" }
        run_check("brew update-test --commit=HEAD") do
          safe_system HOMEBREW_BREW_FILE, "update-test", "--commit=HEAD"
        end

        run_check("brew test-bot --only-formulae --only-json-tab --test-default-formula") do
          safe_system HOMEBREW_BREW_FILE, "test-bot", "--only-formulae", "--only-json-tab", "--test-default-formula"
        end
      end

      sig { params(label: String, block: T.proc.void).void }
      def run_check(label, &block)
        ohai label
        yield
        puts
      end

      sig { params(path: String, reason: String).void }
      def ensure_clean!(path, reason:)
        absolute = HOMEBREW_LIBRARY_PATH/path
        return unless absolute.exist?

        diff = Utils.popen_read("git", "-C", HOMEBREW_LIBRARY_PATH.to_s, "status", "--porcelain", "--", path)
        return if diff.strip.empty?

        odie "#{reason}: working tree under #{path} is not clean.\n#{diff}"
      end

      sig { void }
      def revert!
        ohai "Reverting vendored portable-ruby files"

        previous_pkg_version = Utils::PortableRuby.portable_ruby_version_file.read.strip

        platform_filename = current_platform_filename
        files_to_restore = TRACKED_VENDOR_FILES + ["vendor/#{platform_filename}"]
        files_to_restore.each do |relative|
          path = HOMEBREW_LIBRARY_PATH/relative
          next if !path.exist? && !path.symlink?

          safe_system "git", "-C", HOMEBREW_LIBRARY_PATH.to_s, "restore", "--", relative
        end

        restored_pkg_version = Utils::PortableRuby.portable_ruby_version_file.read.strip
        restored_ruby_dir = Utils::PortableRuby.unpacked_ruby_dir(restored_pkg_version)

        if restored_ruby_dir.directory?
          current_symlink = Utils::PortableRuby.vendor_dir/"portable-ruby/current"
          FileUtils.ln_sf(restored_pkg_version, current_symlink)
        end

        return if previous_pkg_version == restored_pkg_version

        stale_dir = Utils::PortableRuby.unpacked_ruby_dir(previous_pkg_version)
        FileUtils.rm_rf(stale_dir) if stale_dir.directory?
      end

      sig { returns(String) }
      def current_platform_filename
        tag = Utils::Bottles.tag
        os = tag.linux? ? "linux" : "darwin"
        "portable-ruby-#{tag.standardized_arch}-#{os}"
      end
    end
  end
end
