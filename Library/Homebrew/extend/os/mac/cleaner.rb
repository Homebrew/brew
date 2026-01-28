# typed: strict
# frozen_string_literal: true

module OS
  module Mac
    module Cleaner
      private

      sig { params(path: ::Pathname).returns(T::Boolean) }
      def executable_path?(path)
        return true if path.text_executable?

        path = MachOPathname.wrap(path)
        path.mach_o_executable?
      end
    end
  end
end

Cleaner.prepend(OS::Mac::Cleaner)
