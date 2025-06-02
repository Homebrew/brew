# typed: strict
# frozen_string_literal: true

module OS
  module Mac
    module Cleaner
      private

      sig { params(path: Pathname).returns(T::Boolean) }
      def executable_path?(path)
        path.mach_o_executable? || path.text_executable?
      end
    end
  end
end

Cleaner.prepend(OS::Mac::Cleaner)
