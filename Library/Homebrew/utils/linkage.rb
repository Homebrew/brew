# typed: strict
# frozen_string_literal: true

module Utils
  sig {
    params(binary: T.any(String, Pathname), library: T.any(String, Pathname)).returns(T::Boolean)
  }
  def self.binary_linked_to_library?(binary, library)
    library = library.to_s
    library = File.realpath(library) if library.start_with?(HOMEBREW_PREFIX.to_s)

    binary_path = BinaryPathname.wrap(binary)
    binary_path.dynamically_linked_libraries.any? do |dll|
      dll = File.realpath(dll) if dll.start_with?(HOMEBREW_PREFIX.to_s)
      dll == library
    end
  end
end
