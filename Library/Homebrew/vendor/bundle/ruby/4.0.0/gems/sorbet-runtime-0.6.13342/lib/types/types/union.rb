# frozen_string_literal: true
# typed: true

module T::Types
  # Takes a list of types. Validates that an object matches at least one of the types.
  class Union < Base
    # Don't use Union.new directly, use `Private::Pool.union_of_types`
    # inside sorbet-runtime and `T.any` elsewhere.
    def initialize(types)
      @inner_types = types
    end

    def types
      @types ||= begin
        flattened = @inner_types.flat_map do |type|
          type = T::Utils.coerce(type)
          if type.is_a?(Union)
            # Simplify nested unions (mostly so `name` returns a nicer value)
            type.types
          else
            type
          end
        end.uniq
        # When every member is a plain Simple (whose valid? is exactly
        # `obj.is_a?(raw_type)`), precompute the members' raw modules so
        # valid? can skip per-member dispatch. instance_of? (the is_a? only
        # narrows for static checking) so that any Simple subclass overriding
        # valid? would be excluded. Note this snapshots the members at build
        # time.
        member_modules = []
        all_simple = flattened.all? do |type|
          type.is_a?(T::Types::Simple) && type.instance_of?(T::Types::Simple) &&
            member_modules << type.raw_type
        end
        @member_modules = all_simple ? member_modules.freeze : false
        flattened
      end
    end

    def build_type
      types
      nil
    end

    # overrides Base
    def name
      # Use the attr_reader here so we can override it in SimplePairUnion
      type_shortcuts(types)
    end

    private def type_shortcuts(types)
      if types.size == 1
        # We shouldn't generally get here but it's possible if initializing the type
        # evades Sorbet's static check and we end up on the slow path, or if someone
        # is using the T:Types::Union constructor directly (the latter possibility
        # is why we don't just move the `uniq` into `Private::Pool.union_of_types`).
        return types.fetch(0).name
      end
      nilable = T::Utils.coerce(NilClass)
      trueclass = T::Utils.coerce(TrueClass)
      falseclass = T::Utils.coerce(FalseClass)
      if types.any? { |t| t == nilable }
        remaining_types = types.reject { |t| t == nilable }
        "T.nilable(#{type_shortcuts(remaining_types)})"
      elsif types.any? { |t| t == trueclass } && types.any? { |t| t == falseclass }
        remaining_types = types.reject { |t| t == trueclass || t == falseclass }
        type_shortcuts([T::Private::Types::StringHolder.new("T::Boolean")] + remaining_types)
      else
        names = types.map(&:name).compact.sort
        "T.any(#{names.join(', ')})"
      end
    end

    # overrides Base
    def recursively_valid?(obj)
      member_modules = @member_modules
      if member_modules.nil?
        # Force the lazy types builder, which also computes @member_modules
        types
        member_modules = @member_modules
      end
      index = 0
      if member_modules
        # For an all-Simple union, recursively_valid? and valid? coincide
        # (Simple's recursively_valid? is exactly `obj.is_a?(raw_type)`).
        while index < member_modules.length
          return true if obj.is_a?(member_modules[index])
          index += 1
        end
      else
        members = types
        while index < members.length
          return true if members.fetch(index).recursively_valid?(obj)
          index += 1
        end
      end
      false
    end

    # overrides Base
    def valid?(obj)
      member_modules = @member_modules
      if member_modules.nil?
        # Force the lazy types builder, which also computes @member_modules
        types
        member_modules = @member_modules
      end
      index = 0
      if member_modules
        while index < member_modules.length
          return true if obj.is_a?(member_modules[index])
          index += 1
        end
      else
        members = types
        while index < members.length
          return true if members.fetch(index).valid?(obj)
          index += 1
        end
      end
      false
    end

    # overrides Base
    private def subtype_of_single?(other)
      raise "This should never be reached if you're going through `subtype_of?` (and you should be)"
    end

    def unwrap_nilable
      non_nil_types = types.reject { |t| t == T::Utils::Nilable::NIL_TYPE }
      return nil if types.length == non_nil_types.length
      case non_nil_types.length
      when 0 then nil
      when 1 then non_nil_types.first
      else
        T::Types::Union::Private::Pool.union_of_types(non_nil_types[0], non_nil_types[1], non_nil_types[2..-1])
      end
    end

    module Private
      module Pool
        EMPTY_ARRAY = [].freeze
        private_constant :EMPTY_ARRAY

        # Try to use `to_nilable` on a type to get memoization, or failing that
        # try to at least use SimplePairUnion to get faster init and typechecking.
        #
        # We aren't guaranteed to detect a simple `T.nilable(<Module>)` type here
        # in cases where there are duplicate types, nested unions, etc.
        #
        # That's ok, because returning is SimplePairUnion an optimization which
        # isn't necessary for correctness.
        #
        # @param type_a [T::Types::Base]
        # @param type_b [T::Types::Base]
        # @param types [Array] optional array of additional T::Types::Base instances
        def self.union_of_types(type_a, type_b, types=EMPTY_ARRAY)
          if !types.empty?
            # Slow path
            return Union.new([type_a, type_b] + types)
          elsif !type_a.is_a?(T::Types::Simple) || !type_b.is_a?(T::Types::Simple)
            # Slow path
            return Union.new([type_a, type_b])
          end

          begin
            # The `equal?` checks are an identity fast path: NIL_TYPE is the pooled
            # `coerce(NilClass)` instance, so it hits on every normal `T.nilable` call.
            # The `==` fallbacks preserve semantics for hand-constructed
            # `Simple.new(NilClass)` instances that bypass the pool.
            if type_b.equal?(T::Utils::Nilable::NIL_TYPE) || type_b == T::Utils::Nilable::NIL_TYPE
              type_a.to_nilable
            elsif type_a.equal?(T::Utils::Nilable::NIL_TYPE) || type_a == T::Utils::Nilable::NIL_TYPE
              type_b.to_nilable
            else
              T::Private::Types::SimplePairUnion.new(type_a, type_b)
            end
          rescue T::Private::Types::SimplePairUnion::DuplicateType
            # Slow path
            #
            # This shouldn't normally be possible due to static checks,
            # but we can get here if we're constructing a type dynamically.
            #
            # Relying on the duplicate check in the constructor has the
            # advantage that we avoid it when we hit the memoized case
            # of `to_nilable`.
            type_a
          end
        end
      end
    end
  end
end
