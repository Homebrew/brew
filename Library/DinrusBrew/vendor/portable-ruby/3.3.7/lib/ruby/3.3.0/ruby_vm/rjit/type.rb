module RubyVM::RJIT
  # Represent the type of a value (local/stack/self) in RJIT
  Type = Data.define(:type) do
    # Check if the type is an immediate
    def imm?
      case self
      in Type::UnknownImm then true
      in Type::Nil then true
      in Type::True then true
      in Type::False then true
      in Type::Fixnum then true
      in Type::Flonum then true
      in Type::ImmSymbol then true
      else false
      end
    end

    # Returns true when the type is not specific.
    def unknown?
      case self
      in Type::Unknown | Type::UnknownImm | Type::UnknownHeap then true
      else false
      end
    end

    # Returns true when we know the VALUE is a specific handle type,
    # such as a static symbol ([Type::ImmSymbol], i.e. true from RB_STATIC_SYM_P()).
    # Opposite of [Self::is_unknown].
    def specific?
      !self.unknown?
    end

    # Check if the type is a heap object
    def heap?
      case self
      in Type::UnknownHeap then true
      in Type::TArray then true
      in Type::Hash then true
      in Type::HeapSymbol then true
      in Type::TString then true
      in Type::CString then true
      in Type::BlockParamProxy then true
      else false
      end
    end

    # Check if it's a T_ARRAY object
    def array?
      case self
      in Type::TArray then true
      else false
      end
    end

    # Check if it's a T_STRING object (both TString and CString are T_STRING)
    def string?
      case self
      in Type::TString then true
      in Type::CString then true
      else false
      end
    end

    # Returns the class if it is known, otherwise nil
    def known_class
      case self
      in Type::Nil then C.rb_cNilClass
      in Type::True then C.rb_cTrueClass
      in Type::False then C.rb_cFalseClass
      in Type::Fixnum then C.rb_cInteger
      in Type::Flonum then C.rb_cFloat
      in Type::ImmSymbol | Type::HeapSymbol then C.rb_cSymbol
      in Type::CString then C.rb_cString
      else nil
      end
    end

    # Returns a boolean representing whether the value is truthy if known, otherwise nil
    def known_truthy
      case self
      in Type::Nil then false
      in Type::False then false
      in Type::UnknownHeap then false
      in Type::Unknown | Type::UnknownImm then nil
      else true
      end
    end

    # Returns a boolean representing whether the value is equal to nil if known, otherwise nil
    def known_nil
      case [self, self.known_truthy]
      in Type::Nil, _ then true
      in Type::False, _ then false # Qfalse is not nil
      in _, true then false # if truthy, can't be nil
      in _, _ then nil # otherwise unknown
      end
    end

    def diff(dst)
      # Perfect match, difference is zero
      if self == dst
        return TypeDiff::Compatible[0]
      end

      # Any type can flow into an unknown type
      if dst == Type::Unknown
        return TypeDiff::Compatible[1]
      end

      # A CString is also a TString.
      if self == Type::CString && dst == Type::TString
        return TypeDiff::Compatible[1]
      end

      # Specific heap type into unknown heap type is imperfect but valid
      if self.heap? && dst == Type::UnknownHeap
        return TypeDiff::Compatible[1]
      end

      # Specific immediate type into unknown immediate type is imperfect but valid
      if self.imm? && dst == Type::UnknownImm
        return TypeDiff::Compatible[1]
      end

      # Incompatible types
      return TypeDiff::Incompatible
    end

    def upgrade(new_type)
      assert(new_type.diff(self) != TypeDiff::Incompatible)
      new_type
    end

    private

    def assert(cond)
      unless cond
        raise "'#{cond.inspect}' was not true"
      end
    end
  end

  # This returns an appropriate Type based on a known value
  class << Type
    def from(val)
      if C::SPECIAL_CONST_P(val)
        if fixnum?(val)
          Type::Fixnum
        elsif val.nil?
          Type::Nil
        elsif val == true
          Type::True
        elsif val == false
          Type::False
        elsif static_symbol?(val)
          Type::ImmSymbol
        elsif flonum?(val)
          Type::Flonum
        else
          raise "Illegal value: #{val.inspect}"
        end
      else
        val_class = C.to_value(C.rb_class_of(val))
        if val_class == C.rb_cString && C.rb_obj_frozen_p(val)
          return Type::CString
        end
        if C.to_value(val) == C.rb_block_param_proxy
          return Type::BlockParamProxy
        end
        case C::BUILTIN_TYPE(val)
        in C::RUBY_T_ARRAY
          Type::TArray
        in C::RUBY_T_HASH
          Type::Hash
        in C::RUBY_T_STRING
          Type::TString
        else
          Type::UnknownHeap
        end
      end
    end

    private

    def fixnum?(obj)
      (C.to_value(obj) & C::RUBY_FIXNUM_FLAG) == C::RUBY_FIXNUM_FLAG
    end

    def flonum?(obj)
      (C.to_value(obj) & C::RUBY_FLONUM_MASK) == C::RUBY_FLONUM_FLAG
    end

    def static_symbol?(obj)
      (C.to_value(obj) & 0xff) == C::RUBY_SYMBOL_FLAG
    end
  end

  # List of types
  Type::Unknown     = Type[:Unknown]
  Type::UnknownImm  = Type[:UnknownImm]
  Type::UnknownHeap = Type[:UnknownHeap]
  Type::Nil         = Type[:Nil]
  Type::True        = Type[:True]
  Type::False       = Type[:False]
  Type::Fixnum      = Type[:Fixnum]
  Type::Flonum      = Type[:Flonum]
  Type::Hash        = Type[:Hash]
  Type::ImmSymbol   = Type[:ImmSymbol]
  Type::HeapSymbol  = Type[:HeapSymbol]

  Type::TString = Type[:TString] # An object with the T_STRING flag set, possibly an rb_cString
  Type::CString = Type[:CString] # An un-subclassed string of type rb_cString (can have instance vars in some cases)
  Type::TArray  = Type[:TArray]  # An object with the T_ARRAY flag set, possibly an rb_cArray

  Type::BlockParamProxy = Type[:BlockParamProxy] # A special sentinel value indicating the block parameter should be read from

  module TypeDiff
    Compatible = Data.define(:diversion) # The smaller, the more compatible.
    Incompatible = :Incompatible
  end
end
