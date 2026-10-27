# typed: strict
# frozen_string_literal: true

require "system_command"

module UnpackStrategy
  # Strategy for unpacking tar archives.
  class Tar
    include UnpackStrategy
    extend SystemCommand::Mixin

    sig { override.returns(T::Array[String]) }
    def self.extensions
      [
        ".tar",
        ".tbz", ".tbz2", ".tar.bz2",
        ".tgz", ".tar.gz",
        ".tlzma", ".tar.lzma",
        ".txz", ".tar.xz",
        ".tar.zst",
        ".crate"
      ]
    end

    sig { override.params(path: Path).returns(T::Boolean) }
    def self.can_extract?(path)
      return true if path.magic_number.match?(/\A.{257}ustar/n)

      return false unless [Bzip2, Gzip, Lzip, Xz, Zstd].any? { |s| s.can_extract?(path) }

      # Check if `tar` can list the contents, then it can also extract it.
      stdout, _, status = system_command("tar", args: ["--list", "--file", path], print_stderr: false).to_a
      (status.success? && !stdout.empty?) || false
    end

    private

    sig { override.params(unpack_dir: Pathname, basename: Pathname, verbose: T::Boolean).void }
    def extract_to_dir(unpack_dir, basename:, verbose:)
      Dir.mktmpdir("homebrew-tar", temporary_directory.to_s) do |tmpdir|
        tar_path = if DependencyCollector.tar_needs_xz_dependency? && Xz.can_extract?(path)
          subextract(Xz, Pathname(tmpdir), verbose)
        elsif DependencyCollector.tar_needs_bzip2_dependency? && Bzip2.can_extract?(path)
          subextract(Bzip2, Pathname(tmpdir), verbose)
        elsif Zstd.can_extract?(path)
          subextract(Zstd, Pathname(tmpdir), verbose)
        else
          path
        end

        system_command! "tar",
                        args:    ["--extract", "--no-same-owner",
                                  "--file", tar_path,
                                  "--directory", unpack_dir],
                        # Keep tar diagnostics in English so that `unpack_strategy.rb` can
                        # recognize out-of-space errors, while using a UTF-8 character set so
                        # that archives containing non-ASCII paths can be extracted.
                        env:     { "LC_ALL" => "en_US.UTF-8" },
                        verbose: verbose

        normalize_proot_hardlinks!(unpack_dir)
      end
    end

    # PROOT's --link2symlink extension represents hard links as absolute symlinks
    # into the extraction directory. These break as soon as the tree is moved, so
    # materialise each hard-link group as a regular file plus relative symlinks.
    sig { params(root: Pathname).void }
    def normalize_proot_hardlinks!(root)
      status = begin
        File.read("/proc/self/status")
      rescue SystemCallError
        nil
      end
      return if status.nil?

      tracer_pid = status[/^TracerPid:\s*(\d+)/, 1]
      return if tracer_pid.nil? || tracer_pid.to_i.zero?
      return if root.glob("**/.l2s.*", File::FNM_DOTMATCH).empty?

      groups = T.let({}, T::Hash[String, T::Array[Pathname]])
      l2s_links = T.let({}, T::Hash[String, T::Array[Pathname]])

      root.find do |path|
        next if path.directory?

        target = begin
          path.readlink
        rescue SystemCallError
          nil
        end
        if target
          stat = begin
            File.stat(target)
          rescue SystemCallError
            next
          end
          key = "#{stat.dev}:#{stat.ino}"
          (l2s_links[key] ||= []) << path
          next
        end

        stat = begin
          File.stat(path)
        rescue SystemCallError
          next
        end
        next if stat.nlink <= 1

        key = "#{stat.dev}:#{stat.ino}"
        (groups[key] ||= []) << path
      end

      groups.each do |key, paths|
        next if paths.size < 2

        data = paths.find { |path| path.basename.to_s.start_with?(".l2s.") }
        next if data.nil?

        hardlinks = paths - [data]
        temp_stem = data.basename.to_s.delete_prefix(".l2s.").sub(/\.\d+\z/, "")
        candidates = hardlinks.select { |path| temp_stem.start_with?(path.basename.to_s) }
        canonical = candidates.max_by { |path| path.basename.to_s.length } || hardlinks.first
        next if canonical.nil?

        tmp = canonical.dirname/".homebrew-proot-#{Process.pid}-#{canonical.basename}"
        IO.copy_stream(data.to_s, tmp.to_s)
        File.chmod(data.stat.mode & 07777, tmp.to_s)

        (hardlinks + (l2s_links[key] || []) + [data]).each do |path|
          path.unlink
        rescue Errno::ENOENT
          nil
        end

        tmp.rename(canonical.to_s)

        (hardlinks - [canonical]).each do |path|
          path.make_symlink(canonical.relative_path_from(path.parent))
        end
      end
    end

    sig {
      params(extractor: T.any(T.class_of(Bzip2), T.class_of(Xz), T.class_of(Zstd)), dir: Pathname,
             verbose: T::Boolean).returns(Pathname)
    }
    def subextract(extractor, dir, verbose)
      extractor.new(path).extract(to: dir, verbose:)
      dir.children.fetch(0)
    end
  end
end
