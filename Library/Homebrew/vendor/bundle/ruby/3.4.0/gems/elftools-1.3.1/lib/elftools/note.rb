# frozen_string_literal: true

require 'elftools/structs'
require 'elftools/util'

module ELFTools
  # Since both note sections and note segments refer to notes, this module
  # defines common methods for {ELFTools::Sections::NoteSection} and
  # {ELFTools::Segments::NoteSegment}.
  #
  # @note
  #   This module can only be included in {ELFTools::Sections::NoteSection} and
  #   {ELFTools::Segments::NoteSegment} since some methods here assume some
  #   attributes already exist.
  module Note
    # Since size of {ELFTools::Structs::ELF_Nhdr} will not change no matter in
    # what endian and what arch, we can do this here. This value should equal
    # to 12.
    SIZE_OF_NHDR = Structs::ELF_Nhdr.new(endian: :little).num_bytes

    # Iterate all notes in a note section or segment.
    #
    # Structure of notes are:
    #   +---------------+
    #   | Note 1 header |
    #   +---------------+
    #   |  Note 1 name  |
    #   +---------------+
    #   |  Note 1 desc  |
    #   +---------------+
    #   | Note 2 header |
    #   +---------------+
    #   |      ...      |
    #   +---------------+
    #
    # @note
    #   This method assume following methods exist:
    #     stream
    #     note_start
    #     note_total_size
    # @return [Enumerator<ELFTools::Note::Note>, Array<ELFTools::Note::Note>]
    #   If block is not given, an enumerator will be returned.
    #   Otherwise, return the array of notes.
    def each_notes
      return enum_for(:each_notes) unless block_given?

      @notes_offset_map ||= {}
      cur = note_start
      notes = []
      while cur < note_start + note_total_size
        stream.pos = cur
        @notes_offset_map[cur] ||= create_note(cur)
        note = @notes_offset_map[cur]
        # name and desc size needs to be 4-bytes align
        name_size = Util.align(note.header.n_namesz, 2)
        desc_size = Util.align(note.header.n_descsz, 2)
        cur += SIZE_OF_NHDR + name_size + desc_size
        notes << note
        yield note
      end
      notes
    end

    # Simply +#notes+ to get all notes.
    # @return [Array<ELFTools::Note::Note>]
    #   Whole notes.
    def notes
      each_notes.to_a
    end

    private

    # Get the endian.
    #
    # @note This method assume method +header+ exists.
    # @return [Symbol] +:little+ or +:big+.
    def endian
      header.class.self_endian
    end

    def create_note(cur)
      nhdr = Structs::ELF_Nhdr.new(endian:, offset: stream.pos).read(stream)
      ELFTools::Note::Note.new(nhdr, stream, cur)
    end

    # Class of a note.
    class Note
      attr_reader :header # @return [ELFTools::Structs::ELF_Nhdr] Note header.
      attr_reader :stream # @return [#pos=, #read] Streaming object.
      attr_reader :offset # @return [Integer] Address of this note start, includes note header.

      # Instantiate a {ELFTools::Note::Note} object.
      # @param [ELF_Nhdr] header The note header.
      # @param [#pos=, #read] stream Streaming object.
      # @param [Integer] offset
      #   Start address of this note, includes the header.
      def initialize(header, stream, offset)
        @header = header
        @stream = stream
        @offset = offset
      end

      # Name of this note.
      # @return [String] The name.
      def name
        return @name if defined?(@name)

        stream.pos = @offset + SIZE_OF_NHDR
        @name = stream.read(header.n_namesz)[0..-2]
      end

      # Description of this note.
      # @return [String] The description.
      def desc
        return @desc if instance_variable_defined?(:@desc)

        stream.pos = @offset + SIZE_OF_NHDR + Util.align(header.n_namesz, 2)
        @desc = stream.read(header.n_descsz)
      end

      # If someone likes to use full name.
      alias description desc
    end
  end
end
