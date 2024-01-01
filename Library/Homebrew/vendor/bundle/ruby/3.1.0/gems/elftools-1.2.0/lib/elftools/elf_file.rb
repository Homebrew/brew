# frozen_string_literal: true

require 'elftools/constants'
require 'elftools/exceptions'
require 'elftools/lazy_array'
require 'elftools/sections/sections'
require 'elftools/segments/segments'
require 'elftools/structs'

module ELFTools
  # The main class for using elftools.
  class ELFFile
    attr_reader :stream # @return [#pos=, #read] The +File+ object.
    attr_reader :elf_class # @return [Integer] 32 or 64.
    attr_reader :endian # @return [Symbol] +:little+ or +:big+.

    # Instantiate an {ELFFile} object.
    #
    # @param [#pos=, #read] stream
    #   The +File+ object to be fetch information from.
    # @example
    #   ELFFile.new(File.open('/bin/cat'))
    #   #=> #<ELFTools::ELFFile:0x00564b106c32a0 @elf_class=64, @endian=:little, @stream=#<File:/bin/cat>>
    def initialize(stream)
      @stream = stream
      # always set binmode if stream is an IO object.
      @stream.binmode if @stream.respond_to?(:binmode)
      identify # fetch the most basic information
    end

    # Return the file header.
    #
    # Lazy loading.
    # @return [ELFTools::Structs::ELF_Ehdr] The header.
    def header
      return @header if defined?(@header)

      stream.pos = 0
      @header = Structs::ELF_Ehdr.new(endian: endian, offset: stream.pos)
      @header.elf_class = elf_class
      @header.read(stream)
    end

    # Return the BuildID of ELF.
    # @return [String, nil]
    #   BuildID in hex form will be returned.
    #   +nil+ is returned if the .note.gnu.build-id section
    #   is not found.
    # @example
    #   elf.build_id
    #   #=> '73ab62cb7bc9959ce053c2b711322158708cdc07'
    def build_id
      section = section_by_name('.note.gnu.build-id')
      return nil if section.nil?

      note = section.notes.first
      return nil if note.nil?

      note.desc.unpack1('H*')
    end

    # Get machine architecture.
    #
    # Mappings of architecture can be found
    # in {ELFTools::Constants::EM.mapping}.
    # @return [String]
    #   Name of architecture.
    # @example
    #   elf.machine
    #   #=> 'Advanced Micro Devices X86-64'
    def machine
      ELFTools::Constants::EM.mapping(header.e_machine)
    end

    # Return the ELF type according to +e_type+.
    # @return [String] Type in string format.
    # @example
    #   ELFFile.new(File.open('spec/files/libc.so.6')).elf_type
    #   #=> 'DYN'
    #   ELFFile.new(File.open('spec/files/amd64.elf')).elf_type
    #   #=> 'EXEC'
    def elf_type
      ELFTools::Constants::ET.mapping(header.e_type)
    end

    #========= method about sections

    # Number of sections in this file.
    # @return [Integer] The desired number.
    # @example
    #   elf.num_sections
    #   #=> 29
    def num_sections
      header.e_shnum
    end

    # Acquire the section named as +name+.
    # @param [String] name The desired section name.
    # @return [ELFTools::Sections::Section, nil] The target section.
    # @example
    #   elf.section_by_name('.note.gnu.build-id')
    #   #=> #<ELFTools::Sections::Section:0x005647b1282428>
    #   elf.section_by_name('')
    #   #=> #<ELFTools::Sections::NullSection:0x005647b11da110>
    #   elf.section_by_name('no such section')
    #   #=> nil
    def section_by_name(name)
      each_sections.find { |sec| sec.name == name }
    end

    # Iterate all sections.
    #
    # All sections are lazy loading, the section
    # only be created whenever accessing it.
    # This method is useful for {#section_by_name}
    # since not all sections need to be created.
    # @yieldparam [ELFTools::Sections::Section] section A section.
    # @yieldreturn [void]
    # @return [Enumerator<ELFTools::Sections::Section>, Array<ELFTools::Sections::Section>]
    #   As +Array#each+, if block is not given, a enumerator will be returned,
    #   otherwise, the whole sections will be returned.
    def each_sections(&block)
      return enum_for(:each_sections) unless block_given?

      Array.new(num_sections) do |i|
        section_at(i).tap(&block)
      end
    end

    # Simply use {#sections} to get all sections.
    # @return [Array<ELFTools::Sections::Section>]
    #   Whole sections.
    def sections
      each_sections.to_a
    end

    # Acquire the +n+-th section, 0-based.
    #
    # Sections are lazy loaded.
    # @param [Integer] n The index.
    # @return [ELFTools::Sections::Section, nil]
    #   The target section.
    #   If +n+ is out of bound, +nil+ is returned.
    def section_at(n)
      @sections ||= LazyArray.new(num_sections, &method(:create_section))
      @sections[n]
    end

    # Fetch all sections with specific type.
    #
    # The available types are listed in {ELFTools::Constants::PT}.
    # This method accept giving block.
    # @param [Integer, Symbol, String] type
    #   The type needed, similar format as {#segment_by_type}.
    # @yieldparam [ELFTools::Sections::Section] section A section in specific type.
    # @yieldreturn [void]
    # @return [Array<ELFTools::Sections::section>] The target sections.
    # @example
    #   elf = ELFTools::ELFFile.new(File.open('spec/files/amd64.elf'))
    #   elf.sections_by_type(:rela)
    #   #=> [#<ELFTools::Sections::RelocationSection:0x00563cd3219970>,
    #   #    #<ELFTools::Sections::RelocationSection:0x00563cd3b89d70>]
    def sections_by_type(type, &block)
      type = Util.to_constant(Constants::SHT, type)
      Util.select_by_type(each_sections, type, &block)
    end

    # Get the string table section.
    #
    # This section is acquired by using the +e_shstrndx+
    # in ELF header.
    # @return [ELFTools::Sections::StrTabSection] The desired section.
    def strtab_section
      section_at(header.e_shstrndx)
    end

    #========= method about segments

    # Number of segments in this file.
    # @return [Integer] The desited number.
    def num_segments
      header.e_phnum
    end

    # Iterate all segments.
    #
    # All segments are lazy loading, the segment
    # only be created whenever accessing it.
    # This method is useful for {#segment_by_type}
    # since not all segments need to be created.
    # @yieldparam [ELFTools::Segments::Segment] segment A segment.
    # @yieldreturn [void]
    # @return [Array<ELFTools::Segments::Segment>]
    #   Whole segments will be returned.
    def each_segments(&block)
      return enum_for(:each_segments) unless block_given?

      Array.new(num_segments) do |i|
        segment_at(i).tap(&block)
      end
    end

    # Simply use {#segments} to get all segments.
    # @return [Array<ELFTools::Segments::Segment>]
    #   Whole segments.
    def segments
      each_segments.to_a
    end

    # Get the first segment with +p_type=type+.
    # The available types are listed in {ELFTools::Constants::PT}.
    #
    # @note
    #   This method will return the first segment found,
    #   to found all segments with specific type you can use {#segments_by_type}.
    # @param [Integer, Symbol, String] type
    #   See examples for clear usage.
    # @return [ELFTools::Segments::Segment] The target segment.
    # @example
    #   # type as an integer
    #   elf.segment_by_type(ELFTools::Constants::PT_NOTE)
    #   #=>  #<ELFTools::Segments::NoteSegment:0x005629dda1e4f8>
    #
    #   elf.segment_by_type(4) # PT_NOTE
    #   #=>  #<ELFTools::Segments::NoteSegment:0x005629dda1e4f8>
    #
    #   # type as a symbol
    #   elf.segment_by_type(:PT_NOTE)
    #   #=>  #<ELFTools::Segments::NoteSegment:0x005629dda1e4f8>
    #
    #   # you can do this
    #   elf.segment_by_type(:note) # will be transformed into `PT_NOTE`
    #   #=>  #<ELFTools::Segments::NoteSegment:0x005629dda1e4f8>
    #
    #   # type as a string
    #   elf.segment_by_type('PT_NOTE')
    #   #=>  #<ELFTools::Segments::NoteSegment:0x005629dda1e4f8>
    #
    #   # this is ok
    #   elf.segment_by_type('note') # will be tranformed into `PT_NOTE`
    #   #=>  #<ELFTools::Segments::NoteSegment:0x005629dda1e4f8>
    # @example
    #   elf.segment_by_type(1337)
    #   # ArgumentError: No constants in Constants::PT is 1337
    #
    #   elf.segment_by_type('oao')
    #   # ArgumentError: No constants in Constants::PT named "PT_OAO"
    # @example
    #   elf.segment_by_type(0)
    #   #=> nil # no such segment exists
    def segment_by_type(type)
      type = Util.to_constant(Constants::PT, type)
      each_segments.find { |seg| seg.header.p_type == type }
    end

    # Fetch all segments with specific type.
    #
    # If you want to find only one segment,
    # use {#segment_by_type} instead.
    # This method accept giving block.
    # @param [Integer, Symbol, String] type
    #   The type needed, same format as {#segment_by_type}.
    # @yieldparam [ELFTools::Segments::Segment] segment A segment in specific type.
    # @yieldreturn [void]
    # @return [Array<ELFTools::Segments::Segment>] The target segments.
    def segments_by_type(type, &block)
      type = Util.to_constant(Constants::PT, type)
      Util.select_by_type(each_segments, type, &block)
    end

    # Acquire the +n+-th segment, 0-based.
    #
    # Segments are lazy loaded.
    # @param [Integer] n The index.
    # @return [ELFTools::Segments::Segment, nil]
    #   The target segment.
    #   If +n+ is out of bound, +nil+ is returned.
    def segment_at(n)
      @segments ||= LazyArray.new(num_segments, &method(:create_segment))
      @segments[n]
    end

    # Get the offset related to file, given virtual memory address.
    #
    # This method should work no matter ELF is a PIE or not.
    # This method refers from (actually equals to) binutils/readelf.c#offset_from_vma.
    # @param [Integer] vma The virtual address to be queried.
    # @return [Integer] Related file offset.
    # @example
    #   elf = ELFTools::ELFFile.new(File.open('/bin/cat'))
    #   elf.offset_from_vma(0x401337)
    #   #=> 4919 # 0x1337
    def offset_from_vma(vma, size = 0)
      segments_by_type(:load) do |seg|
        return seg.vma_to_offset(vma) if seg.vma_in?(vma, size)
      end
    end

    # The patch status.
    # @return [Hash{Integer => String}]
    def patches
      patch = {}
      loaded_headers.each do |header|
        header.patches.each do |key, val|
          patch[key + header.offset] = val
        end
      end
      patch
    end

    # Apply patches and save as +filename+.
    #
    # @param [String] filename
    # @return [void]
    def save(filename)
      stream.pos = 0
      all = stream.read.force_encoding('ascii-8bit')
      patches.each do |pos, val|
        all[pos, val.size] = val
      end
      File.binwrite(filename, all)
    end

    private

    # bad idea..
    def loaded_headers
      explore = lambda do |obj|
        return obj if obj.is_a?(::ELFTools::Structs::ELFStruct)
        return obj.map(&explore) if obj.is_a?(Array)

        obj.instance_variables.map do |s|
          explore.call(obj.instance_variable_get(s))
        end
      end
      explore.call(self).flatten
    end

    def identify
      stream.pos = 0
      magic = stream.read(4)
      raise ELFMagicError, "Invalid magic number #{magic.inspect}" unless magic == Constants::ELFMAG

      ei_class = stream.read(1).ord
      @elf_class = {
        1 => 32,
        2 => 64
      }[ei_class]
      raise ELFClassError, format('Invalid EI_CLASS "\x%02x"', ei_class) if elf_class.nil?

      ei_data = stream.read(1).ord
      @endian = {
        1 => :little,
        2 => :big
      }[ei_data]
      raise ELFDataError, format('Invalid EI_DATA "\x%02x"', ei_data) if endian.nil?
    end

    def create_section(n)
      stream.pos = header.e_shoff + n * header.e_shentsize
      shdr = Structs::ELF_Shdr.new(endian: endian, offset: stream.pos)
      shdr.elf_class = elf_class
      shdr.read(stream)
      Sections::Section.create(shdr, stream,
                               offset_from_vma: method(:offset_from_vma),
                               strtab: method(:strtab_section),
                               section_at: method(:section_at))
    end

    def create_segment(n)
      stream.pos = header.e_phoff + n * header.e_phentsize
      phdr = Structs::ELF_Phdr[elf_class].new(endian: endian, offset: stream.pos)
      phdr.elf_class = elf_class
      Segments::Segment.create(phdr.read(stream), stream, offset_from_vma: method(:offset_from_vma))
    end
  end
end
