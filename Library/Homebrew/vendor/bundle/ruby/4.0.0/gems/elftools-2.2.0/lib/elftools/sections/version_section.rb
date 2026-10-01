# frozen_string_literal: true

require 'elftools/sections/section'

module ELFTools
  module Sections
    # Class of the section recording which version each symbol binds to.
    #
    # This section is usually named .gnu.version, and holds an index per symbol
    # of the table its +sh_link+ names, the very indices the +DT_VERSYM+ tag
    # points at.
    class VersionSection < Section
      # How many symbols the section records a version for.
      # @return [Integer] The number.
      def num_versions
        header.sh_size.to_i / entry_size
      end

      # What the +n+-th symbol records as its version, which is an index into
      # the versions a file needs or defines, with the highest bit marking a
      # version the symbol asks for by name rather than the default one.
      # @param [Integer] n The symbol index.
      # @return [Integer, nil] The index, +nil+ if the section records none for it.
      # @example
      #   section.version_at(1)
      #   #=> 2
      def version_at(n)
        return if n.negative? || n >= num_versions

        stream.pos = header.sh_offset.to_i + (n * entry_size)
        stream.read(entry_size).unpack1(header.class.self_endian == :big ? 'S>' : 'S<')
      end

      private

      # What an entry takes, which the section records and the format fixes at
      # two bytes either way.
      # @return [Integer] The number of bytes.
      def entry_size
        2
      end
    end
  end
end
