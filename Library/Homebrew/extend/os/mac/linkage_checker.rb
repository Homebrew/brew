# typed: true
# frozen_string_literal: true

class LinkageChecker
  undef system_libraries_exist_in_cache?

  private

  def system_libraries_exist_in_cache?
    # In macOS Big Sur and later, system libraries do not exist on-disk and instead exist in a cache.
    MacOS.version >= :big_sur
  end
end
