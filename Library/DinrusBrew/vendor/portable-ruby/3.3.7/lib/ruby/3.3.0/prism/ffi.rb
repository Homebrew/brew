# frozen_string_literal: true

# This file is responsible for mirroring the API provided by the C extension by
# using FFI to call into the shared library.

require "rbconfig"
require "ffi"

module Prism
  BACKEND = :FFI

  module LibRubyParser # :nodoc:
    extend FFI::Library

    # Define the library that we will be pulling functions from. Note that this
    # must align with the build shared library from make/rake.
    ffi_lib File.expand_path("../../build/libprism.#{RbConfig::CONFIG["SOEXT"]}", __dir__)

    # Convert a native C type declaration into a symbol that FFI understands.
    # For example:
    #
    #     const char * -> :pointer
    #     bool         -> :bool
    #     size_t       -> :size_t
    #     void         -> :void
    #
    def self.resolve_type(type)
      type = type.strip
      type.end_with?("*") ? :pointer : type.delete_prefix("const ").to_sym
    end

    # Read through the given header file and find the declaration of each of the
    # given functions. For each one, define a function with the same name and
    # signature as the C function.
    def self.load_exported_functions_from(header, *functions)
      File.foreach(File.expand_path("../../include/#{header}", __dir__)) do |line|
        # We only want to attempt to load exported functions.
        next unless line.start_with?("PRISM_EXPORTED_FUNCTION ")

        # We only want to load the functions that we are interested in.
        next unless functions.any? { |function| line.include?(function) }

        # Parse the function declaration.
        unless /^PRISM_EXPORTED_FUNCTION (?<return_type>.+) (?<name>\w+)\((?<arg_types>.+)\);$/ =~ line
          raise "Could not parse #{line}"
        end

        # Delete the function from the list of functions we are looking for to
        # mark it as having been found.
        functions.delete(name)

        # Split up the argument types into an array, ensure we handle the case
        # where there are no arguments (by explicit void).
        arg_types = arg_types.split(",").map(&:strip)
        arg_types = [] if arg_types == %w[void]

        # Resolve the type of the argument by dropping the name of the argument
        # first if it is present.
        arg_types.map! { |type| resolve_type(type.sub(/\w+$/, "")) }

        # Attach the function using the FFI library.
        attach_function name, arg_types, resolve_type(return_type)
      end

      # If we didn't find all of the functions, raise an error.
      raise "Could not find functions #{functions.inspect}" unless functions.empty?
    end

    load_exported_functions_from(
      "prism.h",
      "pm_version",
      "pm_serialize_parse",
      "pm_serialize_parse_comments",
      "pm_serialize_lex",
      "pm_serialize_parse_lex",
      "pm_parse_success_p"
    )

    load_exported_functions_from(
      "prism/util/pm_buffer.h",
      "pm_buffer_sizeof",
      "pm_buffer_init",
      "pm_buffer_value",
      "pm_buffer_length",
      "pm_buffer_free"
    )

    load_exported_functions_from(
      "prism/util/pm_string.h",
      "pm_string_mapped_init",
      "pm_string_free",
      "pm_string_source",
      "pm_string_length",
      "pm_string_sizeof"
    )

    # This object represents a pm_buffer_t. We only use it as an opaque pointer,
    # so it doesn't need to know the fields of pm_buffer_t.
    class PrismBuffer # :nodoc:
      SIZEOF = LibRubyParser.pm_buffer_sizeof

      attr_reader :pointer

      def initialize(pointer)
        @pointer = pointer
      end

      def value
        LibRubyParser.pm_buffer_value(pointer)
      end

      def length
        LibRubyParser.pm_buffer_length(pointer)
      end

      def read
        value.read_string(length)
      end

      # Initialize a new buffer and yield it to the block. The buffer will be
      # automatically freed when the block returns.
      def self.with(&block)
        pointer = FFI::MemoryPointer.new(SIZEOF)

        begin
          raise unless LibRubyParser.pm_buffer_init(pointer)
          yield new(pointer)
        ensure
          LibRubyParser.pm_buffer_free(pointer)
          pointer.free
        end
      end
    end

    # This object represents a pm_string_t. We only use it as an opaque pointer,
    # so it doesn't have to be an FFI::Struct.
    class PrismString # :nodoc:
      SIZEOF = LibRubyParser.pm_string_sizeof

      attr_reader :pointer

      def initialize(pointer)
        @pointer = pointer
      end

      def source
        LibRubyParser.pm_string_source(pointer)
      end

      def length
        LibRubyParser.pm_string_length(pointer)
      end

      def read
        source.read_string(length)
      end

      # Yields a pm_string_t pointer to the given block.
      def self.with(filepath, &block)
        pointer = FFI::MemoryPointer.new(SIZEOF)

        begin
          raise unless LibRubyParser.pm_string_mapped_init(pointer, filepath)
          yield new(pointer)
        ensure
          LibRubyParser.pm_string_free(pointer)
          pointer.free
        end
      end
    end
  end

  # Mark the LibRubyParser module as private as it should only be called through
  # the prism module.
  private_constant :LibRubyParser

  # The version constant is set by reading the result of calling pm_version.
  VERSION = LibRubyParser.pm_version.read_string

  class << self
    # Mirror the Prism.dump API by using the serialization API.
    def dump(code, **options)
      LibRubyParser::PrismBuffer.with do |buffer|
        LibRubyParser.pm_serialize_parse(buffer.pointer, code, code.bytesize, dump_options(options))
        buffer.read
      end
    end

    # Mirror the Prism.dump_file API by using the serialization API.
    def dump_file(filepath, **options)
      LibRubyParser::PrismString.with(filepath) do |string|
        dump(string.read, **options, filepath: filepath)
      end
    end

    # Mirror the Prism.lex API by using the serialization API.
    def lex(code, **options)
      LibRubyParser::PrismBuffer.with do |buffer|
        LibRubyParser.pm_serialize_lex(buffer.pointer, code, code.bytesize, dump_options(options))
        Serialize.load_tokens(Source.new(code), buffer.read)
      end
    end

    # Mirror the Prism.lex_file API by using the serialization API.
    def lex_file(filepath, **options)
      LibRubyParser::PrismString.with(filepath) do |string|
        lex(string.read, **options, filepath: filepath)
      end
    end

    # Mirror the Prism.parse API by using the serialization API.
    def parse(code, **options)
      Prism.load(code, dump(code, **options))
    end

    # Mirror the Prism.parse_file API by using the serialization API. This uses
    # native strings instead of Ruby strings because it allows us to use mmap when
    # it is available.
    def parse_file(filepath, **options)
      LibRubyParser::PrismString.with(filepath) do |string|
        parse(string.read, **options, filepath: filepath)
      end
    end

    # Mirror the Prism.parse_comments API by using the serialization API.
    def parse_comments(code, **options)
      LibRubyParser::PrismBuffer.with do |buffer|
        LibRubyParser.pm_serialize_parse_comments(buffer.pointer, code, code.bytesize, dump_options(options))

        source = Source.new(code)
        loader = Serialize::Loader.new(source, buffer.read)

        loader.load_header
        loader.load_encoding
        loader.load_start_line
        loader.load_comments
      end
    end

    # Mirror the Prism.parse_file_comments API by using the serialization
    # API. This uses native strings instead of Ruby strings because it allows us
    # to use mmap when it is available.
    def parse_file_comments(filepath, **options)
      LibRubyParser::PrismString.with(filepath) do |string|
        parse_comments(string.read, **options, filepath: filepath)
      end
    end

    # Mirror the Prism.parse_lex API by using the serialization API.
    def parse_lex(code, **options)
      LibRubyParser::PrismBuffer.with do |buffer|
        LibRubyParser.pm_serialize_parse_lex(buffer.pointer, code, code.bytesize, dump_options(options))

        source = Source.new(code)
        loader = Serialize::Loader.new(source, buffer.read)

        tokens = loader.load_tokens
        node, comments, magic_comments, data_loc, errors, warnings = loader.load_nodes
        tokens.each { |token,| token.value.force_encoding(loader.encoding) }

        ParseResult.new([node, tokens], comments, magic_comments, data_loc, errors, warnings, source)
      end
    end

    # Mirror the Prism.parse_lex_file API by using the serialization API.
    def parse_lex_file(filepath, **options)
      LibRubyParser::PrismString.with(filepath) do |string|
        parse_lex(string.read, **options, filepath: filepath)
      end
    end

    # Mirror the Prism.parse_success? API by using the serialization API.
    def parse_success?(code, **options)
      LibRubyParser.pm_parse_success_p(code, code.bytesize, dump_options(options))
    end

    # Mirror the Prism.parse_file_success? API by using the serialization API.
    def parse_file_success?(filepath, **options)
      LibRubyParser::PrismString.with(filepath) do |string|
        parse_success?(string.read, **options, filepath: filepath)
      end
    end

    private

    # Convert the given options into a serialized options string.
    def dump_options(options)
      template = +""
      values = []

      template << "L"
      if (filepath = options[:filepath])
        values.push(filepath.bytesize, filepath.b)
        template << "A*"
      else
        values << 0
      end

      template << "L"
      values << options.fetch(:line, 1)

      template << "L"
      if (encoding = options[:encoding])
        name = encoding.name
        values.push(name.bytesize, name.b)
        template << "A*"
      else
        values << 0
      end

      template << "C"
      values << (options.fetch(:frozen_string_literal, false) ? 1 : 0)

      template << "C"
      values << (options.fetch(:verbose, true) ? 0 : 1)

      template << "L"
      if (scopes = options[:scopes])
        values << scopes.length

        scopes.each do |scope|
          template << "L"
          values << scope.length

          scope.each do |local|
            name = local.name
            template << "L"
            values << name.bytesize

            template << "A*"
            values << name.b
          end
        end
      else
        values << 0
      end

      values.pack(template)
    end
  end
end
