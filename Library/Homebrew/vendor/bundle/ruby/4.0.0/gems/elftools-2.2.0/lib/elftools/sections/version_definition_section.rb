# frozen_string_literal: true

require 'elftools/sections/section'
require 'elftools/version_tables'

module ELFTools
  module Sections
    # Class of the section recording the versions a file defines for what it
    # exports.
    #
    # This section is usually named .gnu.version_d, and records the very
    # versions the +DT_VERDEF+ tag points at.
    class VersionDefinitionSection < Section
      # Instantiate a {VersionDefinitionSection} object.
      # @param [ELFTools::Structs::ELF_Shdr] header
      #   See {Section#initialize} for more information.
      # @param [#pos=, #read] stream
      #   See {Section#initialize} for more information.
      # @param [Proc] section_at
      #   The method for fetching other sections by index, which is where the
      #   names are recorded.
      def initialize(header, stream, section_at: nil, **_kwargs)
        @section_at = section_at
        super
      end

      # The versions this file defines for what it exports.
      # @return [Array<ELFTools::VersionTables::Definition>]
      #   The definitions, in the order the section records them.
      # @example
      #   section.definitions.map(&:name).first(3)
      #   #=> ['libc.so.6', 'GLIBC_2.2.5', 'GLIBC_2.2.6']
      def definitions
        @definitions ||= VersionTables.new(stream, @section_at.call(header.sh_link),
                                           endian: header.class.self_endian)
                                      .definitions(header.sh_offset.to_i, header.sh_info.to_i)
      end
    end
  end
end
