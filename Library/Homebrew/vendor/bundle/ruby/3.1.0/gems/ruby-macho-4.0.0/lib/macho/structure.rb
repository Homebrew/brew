# frozen_string_literal: true

module MachO
  # A general purpose pseudo-structure. Described in detail in docs/machostructure-dsl.md.
  # @abstract
  class MachOStructure
    # Constants used for parsing MachOStructure fields
    module Fields
      # 1. All fields with empty strings and zeros aren't used
      #    to calculate the format and sizeof variables.
      # 2. All fields with nil should provide those values manually
      #    via the :size parameter.

      # association of field types to byte size
      # @api private
      BYTE_SIZE = {
        # Binary slices
        :string => nil,
        :null_padded_string => nil,
        :int32 => 4,
        :uint32 => 4,
        :uint64 => 8,
        # Classes
        :view => 0,
        :lcstr => 4,
        :two_level_hints_table => 0,
        :tool_entries => 4,
      }.freeze

      # association of field types with ruby format codes
      # Binary format codes can be found here:
      # https://docs.ruby-lang.org/en/2.6.0/String.html#method-i-unpack
      #
      # The equals sign is used to manually change endianness using
      # the Utils#specialize_format() method.
      # @api private
      FORMAT_CODE = {
        # Binary slices
        :string => "a",
        :null_padded_string => "Z",
        :int32 => "l=",
        :uint32 => "L=",
        :uint64 => "Q=",
        # Classes
        :view => "",
        :lcstr => "L=",
        :two_level_hints_table => "",
        :tool_entries => "L=",
      }.freeze

      # A list of classes that must get initialized
      # To add a new class append it here and add the init method to the def_class_reader method
      # @api private
      CLASSES_TO_INIT = %i[lcstr tool_entries two_level_hints_table].freeze

      # A list of fields that don't require arguments in the initializer
      # Used to calculate MachOStructure#min_args
      # @api private
      NO_ARG_REQUIRED = %i[two_level_hints_table].freeze
    end

    # map of field names to indices
    @field_idxs = {}

    # array of fields sizes
    @size_list = []

    # array of field format codes
    @fmt_list = []

    # minimum number of required arguments
    @min_args = 0

    # @param args [Array[Value]] list of field parameters
    def initialize(*args)
      raise ArgumentError, "Invalid number of arguments" if args.size < self.class.min_args

      @values = args
    end

    # @return [Hash] a hash representation of this {MachOStructure}.
    def to_h
      {
        "structure" => {
          "format" => self.class.format,
          "bytesize" => self.class.bytesize,
        },
      }
    end

    class << self
      attr_reader :min_args

      # @param endianness [Symbol] either `:big` or `:little`
      # @param bin [String] the string to be unpacked into the new structure
      # @return [MachO::MachOStructure] the resulting structure
      # @api private
      def new_from_bin(endianness, bin)
        format = Utils.specialize_format(self.format, endianness)

        new(*bin.unpack(format))
      end

      def format
        @format ||= @fmt_list.join
      end

      def bytesize
        @bytesize ||= @size_list.sum
      end

      private

      # @param subclass [Class] subclass type
      # @api private
      def inherited(subclass) # rubocop:disable Lint/MissingSuper
        # Clone all class instance variables
        field_idxs = @field_idxs.dup
        size_list = @size_list.dup
        fmt_list = @fmt_list.dup
        min_args = @min_args.dup

        # Add those values to the inheriting class
        subclass.class_eval do
          @field_idxs = field_idxs
          @size_list = size_list
          @fmt_list = fmt_list
          @min_args = min_args
        end
      end

      # @param name [Symbol] name of internal field
      # @param type [Symbol] type of field in terms of binary size
      # @param options [Hash] set of additonal options
      # Expected options
      #   :size [Integer] size in bytes
      #   :mask [Integer] bitmask
      #   :unpack [String] string format
      #   :default [Value] default value
      #   :to_s [Boolean] flag for generating #to_s
      #   :endian [Symbol] optionally specify :big or :little endian
      #   :padding [Symbol] optionally specify :null padding
      # @api private
      def field(name, type, **options)
        raise ArgumentError, "Invalid field type #{type}" unless Fields::FORMAT_CODE.key?(type)

        # Get field idx for size_list and fmt_list
        idx = if @field_idxs.key?(name)
          @field_idxs[name]
        else
          @min_args += 1 unless options.key?(:default) || Fields::NO_ARG_REQUIRED.include?(type)
          @field_idxs[name] = @field_idxs.size
          @size_list << nil
          @fmt_list << nil
          @field_idxs.size - 1
        end

        # Update string type if padding is specified
        type = :null_padded_string if type == :string && options[:padding] == :null

        # Add to size_list and fmt_list
        @size_list[idx] = Fields::BYTE_SIZE[type] || options[:size]
        @fmt_list[idx] = if options[:endian]
          Utils.specialize_format(Fields::FORMAT_CODE[type], options[:endian])
        else
          Fields::FORMAT_CODE[type]
        end
        @fmt_list[idx] += options[:size].to_s if options.key?(:size)

        # Generate methods
        if Fields::CLASSES_TO_INIT.include?(type)
          def_class_reader(name, type, idx)
        elsif options.key?(:mask)
          def_mask_reader(name, idx, options[:mask])
        elsif options.key?(:unpack)
          def_unpack_reader(name, idx, options[:unpack])
        elsif options.key?(:default)
          def_default_reader(name, idx, options[:default])
        else
          def_reader(name, idx)
        end

        def_to_s(name) if options[:to_s]
      end

      #
      # Method Generators
      #

      # Generates a reader method for classes that need to be initialized.
      # These classes are defined in the Fields::CLASSES_TO_INIT array.
      # @param name [Symbol] name of internal field
      # @param type [Symbol] type of field in terms of binary size
      # @param idx [Integer] the index of the field value in the @values array
      # @api private
      def def_class_reader(name, type, idx)
        case type
        when :lcstr
          define_method(name) do
            instance_variable_defined?("@#{name}") ||
              instance_variable_set("@#{name}", LoadCommands::LoadCommand::LCStr.new(self, @values[idx]))

            instance_variable_get("@#{name}")
          end
        when :two_level_hints_table
          define_method(name) do
            instance_variable_defined?("@#{name}") ||
              instance_variable_set("@#{name}", LoadCommands::TwolevelHintsCommand::TwolevelHintsTable.new(view, htoffset, nhints))

            instance_variable_get("@#{name}")
          end
        when :tool_entries
          define_method(name) do
            instance_variable_defined?("@#{name}") ||
              instance_variable_set("@#{name}", LoadCommands::BuildVersionCommand::ToolEntries.new(view, @values[idx]))

            instance_variable_get("@#{name}")
          end
        end
      end

      # Generates a reader method for fields that need to be bitmasked.
      # @param name [Symbol] name of internal field
      # @param idx [Integer] the index of the field value in the @values array
      # @param mask [Integer] the bitmask
      # @api private
      def def_mask_reader(name, idx, mask)
        define_method(name) do
          instance_variable_defined?("@#{name}") ||
            instance_variable_set("@#{name}", @values[idx] & ~mask)

          instance_variable_get("@#{name}")
        end
      end

      # Generates a reader method for fields that need further unpacking.
      # @param name [Symbol] name of internal field
      # @param idx [Integer] the index of the field value in the @values array
      # @param unpack [String] the format code used for futher binary unpacking
      # @api private
      def def_unpack_reader(name, idx, unpack)
        define_method(name) do
          instance_variable_defined?("@#{name}") ||
            instance_variable_set("@#{name}", @values[idx].unpack(unpack))

          instance_variable_get("@#{name}")
        end
      end

      # Generates a reader method for fields that have default values.
      # @param name [Symbol] name of internal field
      # @param idx [Integer] the index of the field value in the @values array
      # @param default [Value] the default value
      # @api private
      def def_default_reader(name, idx, default)
        define_method(name) do
          instance_variable_defined?("@#{name}") ||
            instance_variable_set("@#{name}", @values.size > idx ? @values[idx] : default)

          instance_variable_get("@#{name}")
        end
      end

      # Generates an attr_reader like method for a field.
      # @param name [Symbol] name of internal field
      # @param idx [Integer] the index of the field value in the @values array
      # @api private
      def def_reader(name, idx)
        define_method(name) do
          @values[idx]
        end
      end

      # Generates the to_s method based on the named field.
      # @param name [Symbol] name of the field
      # @api private
      def def_to_s(name)
        define_method(:to_s) do
          send(name).to_s
        end
      end
    end
  end
end
