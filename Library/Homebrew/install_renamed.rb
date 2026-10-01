# typed: strict
# frozen_string_literal: true

require "utils/path"

# Helper module for installing default files.
module InstallRenamed
  sig {
    params(src: T.any(String, Pathname), new_basename: String,
           _block: T.nilable(T.proc.params(src: Pathname, dst: Pathname).returns(T.nilable(Pathname)))).void
  }
  def install_p(src, new_basename, &_block)
    super do |src, dst|
      if src.directory?
        dst.install(src.children)
        next
      else
        InstallRenamed.destination_for(src, dst)
      end
    end
  end

  sig {
    params(path: Pathname, pattern: T.any(Pathname, String, Regexp), replacement: T.any(Pathname, String)).void
  }
  def self.cp_path_sub(path, pattern, replacement)
    Utils::Path.cp_path_sub(path, pattern, replacement) do |src, dst|
      destination_for(src, dst)
    end
  end

  sig {
    params(pattern: T.any(Pathname, String, Regexp), replacement: T.any(Pathname, String),
           _block: T.nilable(T.proc.params(src: Pathname, dst: Pathname).returns(Pathname))).void
  }
  def cp_path_sub(pattern, replacement, &_block)
    super do |src, dst|
      InstallRenamed.destination_for(src, dst)
    end
  end

  sig { params(other: T.any(String, Pathname)).returns(Pathname) }
  def +(other)
    super.extend(InstallRenamed)
  end

  sig { params(other: T.any(String, Pathname)).returns(Pathname) }
  def /(other)
    super.extend(InstallRenamed)
  end

  sig { params(src: Pathname, dst: Pathname).returns(Pathname) }
  def self.destination_for(src, dst)
    return dst if !dst.file? || FileUtils.identical?(src, dst)

    # Bottle installs restore config from `<keg>/.bottle/etc` through this
    # helper. If the live config still matches an older bottled default, replace
    # it so untouched configs advance on upgrade. Modified configs still receive
    # the new default as `*.default`.
    # Resolve via realpath so the ascend walks the Cellar path, not `opt_prefix`.
    # For symlink sources, resolve only the parent directory so broken symlinks
    # are still handled without requiring the target to exist.
    src = if src.symlink?
      src.dirname.realpath/src.basename
    else
      src.realpath
    end
    src.ascend do |path|
      next if path.basename.to_s != ".bottle" || path.parent.parent.parent != HOMEBREW_CELLAR

      path.parent.parent.subdirs.each do |prefix|
        next if prefix == path.parent

        default_file = prefix/".bottle"/src.relative_path_from(path)
        return dst if default_file.file? && FileUtils.identical?(dst, default_file)
      end

      break
    end

    Pathname.new("#{dst}.default")
  end
end
