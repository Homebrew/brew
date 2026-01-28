# typed: strict
# frozen_string_literal: true

module OS
  module Linux
    module Cleaner
      private

      sig { params(path: ::Pathname).returns(T::Boolean) }
      def executable_path?(path)
        return true if path.text_executable?

        ELFPathname.wrap(path).elf?
      end
    end
  end
end

Cleaner.prepend(OS::Linux::Cleaner)
