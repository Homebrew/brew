# frozen_string_literal: true

# Require this file to load all sections classes.

require 'elftools/sections/section'

require 'elftools/sections/dynamic_section'
require 'elftools/sections/note_section'
require 'elftools/sections/null_section'
require 'elftools/sections/relative_relocation_section'
require 'elftools/sections/relocation_section'
require 'elftools/sections/str_tab_section'
require 'elftools/sections/sym_tab_section'
require 'elftools/sections/version_definition_section'
require 'elftools/sections/version_need_section'
require 'elftools/sections/version_section'

module ELFTools
  # Defines different types of sections in this module.
  module Sections
    # Class methods of {Sections::Section}.
    class << Section
      # Use different class according to +header.sh_type+.
      # @param [ELFTools::Structs::ELF_Shdr] header Section header.
      # @param [#pos=, #read] stream Streaming object.
      # @return [ELFTools::Sections::Section]
      #   Return object dependes on +header.sh_type+.
      def create(header, stream, *args, **kwargs)
        klass = case header.sh_type
                when Constants::SHT_DYNAMIC then DynamicSection
                when Constants::SHT_NULL then NullSection
                when Constants::SHT_NOTE then NoteSection
                when Constants::SHT_RELA, Constants::SHT_REL then RelocationSection
                when Constants::SHT_RELR then RelativeRelocationSection
                when Constants::SHT_GNU_versym then VersionSection
                when Constants::SHT_GNU_verneed then VersionNeedSection
                when Constants::SHT_GNU_verdef then VersionDefinitionSection
                when Constants::SHT_STRTAB then StrTabSection
                when Constants::SHT_SYMTAB, Constants::SHT_DYNSYM then SymTabSection
                else Section
                end
        klass.new(header, stream, *args, **kwargs)
      end
    end
  end
end
