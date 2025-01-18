# typed: strict
# frozen_string_literal: true

module Utils
  sig {
    params(binary: T.any(String, Pathname), library: T.any(String, Pathname),
           prefix: T.any(String, Pathname)).returns(T::Boolean)
  }
  def self.binary_linked_to_library?(binary, library, prefix = HOMEBREW_PREFIX)
    Pathname.new(binary).dynamically_linked_libraries.any? do |dll|
      next false unless dll.start_with?(prefix.to_s)

      File.realpath(dll) == File.realpath(Pathname.new(library))
    end
  end
end
