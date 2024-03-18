# frozen_string_literal: true
# typed: true

module T::Types
  # Defines the type of a proc (a ruby callable). At runtime, only
  # validates that the value is a `::Proc`.
  #
  # At present, we only support fixed-arity procs with no optional or
  # keyword arguments.
  class Proc < Base
    def initialize(arg_types, returns)
      @inner_arg_types = arg_types
      @inner_returns = returns
    end

    def arg_types
      @arg_types ||= @inner_arg_types.transform_values do |raw_type|
        T::Utils.coerce(raw_type)
      end
    end

    def returns
      @returns ||= T::Utils.coerce(@inner_returns)
    end

    def build_type
      arg_types
      returns
      nil
    end

    # overrides Base
    def name
      args = []
      arg_types.each do |k, v|
        args << "#{k}: #{v.name}"
      end
      "T.proc.params(#{args.join(', ')}).returns(#{returns})"
    end

    # overrides Base
    def valid?(obj)
      obj.is_a?(::Proc)
    end

    # overrides Base
    private def subtype_of_single?(other)
      case other
      when self.class
        if arg_types.size != other.arg_types.size
          return false
        end
        arg_types.values.zip(other.arg_types.values).all? do |a, b|
          b.subtype_of?(a)
        end && returns.subtype_of?(other.returns)
      else
        false
      end
    end
  end
end
