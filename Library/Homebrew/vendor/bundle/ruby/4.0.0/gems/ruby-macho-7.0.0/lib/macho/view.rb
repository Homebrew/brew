# frozen_string_literal: true

module MachO
  # A representation of some unspecified Mach-O data.
  class MachOView
    # @return [MachOFile] that this view belongs to
    attr_reader :macho_file

    # @return [String] the raw Mach-O data
    attr_reader :raw_data

    # @return [Symbol] the endianness of the data (`:big` or `:little`)
    attr_reader :endianness

    # @return [Integer] the offset of the relevant data (in {#raw_data})
    attr_reader :offset

    # Creates a new MachOView.
    # @param macho_file [MachOFile] the file this view slice is from
    # @param raw_data [String] the raw Mach-O data
    # @param endianness [Symbol] the endianness of the data
    # @param offset [Integer] the offset of the relevant data
    def initialize(macho_file, raw_data, endianness, offset)
      @macho_file = macho_file
      @raw_data = raw_data
      @endianness = endianness
      @offset = offset
    end

    # @return [Hash] a hash representation of this {MachOView}.
    def to_h
      {
        "endianness" => endianness,
        "offset" => offset,
      }
    end

    def inspect
      "#<#{self.class}:0x#{(object_id << 1).to_s(16)} @endianness=#{@endianness.inspect}, @offset=#{@offset.inspect}, length=#{@raw_data.length}>"
    end
  end
end
