# frozen_string_literal: true

require 'elftools/constants'
require 'elftools/structs'

module ELFTools
  module Dynamic
    # A tag class.
    class Tag
      attr_reader :stream # @return [#pos=, #read] Streaming object.

      # Instantiate a {ELFTools::Dynamic::Tag} object.
      # @param [ELFTools::Structs::ELF_Dyn, ELFTools::Structs::Fields] header
      #   The dynamic tag header, or what the file records in one.
      #   {ELFTools::Structs::Fields} answers what the tag records until
      #   something asks for {#header} itself, which builds the structure then.
      # @param [#pos=, #read] stream Streaming object.
      # @param [ELFTools::Dynamic::StringTable] strtab
      #   The string table the names of tags are recorded in.
      def initialize(header, stream, strtab)
        @fields = header.is_a?(Structs::Fields) ? header : Structs::Fields.of(header)
        @stream = stream
        @strtab = strtab
      end

      # The structure the file records this tag in.
      #
      # One is built here for a tag read without it, which is what assigning to
      # a field of one needs and what {ELFTools::ELFFile#patches} reports the
      # changes of.
      # @return [ELFTools::Structs::ELF_Dyn] The structure.
      def header
        @fields.struct
      end

      # What kind of tag this is, which {ELFTools::Constants::DT} names.
      # @return [Integer] The type.
      # @example
      #   dynamic.tag_by_type(:needed).type == ELFTools::Constants::DT_NEEDED
      #   #=> true
      def type
        @fields[:d_tag]
      end

      # Some dynamic have name.
      TYPE_WITH_NAME = [Constants::DT_NEEDED,
                        Constants::DT_SONAME,
                        Constants::DT_RPATH,
                        Constants::DT_RUNPATH].freeze
      # Return the content of this tag records.
      #
      # For normal tags, this method just return
      # +header.d_val+. For tags with +header.d_val+
      # in meaning of string offset (e.g. DT_NEEDED), this method would
      # return the string it specified.
      # Tags with type in {TYPE_WITH_NAME} are those tags with name.
      # @return [Integer, String] The content this tag records.
      # @example
      #   dynamic = elf.segment_by_type(:dynamic)
      #   dynamic.tag_by_type(:init).value
      #   #=> 4195600 # 0x400510
      #   dynamic.tag_by_type(:needed).value
      #   #=> 'libc.so.6'
      def value
        name || @fields[:d_val]
      end

      # Is this tag has a name?
      #
      # The criteria here is if this tag's type is in {TYPE_WITH_NAME}.
      # @return [Boolean] Is this tag has a name.
      def name?
        TYPE_WITH_NAME.include?(type)
      end

      # Return the name of this tag.
      #
      # Only tags with name would return a name.
      # Others would return +nil+.
      # @return [String, nil] The name.
      def name
        return nil unless name?

        @strtab.name_at(@fields[:d_val])
      end
    end
  end
end
