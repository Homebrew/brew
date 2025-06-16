# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

# Helper module for installing default files.
module InstallRenamed
  def install_p(_, new_basename)
    super do |src, dst|
      if src.directory?
        dst.install(src.children)
        next
      else
        append_default_if_different(src, dst)
      end
    end
  end

  def cp_path_sub(pattern, replacement)
    super do |src, dst|
      append_default_if_different(src, dst)
    end
  end

  def +(other)
    super.extend(InstallRenamed)
  end

  def /(other)
    super.extend(InstallRenamed)
  end

  private

  def append_default_if_different(src, dst)
    if dst.file? && !FileUtils.identical?(src, dst)
      Pathname.new("#{dst}.default")
    else
      dst
    end
  end
end
