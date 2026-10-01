# frozen_string_literal: true

require 'elftools/constants'
require 'elftools/structs'
require 'elftools/util'

module ELFTools
  module Sections
    # Class of symbol.
    class Symbol
      attr_reader :stream # @return [#pos=, #read] Streaming object.

      # Instantiate a {ELFTools::Sections::Symbol} object.
      # @param [ELFTools::Structs::ELF32_sym, ELFTools::Structs::ELF64_sym, ELFTools::Structs::Fields] header
      #   The symbol header, or what the file records in one. {ELFTools::Structs::Fields}
      #   answers what the symbol records until something asks for {#header}
      #   itself, which builds the structure then.
      # @param [#pos=, #read] stream The streaming object.
      # @param [ELFTools::Sections::StrTabSection, Proc] symstr
      #   The symbol string section.
      #   If +Proc+ is given, it will be called at the first time
      #   access {Symbol#name}.
      # @param [Integer] machine
      #   The machine of the ELF file, which a name of a value depends on.
      # @param [Proc] version
      #   Call this to get the version this symbol binds to, which only the
      #   symbols a file is loaded by have.
      def initialize(header, stream, symstr: nil, machine: nil, version: nil)
        @fields = header.is_a?(Structs::Fields) ? header : Structs::Fields.of(header)
        @stream = stream
        @symstr = symstr
        @machine = machine
        @version = version
      end

      # The structure the file records this symbol in.
      #
      # One is built here for a symbol read without it, which is what assigning
      # to a field of a symbol needs and what {ELFTools::ELFFile#patches}
      # reports the changes of.
      # @return [ELFTools::Structs::ELF32_sym, ELFTools::Structs::ELF64_sym] The structure.
      def header
        @fields.struct
      end

      # Return the symbol name.
      # @return [String] The name.
      def name
        @name ||= @symstr.call.name_at(@fields[:st_name])
      end

      # The version this symbol binds to.
      #
      # Only the symbols a file is loaded by have one, and only where the file
      # records the versions at all. {#name} is left as the file records it,
      # without the version appended.
      # @return [String, nil] The name of the version.
      # @example
      #   elf.dynamic.symbol_by_name('printf').version
      #   #=> 'GLIBC_2.2.5'
      def version
        binding_version&.name
      end

      # Whether {#version} is one the symbol asks for by name rather than the
      # default one of its name.
      # @return [Boolean] The answer.
      def version_hidden?
        binding_version&.hidden? || false
      end

      # What this symbol is worth, which for most of them is the address of
      # what they name.
      #
      # A symbol of a file that is not loaded anywhere records an offset into
      # the section holding it instead, and one the linker is still to place,
      # which {ELFTools::Constants::SHN_COMMON} marks, records the alignment it
      # needs. The ABI leaves the field to the kind of symbol for that reason,
      # and this answers with what is recorded either way.
      # @return [Integer] The value.
      # @example
      #   elf.section_by_name('.symtab').symbol_by_name('main').value
      #   #=> 4196061 # 0x4006dd
      def value
        @fields[:st_value]
      end

      # How many bytes what this symbol names takes.
      # @return [Integer] The number, zero where the file records none.
      # @example
      #   elf.section_by_name('.symtab').symbol_by_name('main').size
      #   #=> 142
      def size
        @fields[:st_size]
      end

      # What kind of entity this symbol refers to.
      #
      # The available types are listed in {ELFTools::Constants::STT}.
      # @return [Integer] The type.
      # @example
      #   symbol.type == ELFTools::Constants::STT_FUNC
      #   #=> true
      def type
        @fields[:st_info] & 0xf
      end

      # Sets what kind of entity this symbol refers to.
      # @param [Integer] type The type.
      # @raise [ArgumentError] If the four bits recording it cannot hold it.
      # @example
      #   symbol.type = ELFTools::Constants::STT_FUNC
      def type=(type)
        header.st_info = (bind << 4) | Util.fits!(type, 4, 'Symbol type')
      end

      # The name of {#type}.
      #
      # A machine names types of its own, so the name is only known when the
      # machine of the file is.
      # @return [String] The name.
      # @example
      #   symbol.type_name
      #   #=> 'STT_FUNC'
      def type_name
        Constants::STT.mapping(@machine, type)
      end

      # How this symbol is linked against others with the same name.
      #
      # The available bindings are listed in {ELFTools::Constants::STB}.
      # @return [Integer] The binding.
      # @example
      #   symbol.bind == ELFTools::Constants::STB_GLOBAL
      #   #=> true
      def bind
        @fields[:st_info] >> 4
      end

      # Sets how this symbol is linked against others with the same name.
      # @param [Integer] bind The binding.
      # @raise [ArgumentError] If the four bits recording it cannot hold it.
      # @example
      #   symbol.bind = ELFTools::Constants::STB_WEAK
      def bind=(bind)
        header.st_info = (Util.fits!(bind, 4, 'Symbol binding') << 4) | type
      end

      # The name of {#bind}.
      # @return [String] The name.
      # @example
      #   symbol.bind_name
      #   #=> 'STB_GLOBAL'
      def bind_name
        Constants::STB.mapping(@machine, bind)
      end

      # How this symbol is accessed once it becomes part of an executable or
      # shared object.
      #
      # The available visibilities are listed in {ELFTools::Constants::STV}.
      # @return [Integer] The visibility.
      # @example
      #   symbol.visibility == ELFTools::Constants::STV_HIDDEN
      #   #=> true
      def visibility
        @fields[:st_other] & 0x3
      end

      # Sets how this symbol is accessed once it becomes part of an executable
      # or shared object.
      #
      # The rest of +st_other+ is left alone, which some machines record their
      # own thing in.
      # @param [Integer] visibility The visibility.
      # @raise [ArgumentError] If the two bits recording it cannot hold it.
      # @example
      #   symbol.visibility = ELFTools::Constants::STV_HIDDEN
      def visibility=(visibility)
        header.st_other = (header.st_other.to_i & 0xfc) | Util.fits!(visibility, 2, 'Symbol visibility')
      end

      # The name of {#visibility}.
      # @return [String] The name.
      # @example
      #   symbol.visibility_name
      #   #=> 'STV_DEFAULT'
      def visibility_name
        Constants::STV.mapping(@machine, visibility)
      end

      # The version this symbol binds to, whatever is asked of it.
      # @return [ELFTools::Dynamic::Versions::Version, nil] The version.
      def binding_version
        return @binding_version if defined?(@binding_version)

        @binding_version = @version&.call
      end
      private :binding_version

      # The index of the section this symbol is defined in.
      #
      # Values in {ELFTools::Constants::SHN} have special meanings instead of
      # being an index.
      # @return [Integer] The section index.
      # @example
      #   symbol.section_index == ELFTools::Constants::SHN_UNDEF
      #   #=> true # the symbol is undefined and to be resolved at runtime
      def section_index
        @fields[:st_shndx]
      end
    end
  end
end
