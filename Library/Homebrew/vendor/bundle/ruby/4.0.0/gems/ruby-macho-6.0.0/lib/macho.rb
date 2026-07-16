# frozen_string_literal: true

require_relative "macho/utils"
require_relative "macho/structure"
require_relative "macho/view"
require_relative "macho/headers"
require_relative "macho/code_signing"
require_relative "macho/load_commands"
require_relative "macho/sections"
require_relative "macho/macho_file"
require_relative "macho/fat_file"
require_relative "macho/exceptions"
require_relative "macho/tools"

# The primary namespace for ruby-macho.
module MachO
  # release version
  VERSION = "6.0.0"

  # Opens the given filename as a MachOFile or FatFile, depending on its magic.
  # @param filename [String] the file being opened
  # @return [MachOFile] if the file is a Mach-O
  # @return [FatFile] if the file is a Fat file
  # @raise [ArgumentError] if the given file does not exist
  # @raise [TruncatedFileError] if the file is too small to have a valid header
  # @raise [MagicError] if the file's magic is not valid Mach-O magic
  def self.open(filename)
    raise ArgumentError, "#{filename}: no such file" unless File.file?(filename)
    raise TruncatedFileError unless File.stat(filename).size >= 4

    magic = File.open(filename, "rb") { |f| f.read(4) }.unpack1("N")

    if Utils.fat_magic?(magic)
      file = FatFile.new(filename)
    elsif Utils.magic?(magic)
      file = MachOFile.new(filename)
    else
      raise MagicError, magic
    end

    file
  end

  # Signs a thin or fat Mach-O using an ad-hoc identity.
  # Necessary after changing signed Mach-O data because the signature covers
  # the header, load commands and all bytes preceding the signature.
  # @param filename [String] the file being opened
  # @return [void]
  # @raise [CodeSigningError] if the operation fails
  def self.codesign!(filename)
    raise ArgumentError, "#{filename}: no such file" unless File.file?(filename)

    file = MachO.open(filename)
    file.codesign!
    file.write!
    nil
  rescue MachOError => e
    raise CodeSigningError, "#{filename}: signing failed: #{e.message}"
  end
end
