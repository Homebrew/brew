require 'power_assert/configuration'

if defined?(RubyVM)
  if PowerAssert.configuration._redefinition
    module PowerAssert
      # set redefined flag
      basic_classes = [
        Integer, Float, String, Array, Hash, Symbol, Time, Regexp, NilClass, TrueClass, FalseClass
      ]

      verbose = $VERBOSE
      begin
        $VERBOSE = nil
        [:Fixnum, :Bignum].each do |c|
          if Object.const_defined?(c) and (c = Object.const_get(c)) != Integer
            basic_classes << c
          end
        end
      ensure
        $VERBOSE = verbose
      end

      basic_operators = [
        :+, :-, :*, :/, :%, :==, :===, :<, :<=, :<<, :[], :[]=,
        :length, :size, :empty?, :succ, :>, :>=, :!, :!=, :=~, :freeze, :-@, :max, :min, :nil?
      ]

      basic_classes.each do |klass|
        basic_operators.each do |bop|
          if klass.public_method_defined?(bop)
            refine(klass) do
              define_method(bop) {}
            end
          end
        end
      end

      # bypass check_cfunc
      refine BasicObject do
        def !
        end

        def ==
        end
      end

      refine Module do
        def ==
        end
      end
    end
  end

  # disable optimization
  RubyVM::InstructionSequence.compile_option = {
    specialized_instruction: false
  }
end
