# typed: strict
# frozen_string_literal: true

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
        append_default_if_different(src, dst)
      end
    end
  end

  sig {
    params(pattern: T.any(Pathname, String, Regexp), replacement: T.any(Pathname, String),
           _block: T.nilable(T.proc.params(src: Pathname, dst: Pathname).returns(Pathname))).void
  }
  def cp_path_sub(pattern, replacement, &_block)
    super do |src, dst|
      append_default_if_different(src, dst)
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

  private

  sig { params(src: Pathname, dst: Pathname).returns(Pathname) }
  def append_default_if_different(src, dst)
    if dst.file? && !FileUtils.identical?(src, dst)
      Pathname.new("#{dst}.default")
    else
      dst
    end
  end
end
