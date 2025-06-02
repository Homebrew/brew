require 'fiddle'
require 'fiddle/pack'
require_relative 'c_pointer'

module RubyVM::RJIT
  module CType
    module Struct
      # @param name [String]
      # @param members [Hash{ Symbol => [Integer, RubyVM::RJIT::CType::*] }]
      def self.new(name, sizeof, **members)
        name = members.keys.join('_') if name.empty?
        CPointer.with_class_name('Struct', name) do
          CPointer::Struct.define(sizeof, members)
        end
      end
    end

    module Union
      # @param name [String]
      # @param members [Hash{ Symbol => RubyVM::RJIT::CType::* }]
      def self.new(name, sizeof, **members)
        name = members.keys.join('_') if name.empty?
        CPointer.with_class_name('Union', name) do
          CPointer::Union.define(sizeof, members)
        end
      end
    end

    module Immediate
      # @param fiddle_type [Integer]
      def self.new(fiddle_type)
        name = Fiddle.constants.find do |const|
          const.start_with?('TYPE_') && Fiddle.const_get(const) == fiddle_type.abs
        end&.to_s
        name.delete_prefix!('TYPE_')
        if fiddle_type.negative?
          name.prepend('U')
        end
        CPointer.with_class_name('Immediate', name, cache: true) do
          CPointer::Immediate.define(fiddle_type)
        end
      end

      # @param type [String]
      def self.parse(ctype)
        new(Fiddle::Importer.parse_ctype(ctype))
      end

      def self.find(size, signed)
        fiddle_type = TYPE_MAP.fetch(size)
        fiddle_type = -fiddle_type unless signed
        new(fiddle_type)
      end

      TYPE_MAP = Fiddle::PackInfo::SIZE_MAP.map { |type, size| [size, type.abs] }.to_h
      private_constant :TYPE_MAP
    end

    module Bool
      def self.new
        CPointer::Bool
      end
    end

    class Array
      def self.new(&block)
        CPointer.with_class_name('Array', block.object_id.to_s) do
          CPointer::Array.define(block)
        end
      end
    end

    class Pointer
      # This takes a block to avoid "stack level too deep" on a cyclic reference
      # @param block [Proc]
      def self.new(&block)
        CPointer.with_class_name('Pointer', block.object_id.to_s) do
          CPointer::Pointer.define(block)
        end
      end
    end

    module BitField
      # @param width [Integer]
      # @param offset [Integer]
      def self.new(width, offset)
        CPointer.with_class_name('BitField', "#{offset}_#{width}") do
          CPointer::BitField.define(width, offset)
        end
      end
    end

    # Types that are referenced but not part of code generation targets
    Stub = ::Struct.new(:name)

    # Types that it failed to figure out from the header
    Unknown = Module.new
  end
end
