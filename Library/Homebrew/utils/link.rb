# typed: true
# frozen_string_literal: true

module Utils
  # Helper functions for creating symlinks.
  #
  # @api private
  module Link
    def self.link_src_dst_dirs(src_dir, dst_dir, command, link_dir: false)
      return unless src_dir.exist?

      conflicts = []
      src_paths = link_dir ? [src_dir] : src_dir.find
      src_paths.each do |src|
        next if src.directory? && !link_dir

        dst = dst_dir/src.relative_path_from(src_dir)
        if dst.symlink?
          next if src == dst.resolved_path

          dst.unlink
        end
        if dst.exist?
          conflicts << dst
          next
        end
        dst_dir.parent.mkpath
        dst.make_relative_symlink(src)
      end

      return if conflicts.empty?

      onoe <<~EOS
        Could not link:
        #{conflicts.join("\n")}

        Please delete these paths and run:
          #{command}
      EOS
    end
    private_class_method :link_src_dst_dirs

    def self.unlink_src_dst_dirs(src_dir, dst_dir, unlink_dir: false)
      return unless src_dir.exist?

      src_paths = unlink_dir ? [src_dir] : src_dir.find
      src_paths.each do |src|
        next if src.directory? && !unlink_dir

        dst = dst_dir/src.relative_path_from(src_dir)
        dst.delete if dst.symlink? && src == dst.resolved_path
        dst.parent.rmdir_if_possible
      end
    end
    private_class_method :unlink_src_dst_dirs

    def self.link_manpages(path, command)
      link_src_dst_dirs(path/"manpages", HOMEBREW_PREFIX/"share/man/man1", command)
    end

    def self.unlink_manpages(path)
      unlink_src_dst_dirs(path/"manpages", HOMEBREW_PREFIX/"share/man/man1")
    end

    def self.link_completions(path, command)
      link_src_dst_dirs(path/"completions/bash", HOMEBREW_PREFIX/"etc/bash_completion.d", command)
      link_src_dst_dirs(path/"completions/zsh", HOMEBREW_PREFIX/"share/zsh/site-functions", command)
      link_src_dst_dirs(path/"completions/fish", HOMEBREW_PREFIX/"share/fish/vendor_completions.d", command)
    end

    def self.unlink_completions(path)
      unlink_src_dst_dirs(path/"completions/bash", HOMEBREW_PREFIX/"etc/bash_completion.d")
      unlink_src_dst_dirs(path/"completions/zsh", HOMEBREW_PREFIX/"share/zsh/site-functions")
      unlink_src_dst_dirs(path/"completions/fish", HOMEBREW_PREFIX/"share/fish/vendor_completions.d")
    end

    def self.link_docs(path, command)
      link_src_dst_dirs(path/"docs", HOMEBREW_PREFIX/"share/doc/homebrew", command, link_dir: true)
    end
  end
end
