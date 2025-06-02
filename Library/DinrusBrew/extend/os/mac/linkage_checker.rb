# typed: strict
# frozen_string_literal: true

module OS
  module Mac
    module LinkageChecker
      private

      sig { returns(T::Boolean) }
      def system_libraries_exist_in_cache?
        # In macOS Big Sur and later, system libraries do not exist on-disk and instead exist in a cache.
        MacOS.version >= :big_sur
      end
    end
  end
end

LinkageChecker.prepend(OS::Mac::LinkageChecker)
