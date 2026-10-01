# frozen_string_literal: true

require 'optparse'

require 'patchelf/patcher'
require 'patchelf/version'

module PatchELF
  # For command line interface to parsing arguments.
  module CLI
    # Name of binary.
    SCRIPT_NAME = 'patchelf.rb'
    # CLI usage string.
    USAGE = format('Usage: %s [OPTIONS] INPUT_FILE [OUTPUT_FILE]', SCRIPT_NAME).freeze

    module_function

    # Main method of CLI.
    # @param [Array<String>] argv
    #   Command line arguments.
    # @return [Integer] Process exit status: zero on success, non-zero on usage or input errors.
    # @example
    #   PatchELF::CLI.work(%w[--help])
    #   # usage message to stdout
    #   PatchELF::CLI.work(%w[--version])
    #   # version message to stdout
    def work(argv)
      @options = {
        set: {},
        print: [],
        needed: []
      }
      unless parse?(argv)
        $stdout.puts option_parser
        return 1
      end

      case @options[:action]
      when :version
        $stdout.puts "PatchELF Version #{PatchELF::VERSION}"
        return 0
      when :help
        $stdout.puts option_parser
        return 0
      end

      # Now the options are (hopefully) valid, let's process the ELF file.
      @patcher = PatchELF::Patcher.new(@options[:in_file])
      patcher.use_rpath! if @options[:force_rpath]
      readonly
      patch_requests
      patcher.save(@options[:out_file])
      0
    rescue OptionParser::ParseError, ELFTools::ELFError, SystemCallError, NotImplementedError => e
      PatchELF::Logger.error(e.message)
      1
    end

    private

    # @return [PatchELF::Patcher]
    def patcher
      @patcher
    end

    # Print the requested ELF metadata.
    # @return [void]
    def readonly
      @options[:print].uniq.each do |s|
        content = patcher.__send__(s)
        next if content.nil?

        s = :rpath if @options[:force_rpath] && s == :runpath
        $stdout.puts "#{s}: #{Array(content).join(' ')}"
      end
    end

    # Apply all requested ELF mutations to the patcher.
    # @return [void]
    def patch_requests
      @options[:set].each do |sym, val|
        patcher.__send__(:"#{sym}=", val)
      end

      @options[:needed].each do |type, val|
        patcher.__send__(:"#{type}_needed", *val)
      end
    end

    # Parse options and capture the input and optional output paths.
    # @param [Array<String>] argv
    # @return [Boolean]
    def parse?(argv)
      remain = option_parser.permute(argv)
      return true if @options[:action]
      return false if remain.first.nil?
      raise OptionParser::InvalidArgument, 'too many positional arguments' if remain.length > 2

      @options[:in_file] = remain.first
      @options[:out_file] = remain[1] # can be nil
      true
    end

    # @return [OptionParser]
    def option_parser
      @option_parser ||= OptionParser.new do |opts|
        opts.banner = USAGE

        opts.on('--print-interpreter', '--pi', 'Show interpreter\'s name.') do
          @options[:print] << :interpreter
        end

        opts.on('--print-needed', '--pn', 'Show needed libraries specified in DT_NEEDED.') do
          @options[:print] << :needed
        end

        opts.on('--print-runpath', '--pr', 'Show the path specified in DT_RUNPATH.') do
          @options[:print] << :runpath
        end

        opts.on('--print-soname', '--ps', 'Show soname specified in DT_SONAME.') do
          @options[:print] << :soname
        end

        opts.on('--set-interpreter INTERP', '--interp INTERP', 'Set interpreter\'s name.') do |interp|
          @options[:set][:interpreter] = interp
        end

        opts.on('--set-needed LIB1,LIB2,LIB3', '--needed LIB1,LIB2,LIB3', Array,
                'Set needed libraries, this will remove all existent needed libraries.') do |needs|
          @options[:set][:needed] = needs
        end

        opts.on('--add-needed LIB', 'Append a new needed library.') do |lib|
          @options[:needed] << [:add, lib]
        end

        opts.on('--remove-needed LIB', 'Remove a needed library.') do |lib|
          @options[:needed] << [:remove, lib]
        end

        opts.on('--replace-needed LIB1,LIB2', Array, 'Replace needed library LIB1 as LIB2.') do |libs|
          @options[:needed] << [:replace, libs]
        end

        opts.on('--set-runpath PATH', '--runpath PATH', 'Set the path of runpath.') do |path|
          @options[:set][:runpath] = path
        end

        opts.on(
          '--force-rpath',
          'According to the ld.so docs, DT_RPATH is obsolete,',
          "#{SCRIPT_NAME} will always try to get/set DT_RUNPATH first.",
          'Use this option to force every operations related to runpath (e.g. --runpath)',
          'to consider \'DT_RPATH\' instead of \'DT_RUNPATH\'.'
        ) do
          @options[:force_rpath] = true
        end

        opts.on('--set-soname SONAME', '--so SONAME', 'Set name of a shared library.') do |soname|
          @options[:set][:soname] = soname
        end

        opts.on('-h', '--help', 'Show this help.') do
          @options[:action] = :help
        end

        opts.on('--version', 'Show current gem\'s version.') do
          @options[:action] = :version
        end
      end
    end

    extend self
  end
end
