# encoding: ascii-8bit
# frozen_string_literal: true

require 'elftools/elf_file'

require 'patchelf/exceptions'
require 'patchelf/logger'
require 'patchelf/saver'

module PatchELF
  # Class to handle all patching things.
  class Patcher
    # @!macro [new] note_apply
    #   @note This setting will be saved after {#save} being invoked.

    attr_reader :elf # @return [ELFTools::ELFFile] ELF parser object.

    # Instantiate a {Patcher} object.
    # @param [String] filename
    #   Filename of input ELF.
    # @param [Boolean] logging
    #   *deprecated*: use +on_error+ instead
    # @param [:log, :silent, :exception] on_error
    #   action when the desired segment/tag field isn't present
    #     :log = logs to stderr
    #     :exception = raise exception related to the error
    #     :silent = ignore the errors
    def initialize(filename, on_error: :log, logging: true)
      @in_file = filename
      @elf = ELFTools::ELFFile.new(File.open(filename))
      @set = {}
      @rpath_sym = :runpath
      @on_error = logging ? on_error : :exception

      on_error_syms = %i[exception log silent]
      raise ArgumentError, "on_error must be one of #{on_error_syms}" unless on_error_syms.include?(@on_error)
    end

    # @return [String?]
    #   Get interpreter's name.
    # @example
    #   PatchELF::Patcher.new('/bin/ls').interpreter
    #   #=> "/lib64/ld-linux-x86-64.so.2"
    def interpreter
      @set[:interpreter] || interpreter_
    end

    # Set interpreter's name.
    #
    # If the input ELF has no existent interpreter,
    # this method will show a warning and has no effect.
    # @param [String] interp
    # @macro note_apply
    def interpreter=(interp)
      return if interpreter_.nil? # will also show warning if there's no interp segment.

      @set[:interpreter] = interp
    end

    # Get needed libraries.
    # @return [Array<String>]
    # @example
    #   patcher = PatchELF::Patcher.new('/bin/ls')
    #   patcher.needed
    #   #=> ["libselinux.so.1", "libc.so.6"]
    def needed
      @set[:needed] || needed_
    end

    # Set needed libraries.
    # @param [Array<String>] needs
    # @macro note_apply
    def needed=(needs)
      @set[:needed] = needs
    end

    # Add the needed library.
    # @param [String] need
    # @return [void]
    # @macro note_apply
    def add_needed(need)
      @set[:needed] ||= needed_
      @set[:needed] << need
    end

    # Remove the needed library.
    # @param [String] need
    # @return [void]
    # @macro note_apply
    def remove_needed(need)
      @set[:needed] ||= needed_
      @set[:needed].delete(need)
    end

    # Replace needed library +src+ with +tar+.
    #
    # @param [String] src
    #   Library to be replaced.
    # @param [String] tar
    #   Library replace with.
    # @return [void]
    # @macro note_apply
    def replace_needed(src, tar)
      @set[:needed] ||= needed_
      @set[:needed].map! { |v| v == src ? tar : v }
    end

    # Get the soname of a shared library.
    # @return [String?] The name.
    # @example
    #   patcher = PatchELF::Patcher.new('/bin/ls')
    #   patcher.soname
    #   # [WARN] Entry DT_SONAME not found, not a shared library?
    #   #=> nil
    # @example
    #   PatchELF::Patcher.new('/lib/x86_64-linux-gnu/libc.so.6').soname
    #   #=> "libc.so.6"
    def soname
      @set[:soname] || soname_
    end

    # Set soname.
    #
    # If the input ELF is not a shared library with a soname,
    # this method will show a warning and has no effect.
    # @param [String] name
    # @macro note_apply
    def soname=(name)
      return if soname_.nil?

      @set[:soname] = name
    end

    # Get runpath.
    # @return [String?]
    def runpath
      @set[@rpath_sym] || runpath_(@rpath_sym)
    end

    # Get rpath
    # return [String?]
    def rpath
      @set[:rpath] || runpath_(:rpath)
    end

    # Set rpath
    #
    # Modify / set DT_RPATH of the given ELF.
    # similar to runpath= except DT_RPATH is modifed/created in DYNAMIC segment.
    # @param [String] rpath
    # @macro note_apply
    def rpath=(rpath)
      @set[:rpath] = rpath
    end

    # Set runpath.
    #
    # If DT_RUNPATH is not presented in the input ELF,
    # a new DT_RUNPATH attribute will be inserted into the DYNAMIC segment.
    # @param [String] runpath
    # @macro note_apply
    def runpath=(runpath)
      @set[@rpath_sym] = runpath
    end

    # Set all operations related to DT_RUNPATH to use DT_RPATH.
    # @return [self]
    def use_rpath!
      @rpath_sym = :rpath
      self
    end

    # Save the patched ELF as +out_file+.
    # @param [String?] out_file
    #   If +out_file+ is +nil+, the original input file will be modified.
    # @param [Boolean] patchelf_compatible
    #   When +patchelf_compatible+ is true, tries to produce same ELF as the one produced by NixOS/patchelf.
    # @return [void]
    def save(out_file = nil, patchelf_compatible: false)
      # If nothing is modified, return directly.
      return if out_file.nil? && !dirty?

      out_file ||= @in_file
      saver = if patchelf_compatible
                require 'patchelf/alt_saver'
                PatchELF::AltSaver.new(@in_file, out_file, @set)
              else
                PatchELF::Saver.new(@in_file, out_file, @set)
              end

      saver.save!
    end

    private

    def log_or_raise(msg, exception = PatchELF::PatchError)
      raise exception, msg if @on_error == :exception

      PatchELF::Logger.warn(msg) if @on_error == :log
    end

    def interpreter_
      segment = @elf.segment_by_type(:interp)
      return log_or_raise 'No interpreter found.', PatchELF::MissingSegmentError if segment.nil?

      segment.interp_name
    end

    # @return [Array<String>]
    def needed_
      segment = dynamic_or_log
      return if segment.nil?

      segment.tags_by_type(:needed).map(&:name)
    end

    # @return [String?]
    def runpath_(rpath_sym = :runpath)
      tag_name_or_log(rpath_sym, "Entry DT_#{rpath_sym.to_s.upcase} not found.")
    end

    # @return [String?]
    def soname_
      tag_name_or_log(:soname, 'Entry DT_SONAME not found, not a shared library?')
    end

    # @return [Boolean]
    def dirty?
      @set.any?
    end

    def tag_name_or_log(type, log_msg)
      segment = dynamic_or_log
      return if segment.nil?

      tag = segment.tag_by_type(type)
      return log_or_raise log_msg, PatchELF::MissingTagError if tag.nil?

      tag.name
    end

    def dynamic_or_log
      @elf.segment_by_type(:dynamic).tap do |s|
        if s.nil?
          log_or_raise 'DYNAMIC segment not found, might be a statically-linked ELF?', PatchELF::MissingSegmentError
        end
      end
    end
  end
end
