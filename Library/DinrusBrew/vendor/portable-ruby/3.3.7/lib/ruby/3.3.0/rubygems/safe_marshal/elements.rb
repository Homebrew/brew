# frozen_string_literal: true

module Gem
  module SafeMarshal
    module Elements
      class Element
      end

      class Symbol < Element
        def initialize(name)
          @name = name
        end
        attr_reader :name
      end

      class UserDefined < Element
        def initialize(name, binary_string)
          @name = name
          @binary_string = binary_string
        end

        attr_reader :name, :binary_string
      end

      class UserMarshal < Element
        def initialize(name, data)
          @name = name
          @data = data
        end

        attr_reader :name, :data
      end

      class String < Element
        def initialize(str)
          @str = str
        end

        attr_reader :str
      end

      class Hash < Element
        def initialize(pairs)
          @pairs = pairs
        end

        attr_reader :pairs
      end

      class HashWithDefaultValue < Hash
        def initialize(pairs, default)
          super(pairs)
          @default = default
        end

        attr_reader :default
      end

      class Array < Element
        def initialize(elements)
          @elements = elements
        end

        attr_reader :elements
      end

      class Integer < Element
        def initialize(int)
          @int = int
        end

        attr_reader :int
      end

      class True < Element
        def initialize
        end
        TRUE = new.freeze
      end

      class False < Element
        def initialize
        end

        FALSE = new.freeze
      end

      class WithIvars < Element
        def initialize(object, ivars)
          @object = object
          @ivars = ivars
        end

        attr_reader :object, :ivars
      end

      class Object < Element
        def initialize(name)
          @name = name
        end
        attr_reader :name
      end

      class Nil < Element
        NIL = new.freeze
      end

      class ObjectLink < Element
        def initialize(offset)
          @offset = offset
        end
        attr_reader :offset
      end

      class SymbolLink < Element
        def initialize(offset)
          @offset = offset
        end
        attr_reader :offset
      end

      class Float < Element
        def initialize(string)
          @string = string
        end
        attr_reader :string
      end

      class Bignum < Element # rubocop:disable Lint/UnifiedInteger
        def initialize(sign, data)
          @sign = sign
          @data = data
        end
        attr_reader :sign, :data
      end

      class UserClass < Element
        def initialize(name, wrapped_object)
          @name = name
          @wrapped_object = wrapped_object
        end
        attr_reader :name, :wrapped_object
      end
    end
  end
end
