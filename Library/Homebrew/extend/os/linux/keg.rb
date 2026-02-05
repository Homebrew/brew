# typed: strict
# frozen_string_literal: true

module OS
  module Linux
    module Keg
      sig { returns(T::Array[ELFShim]) }
      def binary_executable_or_library_files = elf_files
    end
  end
end

Keg.prepend(OS::Linux::Keg)
