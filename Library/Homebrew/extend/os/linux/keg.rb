# typed: strict
# frozen_string_literal: true

class Keg
  sig { returns(T::Array[Pathname]) }
  def binary_executable_or_library_files
    elf_files
  end
end
