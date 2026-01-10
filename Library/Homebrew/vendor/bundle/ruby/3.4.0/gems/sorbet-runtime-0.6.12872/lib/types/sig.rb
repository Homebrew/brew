# frozen_string_literal: true
# typed: strict

# Used as a mixin to any class so that you can call `sig`.
# Docs at https://sorbet.org/docs/sigs
module T::Sig
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
    T::Private::Methods.declare_sig(self, Kernel.caller_locations(1, 1)&.first, arg0, &blk)
  end
end
