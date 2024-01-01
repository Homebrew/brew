# typed: true
# frozen_string_literal: true

require "system_command"

module UnpackStrategy
  # Strategy for unpacking tar archives.
  class Tar
    include UnpackStrategy
    extend SystemCommand::Mixin

    sig { returns(T::Array[String]) }
    def self.extensions
      [
        ".tar",
        ".tbz", ".tbz2", ".tar.bz2",
        ".tgz", ".tar.gz",
        ".tlzma", ".tar.lzma",
        ".txz", ".tar.xz",
        ".tar.zst"
      ]
    end

    def self.can_extract?(path)
      return true if path.magic_number.match?(/\A.{257}ustar/n)

      return false unless [Bzip2, Gzip, Lzip, Xz, Zstd].any? { |s| s.can_extract?(path) }

      # Check if `tar` can list the contents, then it can also extract it.
      stdout, _, status = system_command("tar", args: ["--list", "--file", path], print_stderr: false)
      status.success? && !stdout.empty?
    end

    private

    sig { override.params(unpack_dir: Pathname, basename: Pathname, verbose: T::Boolean).returns(T.untyped) }
    def extract_to_dir(unpack_dir, basename:, verbose:)
      Dir.mktmpdir do |tmpdir|
        tar_path = if DependencyCollector.tar_needs_xz_dependency? && Xz.can_extract?(path)
          subextract(Xz, Pathname(tmpdir), verbose)
        elsif Zstd.can_extract?(path)
          subextract(Zstd, Pathname(tmpdir), verbose)
        else
          path
        end

        system_command! "tar",
                        args:    ["--extract", "--no-same-owner",
                                  "--file", tar_path,
                                  "--directory", unpack_dir],
                        verbose: verbose
      end
    end

    sig {
      params(extractor: T.any(T.class_of(Xz), T.class_of(Zstd)), dir: Pathname, verbose: T::Boolean).returns(Pathname)
    }
    def subextract(extractor, dir, verbose)
      extractor.new(path).extract(to: dir, verbose: verbose)
      T.must(dir.children.first)
    end
  end
end
