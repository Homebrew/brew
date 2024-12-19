# frozen_string_literal: true
# typed: true

module T::Types
  class Base
    def self.method_added(method_name)
      super(method_name)
      # What is now `subtype_of_single?` used to be named `subtype_of?`. Make sure people don't
      # override the wrong thing.
      #
      # NB: Outside of T::Types, we would enforce this by using `sig` and not declaring the method
      # as overridable, but doing so here would result in a dependency cycle.
      if method_name == :subtype_of? && self != T::Types::Base
        raise "`subtype_of?` should not be overridden. You probably want to override " \
              "`subtype_of_single?` instead."
      end
    end

    # this will be redefined in certain subclasses
    def recursively_valid?(obj)
      valid?(obj)
    end

    define_method(:valid?) do |_obj|
      raise NotImplementedError
    end

    # @return [T::Boolean] This method must be implemented to return whether the subclass is a subtype
    # of `type`. This should only be called by `subtype_of?`, which guarantees that `type` will be
    # a "single" type, by which we mean it won't be a Union or an Intersection (c.f.
    # `isSubTypeSingle` in sorbet).
    private def subtype_of_single?(type)
      raise NotImplementedError
    end

    # Force any lazy initialization that this type might need to do
    # It's unusual to call this directly; you probably want to call it indirectly via `T::Utils.run_all_sig_blocks`.
    define_method(:build_type) do
      raise NotImplementedError
    end

    # Equality is based on name, so be sure the name reflects all relevant state when implementing.
    define_method(:name) do
      raise NotImplementedError
    end

    # Mirrors ruby_typer::core::Types::isSubType
    # See https://git.corp.stripe.com/stripe-internal/ruby-typer/blob/9fc8ed998c04ac0b96592ae6bb3493b8a925c5c1/core/types/subtyping.cc#L912-L950
    #
    # This method cannot be overridden (see `method_added` above).
    # Subclasses only need to implement `subtype_of_single?`).
    def subtype_of?(t2)
      t1 = self

      if t2.is_a?(T::Private::Types::TypeAlias)
        t2 = t2.aliased_type
      end

      if t2.is_a?(T::Types::Anything)
        return true
      end

      if t1.is_a?(T::Private::Types::TypeAlias)
        return t1.aliased_type.subtype_of?(t2)
      end

      if t1.is_a?(T::Types::TypeVariable) || t2.is_a?(T::Types::TypeVariable)
        # Generics are erased at runtime. Let's treat them like `T.untyped` for
        # the purpose of things like override checking.
        return true
      end

      # pairs to cover: 1  (_, _)
      #                 2  (_, And)
      #                 3  (_, Or)
      #                 4  (And, _)
      #                 5  (And, And)
      #                 6  (And, Or)
      #                 7  (Or, _)
      #                 8  (Or, And)
      #                 9  (Or, Or)

      # Note: order of cases here matters!
      if t1.is_a?(T::Types::Union) # 7, 8, 9
        # this will be incorrect if/when we have Type members
        return t1.types.all? {|t1_member| t1_member.subtype_of?(t2)}
      end

      if t2.is_a?(T::Types::Intersection) # 2, 5
        # this will be incorrect if/when we have Type members
        return t2.types.all? {|t2_member| t1.subtype_of?(t2_member)}
      end

      if t2.is_a?(T::Types::Union)
        if t1.is_a?(T::Types::Intersection) # 6
          # dropping either of parts eagerly make subtype test be too strict.
          # we have to try both cases, when we normally try only one
          return t2.types.any? {|t2_member| t1.subtype_of?(t2_member)} ||
              t1.types.any? {|t1_member| t1_member.subtype_of?(t2)}
        end
        return t2.types.any? {|t2_member| t1.subtype_of?(t2_member)} # 3
      end

      if t1.is_a?(T::Types::Intersection) # 4
        # this will be incorrect if/when we have Type members
        return t1.types.any? {|t1_member| t1_member.subtype_of?(t2)}
      end

      # 1; Start with some special cases
      if t1.is_a?(T::Private::Types::Void)
        return t2.is_a?(T::Private::Types::Void)
      end

      if t1.is_a?(T::Types::Untyped) || t2.is_a?(T::Types::Untyped)
        return true
      end

      # Rest of (1)
      subtype_of_single?(t2)
    end

    def to_s
      name
    end

    def describe_obj(obj)
      # Would be redundant to print class and value in these common cases.
      case obj
      when nil, true, false
        return "type #{obj.class}"
      end

      # In rare cases, obj.inspect may fail, or be undefined, so rescue.
      begin
        # Default inspect behavior of, eg; `#<Object:0x0...>` is ugly; just print the hash instead, which is more concise/readable.
        if obj.method(:inspect).owner == Kernel
          "type #{obj.class} with hash #{obj.hash}"
        elsif T::Configuration.include_value_in_type_errors?
          "type #{obj.class} with value #{T::Utils.string_truncate_middle(obj.inspect, 30, 30)}"
        else
          "type #{obj.class}"
        end
      rescue StandardError, SystemStackError
        "type #{obj.class} with unprintable value"
      end
    end

    def error_message_for_obj(obj)
      if valid?(obj)
        nil
      else
        error_message(obj)
      end
    end

    def error_message_for_obj_recursive(obj)
      if recursively_valid?(obj)
        nil
      else
        error_message(obj)
      end
    end

    private def error_message(obj)
      "Expected type #{self.name}, got #{describe_obj(obj)}"
    end

    def validate!(obj)
      err = error_message_for_obj(obj)
      raise TypeError.new(err) if err
    end

    ### Equality methods (necessary for deduping types with `uniq`)

    def hash
      name.hash
    end

    # Type equivalence, defined by serializing the type to a string (with
    # `#name`) and comparing the resulting strings for equality.
    def ==(other)
      case other
      when T::Types::Base
        other.name == self.name
      else
        false
      end
    end

    alias_method :eql?, :==
  end
end
