# frozen_string_literal: true

require_relative "visitor"

module Gem::SafeMarshal
  module Visitors
    class ToRuby < Visitor
      def initialize(permitted_classes:, permitted_symbols:, permitted_ivars:)
        @permitted_classes = permitted_classes
        @permitted_symbols = ["E"].concat(permitted_symbols).concat(permitted_classes)
        @permitted_ivars = permitted_ivars

        @objects = []
        @symbols = []
        @class_cache = {}

        @stack = ["root"]
        @stack_idx = 1
      end

      def inspect # :nodoc:
        format("#<%s permitted_classes: %p permitted_symbols: %p permitted_ivars: %p>",
          self.class, @permitted_classes, @permitted_symbols, @permitted_ivars)
      end

      def visit(target)
        stack_idx = @stack_idx
        super
      ensure
        @stack_idx = stack_idx - 1
      end

      private

      def push_stack(element)
        @stack[@stack_idx] = element
        @stack_idx += 1
      end

      def visit_Gem_SafeMarshal_Elements_Array(a)
        array = register_object([])

        elements = a.elements
        size = elements.size
        idx = 0
        # not idiomatic, but there's a huge number of IMEMOs allocated here, so we avoid the block
        # because this is such a hot path when doing a bundle install with the full index
        until idx == size
          push_stack idx
          array << visit(elements[idx])
          idx += 1
        end

        array
      end

      def visit_Gem_SafeMarshal_Elements_Symbol(s)
        name = s.name
        raise UnpermittedSymbolError.new(symbol: name, stack: formatted_stack) unless @permitted_symbols.include?(name)
        visit_symbol_type(s)
      end

      def map_ivars(klass, ivars)
        stack_idx = @stack_idx
        ivars.map.with_index do |(k, v), i|
          @stack_idx = stack_idx

          push_stack "ivar_"
          push_stack i
          k = resolve_ivar(klass, k)

          @stack_idx = stack_idx
          push_stack k

          next k, visit(v)
        end
      end

      def visit_Gem_SafeMarshal_Elements_WithIvars(e)
        object_offset = @objects.size
        push_stack "object"
        object = visit(e.object)
        ivars = map_ivars(object.class, e.ivars)

        case e.object
        when Elements::UserDefined
          if object.class == ::Time
            internal = []

            ivars.reject! do |k, v|
              case k
              when :offset, :zone, :nano_num, :nano_den, :submicro
                internal << [k, v]
                true
              else
                false
              end
            end

            s = e.object.binary_string

            marshal_string = "\x04\bIu:\tTime".b
            marshal_string.concat(s.size + 5)
            marshal_string << s
            marshal_string.concat(internal.size + 5)

            internal.each do |k, v|
              marshal_string.concat(":")
              marshal_string.concat(k.size + 5)
              marshal_string.concat(k.to_s)
              dumped = Marshal.dump(v)
              dumped[0, 2] = ""
              marshal_string.concat(dumped)
            end

            object = @objects[object_offset] = Marshal.load(marshal_string)
          end
        when Elements::String
          enc = nil

          ivars.reject! do |k, v|
            case k
            when :E
              case v
              when TrueClass
                enc = "UTF-8"
              when FalseClass
                enc = "US-ASCII"
              else
                raise FormatError, "Unexpected value for String :E #{v.inspect}"
              end
            when :encoding
              enc = v
            else
              next false
            end
            true
          end

          object.force_encoding(enc) if enc
        end

        ivars.each do |k, v|
          object.instance_variable_set k, v
        end
        object
      end

      def visit_Gem_SafeMarshal_Elements_Hash(o)
        hash = register_object({})

        o.pairs.each_with_index do |(k, v), i|
          push_stack i
          k = visit(k)
          push_stack k
          hash[k] = visit(v)
        end

        hash
      end

      def visit_Gem_SafeMarshal_Elements_HashWithDefaultValue(o)
        hash = visit_Gem_SafeMarshal_Elements_Hash(o)
        push_stack :default
        hash.default = visit(o.default)
        hash
      end

      def visit_Gem_SafeMarshal_Elements_Object(o)
        register_object(resolve_class(o.name).allocate)
      end

      def visit_Gem_SafeMarshal_Elements_ObjectLink(o)
        @objects[o.offset]
      end

      def visit_Gem_SafeMarshal_Elements_SymbolLink(o)
        @symbols[o.offset]
      end

      def visit_Gem_SafeMarshal_Elements_UserDefined(o)
        register_object(call_method(resolve_class(o.name), :_load, o.binary_string))
      end

      def visit_Gem_SafeMarshal_Elements_UserMarshal(o)
        klass = resolve_class(o.name)
        compat = COMPAT_CLASSES.fetch(klass, nil)
        idx = @objects.size
        object = register_object(call_method(compat || klass, :allocate))

        push_stack :data
        ret = call_method(object, :marshal_load, visit(o.data))

        if compat
          object = @objects[idx] = ret
        end

        object
      end

      def visit_Gem_SafeMarshal_Elements_Integer(i)
        i.int
      end

      def visit_Gem_SafeMarshal_Elements_Nil(_)
        nil
      end

      def visit_Gem_SafeMarshal_Elements_True(_)
        true
      end

      def visit_Gem_SafeMarshal_Elements_False(_)
        false
      end

      def visit_Gem_SafeMarshal_Elements_String(s)
        register_object(+s.str)
      end

      def visit_Gem_SafeMarshal_Elements_Float(f)
        case f.string
        when "inf"
          ::Float::INFINITY
        when "-inf"
          -::Float::INFINITY
        when "nan"
          ::Float::NAN
        else
          f.string.to_f
        end
      end

      def visit_Gem_SafeMarshal_Elements_Bignum(b)
        result = 0
        b.data.each_byte.with_index do |byte, exp|
          result += (byte * 2**(exp * 8))
        end

        case b.sign
        when 43 # ?+
          result
        when 45 # ?-
          -result
        else
          raise FormatError, "Unexpected sign for Bignum #{b.sign.chr.inspect} (#{b.sign})"
        end
      end

      def visit_Gem_SafeMarshal_Elements_UserClass(r)
        if resolve_class(r.name) == ::Hash && r.wrapped_object.is_a?(Elements::Hash)

          hash = register_object({}.compare_by_identity)

          o = r.wrapped_object
          o.pairs.each_with_index do |(k, v), i|
            push_stack i
            k = visit(k)
            push_stack k
            hash[k] = visit(v)
          end

          if o.is_a?(Elements::HashWithDefaultValue)
            push_stack :default
            hash.default = visit(o.default)
          end

          hash
        else
          raise UnsupportedError.new("Unsupported user class #{resolve_class(r.name)} in marshal stream", stack: formatted_stack)
        end
      end

      def resolve_class(n)
        @class_cache[n] ||= begin
          to_s = resolve_symbol_name(n)
          raise UnpermittedClassError.new(name: to_s, stack: formatted_stack) unless @permitted_classes.include?(to_s)
          visit_symbol_type(n)
          begin
            ::Object.const_get(to_s)
          rescue NameError
            raise ArgumentError, "Undefined class #{to_s.inspect}"
          end
        end
      end

      class RationalCompat
        def marshal_load(s)
          num, den = s
          raise ArgumentError, "Expected 2 ints" unless s.size == 2 && num.is_a?(Integer) && den.is_a?(Integer)
          Rational(num, den)
        end
      end
      private_constant :RationalCompat

      COMPAT_CLASSES = {}.tap do |h|
        h[Rational] = RationalCompat
      end.compare_by_identity.freeze
      private_constant :COMPAT_CLASSES

      def resolve_ivar(klass, name)
        to_s = resolve_symbol_name(name)

        raise UnpermittedIvarError.new(symbol: to_s, klass: klass, stack: formatted_stack) unless @permitted_ivars.fetch(klass.name, [].freeze).include?(to_s)

        visit_symbol_type(name)
      end

      def visit_symbol_type(element)
        case element
        when Elements::Symbol
          sym = element.name.to_sym
          @symbols << sym
          sym
        when Elements::SymbolLink
          visit_Gem_SafeMarshal_Elements_SymbolLink(element)
        end
      end

      # This is a hot method, so avoid respond_to? checks on every invocation
      if :read.respond_to?(:name)
        def resolve_symbol_name(element)
          case element
          when Elements::Symbol
            element.name
          when Elements::SymbolLink
            visit_Gem_SafeMarshal_Elements_SymbolLink(element).name
          else
            raise FormatError, "Expected symbol or symbol link, got #{element.inspect} @ #{formatted_stack.join(".")}"
          end
        end
      else
        def resolve_symbol_name(element)
          case element
          when Elements::Symbol
            element.name
          when Elements::SymbolLink
            visit_Gem_SafeMarshal_Elements_SymbolLink(element).to_s
          else
            raise FormatError, "Expected symbol or symbol link, got #{element.inspect} @ #{formatted_stack.join(".")}"
          end
        end
      end

      def register_object(o)
        @objects << o
        o
      end

      def call_method(receiver, method, *args)
        receiver.__send__(method, *args)
      rescue NoMethodError => e
        raise unless e.receiver == receiver

        raise MethodCallError, "Unable to call #{method.inspect} on #{receiver.inspect}, perhaps it is a class using marshal compat, which is not visible in ruby? #{e}"
      end

      def formatted_stack
        formatted = []
        @stack[0, @stack_idx].each do |e|
          if e.is_a?(Integer)
            if formatted.last == "ivar_"
              formatted[-1] = "ivar_#{e}"
            else
              formatted << "[#{e}]"
            end
          else
            formatted << e
          end
        end
        formatted
      end

      class Error < StandardError
      end

      class UnpermittedSymbolError < Error
        def initialize(symbol:, stack:)
          @symbol = symbol
          @stack = stack
          super "Attempting to load unpermitted symbol #{symbol.inspect} @ #{stack.join "."}"
        end
      end

      class UnpermittedIvarError < Error
        def initialize(symbol:, klass:, stack:)
          @symbol = symbol
          @klass = klass
          @stack = stack
          super "Attempting to set unpermitted ivar #{symbol.inspect} on object of class #{klass} @ #{stack.join "."}"
        end
      end

      class UnpermittedClassError < Error
        def initialize(name:, stack:)
          @name = name
          @stack = stack
          super "Attempting to load unpermitted class #{name.inspect} @ #{stack.join "."}"
        end
      end

      class UnsupportedError < Error
        def initialize(message, stack:)
          super "#{message} @ #{stack.join "."}"
        end
      end

      class FormatError < Error
      end

      class MethodCallError < Error
      end
    end
  end
end
