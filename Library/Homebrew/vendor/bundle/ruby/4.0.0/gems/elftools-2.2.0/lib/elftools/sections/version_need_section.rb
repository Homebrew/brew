# frozen_string_literal: true

require 'elftools/sections/section'
require 'elftools/version_tables'

module ELFTools
  module Sections
    # Class of the section recording the versions a file needs of the files it
    # is loaded with.
    #
    # This section is usually named .gnu.version_r, and records the very
    # versions the +DT_VERNEED+ tag points at.
    class VersionNeedSection < Section
      # Instantiate a {VersionNeedSection} object.
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

      # The versions this file needs of the files it is loaded with.
      # @return [Array<ELFTools::VersionTables::Requirement>]
      #   The requirements, in the order the section records them.
      # @example
      #   section.requirements.map { |need| [need.file, need.versions.map(&:name)] }
      #   #=> [['libc.so.6', ['GLIBC_2.4', 'GLIBC_2.2.5']]]
      def requirements
        @requirements ||= VersionTables.new(stream, @section_at.call(header.sh_link),
                                            endian: header.class.self_endian)
                                       .requirements(header.sh_offset.to_i, header.sh_info.to_i)
      end
    end
  end
end
