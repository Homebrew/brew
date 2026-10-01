# frozen_string_literal: true
# typed: strict

# Used as a mixin to any class so that you can call `sig`.
# Docs at https://sorbet.org/docs/sigs
module T::Sig
  include T::Private::Methods::MethodHooks
  include T::Private::Methods::SingletonMethodHooks

  private_class_method def self.included(other)
    return unless Module == other

    # Module#method_added is normally a no-op method that does not call
    # `super` and immediately returns `nil`. This means that `method_added`
    # methods defined on an ancestor of `Module` are never called, so for
    # `Module` itself, we need to redefine to call `super` to forward to the
    # `method_added` defined above and which is already in the hierarchy.
    #
    # (`singleton_method_added` is defined on `BasicObject`, so ours does
    # override that one.)
    other.prepend(T::Private::Methods::MethodHooks)
  end

  private_class_method def self.extended(other)
    if other == T::Private::Methods::TOP_SELF
      # Methods defined via `def foo; end` at the top-level of a file are
      # actually defined as private instance methods on `Object`, so we have to
      # register our `method_added` hook there.
      #
      # Methods defined via `def self.foo; end` at the top-level are defined on
      # a special instance of `Object` called `main` (initialized by the VM on
      # startup), and putting `extend T::Sig` at the top-level of a file has
      # the effect of putting `singleton_method_added` on the singleton class
      # of `main`, which is catches those methods.
      Object.extend(T::Private::Methods::MethodHooks)
      return
    end

    return unless Module.===(other) && other.singleton_class?

    # Given this:
    #
    #     class A
    #       class << self
    #         extend T::Sig
    #       end
    #     end
    #
    # The `singleton_method_added` hook will end up defined as if
    # `A.singleton_class.singleton_class#singleton_method_added`[1], so methods
    # defined via `def self.` inside the `class << self` will be hooked, but
    # not "instance" methods, because for better or worse Ruby chooses to call
    # `A.singleton_method_added` even for `def foo` (an instance method) inside
    # a `class << self` definition.[2]
    #
    # This forces a problem on users: they need `extend T::Sig` to make `sig`
    # callable at the class body, but they need `include T::Sig` to make sure
    # that the `singleton_method_added` hook lands on the right place. To
    # avoid users needing to do that, we define an extra
    # `singleton_method_added` on the `attached_object` of the singleton
    # class, aka `A.singleton_method_added`.[3]
    #
    # [1] Not actually--it will be in the ancestor chain, but callable on
    #   values of that type.
    #
    # [2] I imagine this is for backwards compatibility in the common case of
    #   one level of `class << self` nesting, so that people can define a
    #   single `singleton_method_added` hook and have it fire for `def
    #   self.foo` methods outside and `def foo` inside.
    #
    # [3] Before switching to having the hooks defined eagerly `T::Sig`
    #   itself, this was done lazily via `include(SingletonMethodHooks)`
    #   instead of `extend(MethodHooks)` on the first call to `sig` inside
    #   the `class << self`.
    other.include(T::Private::Methods::SingletonMethodHooks)
  end

  module WithoutRuntime
    # At runtime, does nothing, but statically it is treated exactly the same
    # as T::Sig#sig. Only use it in cases where you can't use T::Sig#sig.
    def self.sig(arg0=nil, &blk); end

    original_verbose = $VERBOSE
    $VERBOSE = false

    # At runtime, does nothing, but statically it is treated exactly the same
    # as T::Sig#sig. Only use it in cases where you can't use T::Sig#sig.
    T::Sig::WithoutRuntime.sig { params(arg0: T.nilable(Symbol), blk: T.proc.bind(T::Private::Methods::DeclBuilder).void).void }
    def self.sig(arg0=nil, &blk); end # rubocop:disable Lint/DuplicateMethods

    $VERBOSE = original_verbose
  end

  # Declares a method with type signatures and/or
  # abstract/override/... helpers. See the documentation URL on
  # {T::Helpers}
  T::Sig::WithoutRuntime.sig { params(arg0: T.nilable(Symbol), blk: T.proc.bind(T::Private::Methods::DeclBuilder).void).void }
  def sig(arg0=nil, &blk)
    T::Private::Methods.declare_sig(T.unsafe(self), Kernel.caller_locations(1, 1)&.first, arg0, &blk)
  end
end
