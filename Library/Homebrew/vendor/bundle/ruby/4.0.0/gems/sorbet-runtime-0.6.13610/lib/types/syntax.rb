# frozen_string_literal: true
# typed: strict

# Used as a shortcut for mixing in the three most common "syntax" extensions
# that Sorbet provides: `sig`, the various sig DSL methods like `abstract` and
# `override`, and the `final!`/`interface!` etc. syntax for class-level
# annotations
module T::Syntax
  include T::Sig
  include T::DefMods
  include T::Helpers

  # ===== NOTE: Must keep in sync with `T::Sig`! ==============================
  #
  # However, there are some slight differences:
  #
  # - We don't need the extra `include ... MethodHooks` lines, because those
  #   come from the `include T::Sig` (c.f. `T::DefMods` though, where those
  #   extra `include` *are* required because there is otherwise no inheritance
  #   relationship between `T::Sig` and `T::DefMods`)
  #
  # - We don't do the TOP_SELF things, because it's not clear that you ever
  #   really want this for TOP_SELF. e.g. what would it mean to write
  #   `interface!` there?
  #
  #   Rather than encourage people to write `extend T::Syntax` in their script
  #   top-levels, let's encourage people to just write `extend T::Sig` to keep
  #   things simpler.
  #
  #   (We could revisit this in the future if people do really want this.)

  private_class_method def self.included(other)
    return unless Module == other
    other.prepend(T::Private::Methods::MethodHooks)
  end

  private_class_method def self.extended(other)
    return unless Module.===(other) && other.singleton_class?
    other.include(T::Private::Methods::SingletonMethodHooks)
  end
  # ===========================================================================
end
