module Concurrent

  # Special "compare and set" handling of numeric values.
  #
  # @!visibility private
  # @!macro internal_implementation_note
  module AtomicNumericCompareAndSetWrapper

    # @!macro atomic_reference_method_compare_and_set
    def compare_and_set(old_value, new_value)
      if old_value.kind_of? Numeric
        # NaN is never == to itself; match it explicitly so #update can terminate.
        expected_nan = old_value.respond_to?(:nan?) && old_value.nan?
        while true
          old = get

          return false unless old.kind_of? Numeric

          if expected_nan
            return false unless old.respond_to?(:nan?) && old.nan?
          else
            return false unless old == old_value
          end

          result = _compare_and_set(old, new_value)
          return result if result
        end
      else
        _compare_and_set(old_value, new_value)
      end
    end

    alias_method :compare_and_swap, :compare_and_set

  end
end
