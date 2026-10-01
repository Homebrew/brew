# frozen_string_literal: true

require 'bindata'

require 'elftools/exceptions'

module ELFTools
  # Define ELF related structures in this module.
  #
  # Structures are fetched from https://github.com/torvalds/linux/blob/master/include/uapi/linux/elf.h.
  # Use gem +bindata+ to have these structures support 32/64 bits and little/big endian simultaneously.
  module Structs
    # The base structure to define common methods.
    class ELFStruct < BinData::Record
      # DRY. Many fields have different type in different arch.
      CHOICE_SIZE_T = proc do |t = 'uint'|
        { selection: :elf_class, choices: { 32 => :"#{t}32", 64 => :"#{t}64" }, copy_on_change: true }
      end

      # How an integer of each width is packed, for +String#unpack+, whether it
      # records a sign or not.
      UNPACK_TEMPLATES = {
        little: {
          false => { 1 => 'C', 2 => 'v', 4 => 'V', 8 => 'Q<' },
          true => { 1 => 'c', 2 => 's<', 4 => 'l<', 8 => 'q<' }
        },
        big: {
          false => { 1 => 'C', 2 => 'n', 4 => 'N', 8 => 'Q>' },
          true => { 1 => 'c', 2 => 's>', 4 => 'l>', 8 => 'q>' }
        }
      }.freeze

      # Bytes of set bits to read a prototype from, longer than any structure
      # here, so that reading one never runs short of them.
      SET_BITS = ("\xff" * 256).b.freeze

      attr_accessor :elf_class # @return [Integer] 32 or 64.
      attr_accessor :offset # @return [Integer] The file offset of this header.

      # Reads the structure, remembering the bytes it was read from.
      #
      # They are taken back off the stream. A stream that cannot be seeked is
      # serialized instead.
      # @param [#pos=, #read] io The streaming object.
      # @return [ELFTools::Structs::ELFStruct] Itself.
      def read(io)
        start = io.pos if io.respond_to?(:pos)
        super.tap { @source = start.nil? ? to_binary_s : bytes_read(io, start) }
      end

      # Which bytes of this structure have been changed since it was read.
      #
      # Every field answers alike, however deeply it is nested, because what is
      # compared is the bytes the structure occupies rather than the
      # assignments that were made to it. A field assigned the value it
      # already held leaves nothing behind.
      # @return [Hash{Integer => String}]
      #   Where each run of changed bytes starts, as an offset into the
      #   structure, and the bytes it is to be replaced with.
      # @example
      #   header.e_ident.ei_abiversion = 41
      #   header.patches
      #   #=> { 8 => "\x29" }
      def patches
        return {} if @source.nil?

        changed_runs(@source, to_binary_s)
      end

      # BinData hash(Snapshot) that behaves like HashWithIndifferentAccess
      alias to_h snapshot

      private

      # The bytes a read has just taken from a stream, leaving it where the
      # read left it.
      # @param [#pos=, #read] io The streaming object.
      # @param [Integer] start Where the read began.
      # @return [String] The bytes.
      def bytes_read(io, start)
        here = io.pos
        io.pos = start
        io.read(here - start).tap { io.pos = here }
      end

      # Where two strings of bytes differ, as the runs of bytes that differ.
      #
      # Only as far as +before+ reaches, so that a patch never covers more of
      # the file than the structure it came from.
      # @param [String] before The bytes as they were.
      # @param [String] after The bytes as they are.
      # @return [Hash{Integer => String}] Where each run starts, and its bytes.
      def changed_runs(before, after)
        runs = {}
        start = nil
        (0..before.bytesize).each do |i|
          if i < before.bytesize && before.getbyte(i) != after.getbyte(i)
            start ||= i
          elsif start
            runs[start] = after.byteslice(start, i - start)
            start = nil
          end
        end
        runs
      end

      class << self
        # Hooks the constructor.
        #
        # +BinData::Record+ doesn't allow us to override +#initialize+, so we hack +new+ here.
        #
        # Keyword arguments have to be taken as a trailing +Hash+ instead of +**kwargs+: bindata
        # defines +new+ on each record class taking +*args+ only, then re-dispatches it to the
        # endian-specific subclass this method actually runs on, which collapses the caller's
        # keywords into a positional +Hash+ on the way. See +override_new_in_class+ in
        # https://github.com/dmendel/bindata/blob/master/lib/bindata/dsl.rb, which is the same in
        # 2.5.1, 3.0.0, and master.
        def new(*args)
          kwargs = args.last.is_a?(Hash) ? args.last : {}
          offset = kwargs.delete(:offset)
          super.tap { |obj| obj.offset = offset }
        end

        # Gets the endianness of current class.
        #
        # A class is of one endianness for as long as it exists, and asking
        # bindata what it is named costs more than remembering the answer.
        # @return [:little, :big] The endianness.
        def self_endian
          @self_endian ||= bindata_name[-2..] == 'be' ? :big : :little
        end

        # What the fields of a structure record, read straight from its bytes.
        #
        # Reading a table of structures costs a structure for every entry of
        # it otherwise, which is most of what reading the table costs. Nothing
        # is remembered of the bytes, so a caller that means to assign to a
        # field wants a structure instead.
        # @param [String] bytes The bytes a structure is recorded in.
        # @param [Integer] elf_class 32 or 64, which decides how wide the fields recording an address are.
        # @param [:little, :big] endian The endianness the file records it in.
        # @return [Hash{Symbol => Integer}] Each field, and what it records.
        # @raise [ELFTools::ELFError] If this is not a structure of integers.
        # @example
        #   ELF64_sym.unpack_fields(bytes, elf_class: 64, endian: :little)
        #   #=> { st_name: 1, st_info: 18, st_other: 0, st_shndx: 15, st_value: 4198864, st_size: 101 }
        def unpack_fields(bytes, elf_class:, endian:)
          values = bytes.unpack(unpack_template(elf_class, endian))
          fields = {}
          # Paired by hand rather than zipped, which would make an array for
          # every field of every structure read.
          field_names(elf_class, endian).each_with_index { |name, i| fields[name] = values[i] }
          fields
        end

        # How many bytes a structure of this kind takes.
        # @param [Integer] elf_class 32 or 64, which decides how wide the fields recording an address are.
        # @param [:little, :big] endian The endianness the file records it in.
        # @return [Integer] The number.
        # @example
        #   ELF64_sym.num_bytes(elf_class: 64, endian: :little)
        #   #=> 24
        def num_bytes(elf_class:, endian:)
          @num_bytes ||= {}
          # Nested rather than keyed by the pair, which would make an array of
          # it for every structure read.
          (@num_bytes[elf_class] ||= {})[endian] ||= prototype(elf_class, endian).num_bytes
        end

        # Packs an integer to string.
        #
        # @deprecated
        #   Nothing here packs a patch by hand anymore, see {ELFStruct#patches}.
        #   This is kept for anyone who called it and goes in the next major.
        # @param [Integer] val
        # @param [Integer] bytes
        # @return [String]
        def pack(val, bytes)
          raise ArgumentError, "Not supported assign type #{val.class}" unless val.is_a?(Integer)

          number = val & ((1 << (8 * bytes)) - 1)
          out = []
          bytes.times do
            out << (number & 0xff)
            number >>= 8
          end
          out = out.pack('C*')
          self_endian == :little ? out : out.reverse
        end

        private

        # A structure of this kind with every bit of it set, which the layout is
        # read off: how wide each field is, and whether it records a sign.
        #
        # Every structure of a kind and a class is laid out alike, so one is
        # built for the kind rather than for each question asked about it.
        # @param [Integer] elf_class 32 or 64, which decides how wide the fields recording an address are.
        # @param [:little, :big] endian The endianness the file records it in.
        # @return [ELFTools::Structs::ELFStruct] The structure.
        def prototype(elf_class, endian)
          @prototypes ||= {}
          (@prototypes[elf_class] ||= {})[endian] ||= begin
            struct = new(endian: endian)
            struct.elf_class = elf_class
            struct.read(SET_BITS)
          end
        end

        # What the fields of this structure are named, in the order they are
        # recorded.
        # @param [Integer] elf_class 32 or 64, which decides how wide the fields recording an address are.
        # @param [:little, :big] endian The endianness the file records it in.
        # @return [Array<Symbol>] The names.
        def field_names(elf_class, endian)
          @field_names ||= {}
          (@field_names[elf_class] ||= {})[endian] ||= prototype(elf_class, endian).field_names
        end

        # How the fields of this structure are packed, as a template for
        # +String#unpack+.
        # @param [Integer] elf_class 32 or 64, which decides how wide the fields recording an address are.
        # @param [:little, :big] endian The endianness the file records it in.
        # @return [String] The template.
        def unpack_template(elf_class, endian)
          @unpack_templates ||= {}
          (@unpack_templates[elf_class] ||= {})[endian] ||=
            prototype(elf_class, endian).each_pair.map { |_, field| field_template(field, endian) }.join
        end

        # How one field is packed, which is its width and whether what it read
        # from a field of set bits came back negative.
        # @param [BinData::Base] field The field, read from bits that are all set.
        # @param [:little, :big] endian The endianness the file records it in.
        # @return [String] The template.
        # @raise [ELFTools::ELFError] If the field is not an integer of 1, 2, 4, or 8 bytes.
        def field_template(field, endian)
          width = field.num_bytes
          template = UNPACK_TEMPLATES.fetch(endian)
          raise ELFError, format('%s is not a structure of integers', name) unless template[false].key?(width)

          template.fetch(field.to_i.negative?)[width]
        end
      end
    end

    # What a structure the file records at an offset holds, read without
    # building the structure.
    #
    # Reading a table of structures costs a structure for every entry of it
    # otherwise, and setting up the fields of one is most of what it costs.
    # {#struct} builds one for whatever wants the structure itself, which
    # is what assigning to a field takes, and what is assigned is answered
    # with from then on.
    class Fields
      attr_reader :elf_class # @return [Integer] 32 or 64.
      attr_reader :endian # @return [:little, :big] The endianness the file records it in.

      # What a structure already built holds, for a caller that has one.
      # @param [ELFTools::Structs::ELFStruct] struct The structure.
      # @return [ELFTools::Structs::Fields] The fields.
      def self.of(struct)
        allocate.tap { |fields| fields.send(:built_from, struct) }
      end

      # Fields nothing in the file records, for what a file states some other
      # way than by recording a structure of it.
      #
      # There is nothing to read and nothing to patch, so a structure is only
      # built if something asks for one, and is built from these.
      # @param [Class] klass The structure class.
      # @param [Hash{Symbol => Integer}] fields What each field is to record.
      # @param [Integer] elf_class 32 or 64.
      # @param [:little, :big] endian The endianness the file records it in.
      # @param [Integer] offset Where in the file this came from.
      # @return [ELFTools::Structs::Fields] The fields.
      # @example
      #   Fields.from(ELF_Rel, { r_offset: 0x1000 }, elf_class: 64, endian: :little, offset: 0x40)
      def self.from(klass, fields, elf_class:, endian:, offset:)
        allocate.tap { |made| made.send(:made_of, klass, fields, elf_class, endian, offset) }
      end

      # @param [Class] klass The structure class.
      # @param [#pos=, #read] stream The streaming object.
      # @param [Integer] offset The file offset the structure is recorded at.
      # @param [Integer] elf_class 32 or 64.
      # @param [:little, :big] endian The endianness the file records it in.
      # @raise [EOFError] If the file does not reach that far.
      def initialize(klass, stream, offset, elf_class:, endian:)
        @klass = klass
        @stream = stream
        @offset = offset
        @elf_class = elf_class
        @endian = endian
        @fields = unpack
      end

      # What one field of the structure records.
      #
      # The structure answers once there is one, so that a field assigned to
      # reads back as it was assigned.
      # @param [Symbol] name The name of the field.
      # @return [Integer] The value.
      # @example
      #   fields[:st_value]
      #   #=> 4198864
      def [](name)
        return @struct[name].to_i if @struct

        @fields[name]
      end

      # Assigns to one field.
      #
      # The structure takes the assignment wherever the file records one, so
      # that {ELFTools::ELFFile#patches} reports it. Fields the file records
      # no structure of take it themselves, there being nothing to patch.
      # @param [Symbol] name The name of the field.
      # @param [Integer] value What it is to record.
      # @return [void]
      def []=(name, value)
        if @struct.nil? && @stream.nil?
          @fields[name] = value
        else
          struct[name] = value
        end
      end

      # The structure itself, read from where the file records it, or built
      # from these fields where it records none.
      #
      # The same one however often it is asked for, so that assigning to a
      # field of it is not forgotten.
      # @return [ELFTools::Structs::ELFStruct] The structure.
      def struct
        @struct ||= @stream.nil? ? build : read
      end

      private

      # Takes a structure that is already built as what these fields hold.
      # @param [ELFTools::Structs::ELFStruct] struct The structure.
      # @return [void]
      def built_from(struct)
        @struct = struct
        @elf_class = struct.elf_class
        @endian = struct.class.self_endian
      end

      # Takes fields nothing in the file records a structure of.
      # @return [void]
      def made_of(klass, fields, elf_class, endian, offset)
        @klass = klass
        @fields = fields
        @elf_class = elf_class
        @endian = endian
        @offset = offset
      end

      # The structure the file records, read from where it records it.
      # @return [ELFTools::Structs::ELFStruct] The structure.
      def read
        struct = new_struct
        @stream.pos = @offset
        struct.read(@stream)
      end

      # A structure holding what these fields hold, for fields the file
      # records no structure of.
      # @return [ELFTools::Structs::ELFStruct] The structure.
      def build
        new_struct.tap { |struct| @fields.each { |name, value| struct[name] = value } }
      end

      # A structure of this kind, of the class and the order of the file, and
      # of where in it this came from.
      # @return [ELFTools::Structs::ELFStruct] The structure.
      def new_struct
        struct = @klass.new(endian: @endian, offset: @offset)
        struct.elf_class = @elf_class
        struct
      end

      # What the fields record, read from the bytes recording them.
      # @return [Hash{Symbol => Integer}] Each field, and what it records.
      # @raise [EOFError] If the file does not reach that far, as reading the structure itself does.
      def unpack
        num_bytes = @klass.num_bytes(elf_class: @elf_class, endian: @endian)
        @stream.pos = @offset
        bytes = @stream.read(num_bytes)
        raise EOFError, 'End of file reached' if bytes.nil? || bytes.bytesize < num_bytes

        @klass.unpack_fields(bytes, elf_class: @elf_class, endian: @endian)
      end
    end

    # ELF header structure.
    class ELF_Ehdr < ELFStruct
      endian :big_and_little
      struct :e_ident do
        string :magic, read_length: 4
        int8 :ei_class
        int8 :ei_data
        int8 :ei_version
        int8 :ei_osabi
        int8 :ei_abiversion
        string :ei_padding, read_length: 7 # no use
      end
      uint16 :e_type
      uint16 :e_machine
      uint32 :e_version
      # entry point
      choice :e_entry, **CHOICE_SIZE_T['uint']
      choice :e_phoff, **CHOICE_SIZE_T['uint']
      choice :e_shoff, **CHOICE_SIZE_T['uint']
      uint32 :e_flags
      uint16 :e_ehsize # size of this header
      uint16 :e_phentsize # size of each segment
      uint16 :e_phnum # number of segments
      uint16 :e_shentsize # size of each section
      uint16 :e_shnum # number of sections
      uint16 :e_shstrndx # index of string table section
    end

    # Section header structure.
    class ELF_Shdr < ELFStruct
      endian :big_and_little
      uint32 :sh_name
      uint32 :sh_type
      choice :sh_flags, **CHOICE_SIZE_T['uint']
      choice :sh_addr, **CHOICE_SIZE_T['uint']
      choice :sh_offset, **CHOICE_SIZE_T['uint']
      choice :sh_size, **CHOICE_SIZE_T['uint']
      uint32 :sh_link
      uint32 :sh_info
      choice :sh_addralign, **CHOICE_SIZE_T['uint']
      choice :sh_entsize, **CHOICE_SIZE_T['uint']
    end

    # Program header structure for 32-bit.
    class ELF32_Phdr < ELFStruct
      endian :big_and_little
      uint32 :p_type
      uint32 :p_offset
      uint32 :p_vaddr
      uint32 :p_paddr
      uint32 :p_filesz
      uint32 :p_memsz
      uint32 :p_flags
      uint32 :p_align
    end

    # Program header structure for 64-bit.
    class ELF64_Phdr < ELFStruct
      endian :big_and_little
      uint32 :p_type
      uint32 :p_flags
      uint64 :p_offset
      uint64 :p_vaddr
      uint64 :p_paddr
      uint64 :p_filesz
      uint64 :p_memsz
      uint64 :p_align
    end

    # Gets the class of program header according to bits.
    ELF_Phdr = {
      32 => ELF32_Phdr,
      64 => ELF64_Phdr
    }.freeze

    # Symbol structure for 32-bit.
    class ELF32_sym < ELFStruct
      endian :big_and_little
      uint32 :st_name
      uint32 :st_value
      uint32 :st_size
      uint8 :st_info
      uint8 :st_other
      uint16 :st_shndx
    end

    # Symbol structure for 64-bit.
    class ELF64_sym < ELFStruct
      endian :big_and_little
      uint32 :st_name  # Symbol name, index in string tbl
      uint8 :st_info   # Type and binding attributes
      uint8 :st_other  # No defined meaning, 0
      uint16 :st_shndx # Associated section index
      uint64 :st_value # Value of the symbol
      uint64 :st_size  # Associated symbol size
    end

    # Get symbol header class according to bits.
    ELF_sym = {
      32 => ELF32_sym,
      64 => ELF64_sym
    }.freeze

    # Header of the symbol hash table +DT_HASH+ points at.
    class ELF_Hash < ELFStruct
      endian :big_and_little
      uint32 :nbucket # Number of buckets
      uint32 :nchain  # Number of chains, which is how many symbols there are
    end

    # Header of the symbol hash table +DT_GNU_HASH+ points at.
    class ELF_GnuHash < ELFStruct
      endian :big_and_little
      uint32 :nbuckets  # Number of buckets
      uint32 :symndx    # The first symbol index the table indexes
      uint32 :maskwords # Number of words the bloom filter takes
      uint32 :shift2    # The second shift the bloom filter is built with
    end

    # An entry of the table of versions a file needs of another, which the
    # +vn_next+ of the one before it points at.
    class ELF_Verneed < ELFStruct
      endian :big_and_little
      uint16 :vn_version # Revision of this structure
      uint16 :vn_cnt     # How many versions of the file are needed
      uint32 :vn_file    # Name of the file, as an offset into the string table
      uint32 :vn_aux     # Where the versions start, as an offset from here
      uint32 :vn_next    # Where the next entry is, as an offset from here
    end

    # A version an {ELF_Verneed} needs, which the +vna_next+ of the one before
    # it points at.
    class ELF_Vernaux < ELFStruct
      endian :big_and_little
      uint32 :vna_hash  # Hash of the name
      uint16 :vna_flags # Flags
      uint16 :vna_other # The index the symbols name this version with
      uint32 :vna_name  # The name, as an offset into the string table
      uint32 :vna_next  # Where the next version is, as an offset from here
    end

    # An entry of the table of versions a file defines, which the +vd_next+ of
    # the one before it points at.
    class ELF_Verdef < ELFStruct
      endian :big_and_little
      uint16 :vd_version # Revision of this structure
      uint16 :vd_flags   # Flags
      uint16 :vd_ndx     # The index the symbols name this version with
      uint16 :vd_cnt     # How many names follow, the version and its ancestors
      uint32 :vd_hash    # Hash of the name
      uint32 :vd_aux     # Where the names start, as an offset from here
      uint32 :vd_next    # Where the next entry is, as an offset from here
    end

    # A name an {ELF_Verdef} records, its own or an ancestor's, which the
    # +vda_next+ of the one before it points at.
    class ELF_Verdaux < ELFStruct
      endian :big_and_little
      uint32 :vda_name # The name, as an offset into the string table
      uint32 :vda_next # Where the next name is, as an offset from here
    end

    # Note header.
    class ELF_Nhdr < ELFStruct
      endian :big_and_little
      uint32 :n_namesz # Name size
      uint32 :n_descsz # Content size
      uint32 :n_type   # Content type
    end

    # Dynamic tag header.
    class ELF_Dyn < ELFStruct
      endian :big_and_little
      choice :d_tag, **CHOICE_SIZE_T['int']
      # This is an union type named +d_un+ in original source,
      # simplify it to be +d_val+ here.
      choice :d_val, **CHOICE_SIZE_T['uint']
    end

    # Rel header in .rel section.
    class ELF_Rel < ELFStruct
      endian :big_and_little
      choice :r_offset, **CHOICE_SIZE_T['uint']
      choice :r_info, **CHOICE_SIZE_T['uint']

      # Compatibility with ELF_Rela, both can be used interchangeably
      def r_addend
        nil
      end
    end

    # Rela header in .rela section.
    class ELF_Rela < ELFStruct
      endian :big_and_little
      choice :r_offset, **CHOICE_SIZE_T['uint']
      choice :r_info, **CHOICE_SIZE_T['uint']
      choice :r_addend, **CHOICE_SIZE_T['int']
    end
  end
end
