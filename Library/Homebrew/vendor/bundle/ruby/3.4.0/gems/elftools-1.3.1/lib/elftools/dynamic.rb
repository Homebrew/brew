# frozen_string_literal: true

module ELFTools
  # Define common methods for dynamic sections and dynamic segments.
  #
  # @note
  #   This module can only be included by {ELFTools::Sections::DynamicSection}
  #   and {ELFTools::Segments::DynamicSegment} because methods here assume some
  #   attributes exist.
  module Dynamic
    # Iterate all tags.
    #
    # @note
    #   This method assume the following methods already exist:
    #     header
    #     tag_start
    # @yieldparam [ELFTools::Dynamic::Tag] tag
    # @return [Enumerator<ELFTools::Dynamic::Tag>, Array<ELFTools::Dynamic::Tag>]
    #   If block is not given, an enumerator will be returned.
    #   Otherwise, return array of tags.
    def each_tags(&block)
      return enum_for(:each_tags) unless block_given?

      arr = []
      0.step do |i|
        tag = tag_at(i).tap(&block)
        arr << tag
        break if tag.header.d_tag == ELFTools::Constants::DT_NULL
      end
      arr
    end

    # Use {#tags} to get all tags.
    # @return [Array<ELFTools::Dynamic::Tag>]
    #   Array of tags.
    def tags
      @tags ||= each_tags.to_a
    end

    # Get a tag of specific type.
    # @param [Integer, Symbol, String] type
    #   Constant value, symbol, or string of type
    #   is acceptable. See examples for more information.
    # @return [ELFTools::Dynamic::Tag] The desired tag.
    # @example
    #   dynamic = elf.segment_by_type(:dynamic)
    #   # type as integer
    #   dynamic.tag_by_type(0) # the null tag
    #   #=>  #<ELFTools::Dynamic::Tag:0x0055b5a5ecad28 @header={:d_tag=>0, :d_val=>0}>
    #   dynamic.tag_by_type(ELFTools::Constants::DT_NULL)
    #   #=>  #<ELFTools::Dynamic::Tag:0x0055b5a5ecad28 @header={:d_tag=>0, :d_val=>0}>
    #
    #   # symbol
    #   dynamic.tag_by_type(:null)
    #   #=>  #<ELFTools::Dynamic::Tag:0x0055b5a5ecad28 @header={:d_tag=>0, :d_val=>0}>
    #   dynamic.tag_by_type(:pltgot)
    #   #=> #<ELFTools::Dynamic::Tag:0x0055d3d2d91b28 @header={:d_tag=>3, :d_val=>6295552}>
    #
    #   # string
    #   dynamic.tag_by_type('null')
    #   #=>  #<ELFTools::Dynamic::Tag:0x0055b5a5ecad28 @header={:d_tag=>0, :d_val=>0}>
    #   dynamic.tag_by_type('DT_PLTGOT')
    #   #=> #<ELFTools::Dynamic::Tag:0x0055d3d2d91b28 @header={:d_tag=>3, :d_val=>6295552}>
    def tag_by_type(type)
      type = Util.to_constant(Constants::DT, type)
      each_tags.find { |tag| tag.header.d_tag == type }
    end

    # Get tags of specific type.
    # @param [Integer, Symbol, String] type
    #   Constant value, symbol, or string of type
    #   is acceptable. See examples for more information.
    # @return [Array<ELFTools::Dynamic::Tag>] The desired tags.
    #
    # @see #tag_by_type
    def tags_by_type(type)
      type = Util.to_constant(Constants::DT, type)
      each_tags.select { |tag| tag.header.d_tag == type }
    end

    # Get the +n+-th tag.
    #
    # Tags are lazy loaded.
    # @note
    #   This method assume the following methods already exist:
    #     header
    #     tag_start
    # @note
    #   We cannot do bound checking of +n+ here since the only way to get size
    #   of tags is calling +tags.size+.
    # @param [Integer] n The index.
    # @return [ELFTools::Dynamic::Tag] The desired tag.
    def tag_at(n)
      return if n.negative?

      @tag_at_map ||= {}
      return @tag_at_map[n] if @tag_at_map[n]

      dyn = Structs::ELF_Dyn.new(endian:)
      dyn.elf_class = header.elf_class
      stream.pos = tag_start + n * dyn.num_bytes
      dyn.offset = stream.pos
      @tag_at_map[n] = Tag.new(dyn.read(stream), stream, method(:str_offset))
    end

    private

    def endian
      header.class.self_endian
    end

    # Get the DT_STRTAB's +d_val+ offset related to file.
    def str_offset
      # TODO: handle DT_STRTAB not exitsts.
      @str_offset ||= @offset_from_vma.call(tag_by_type(:strtab).header.d_val.to_i)
    end

    # A tag class.
    class Tag
      attr_reader :header # @return [ELFTools::Structs::ELF_Dyn] The dynamic tag header.
      attr_reader :stream # @return [#pos=, #read] Streaming object.

      # Instantiate a {ELFTools::Dynamic::Tag} object.
      # @param [ELF_Dyn] header The dynamic tag header.
      # @param [#pos=, #read] stream Streaming object.
      # @param [Method] str_offset
      #   Call this method to get the string offset related
      #   to file.
      def initialize(header, stream, str_offset)
        @header = header
        @stream = stream
        @str_offset = str_offset
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
        name || header.d_val.to_i
      end

      # Is this tag has a name?
      #
      # The criteria here is if this tag's type is in {TYPE_WITH_NAME}.
      # @return [Boolean] Is this tag has a name.
      def name?
        TYPE_WITH_NAME.include?(header.d_tag)
      end

      # Return the name of this tag.
      #
      # Only tags with name would return a name.
      # Others would return +nil+.
      # @return [String, nil] The name.
      def name
        return nil unless name?

        Util.cstring(stream, @str_offset.call + header.d_val.to_i)
      end
    end
  end
end
