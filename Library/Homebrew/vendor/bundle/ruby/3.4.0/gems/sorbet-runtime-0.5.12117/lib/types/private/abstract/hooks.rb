# frozen_string_literal: true
# typed: true

module T::Private::Abstract::Hooks
  # This will become the self.extend_object method on a module that extends Abstract::Hooks.
  # It gets called when *that* module gets extended in another class/module (similar to the
  # `extended` hook, but this gets calls before the ancestors of `other` get modified, which
  # is important for our validation).
  private def extend_object(other)
    T::Private::Abstract::Data.set(self, :last_used_by, other)
    super
  end

  # This will become the self.append_features method on a module that extends Abstract::Hooks.
  # It gets called when *that* module gets included in another class/module (similar to the
  # `included` hook, but this gets calls before the ancestors of `other` get modified, which
  # is important for our validation).
  private def append_features(other)
    T::Private::Abstract::Data.set(self, :last_used_by, other)
    super
  end

  # This will become the self.inherited method on a class that extends Abstract::Hooks.
  # It gets called when *that* class gets inherited by another class.
  private def inherited(other)
    super
    # `self` may not actually be abstract -- it could be a concrete class that inherited from an
    # abstract class. We only need to check this in `inherited` because, for modules being included
    # or extended, the concrete ones won't have these hooks at all. This is just an optimization.
    return if !T::AbstractUtils.abstract_module?(self)

    T::Private::Abstract::Data.set(self, :last_used_by, other)
  end

  # This will become the self.prepended method on a module that extends Abstract::Hooks.
  # It will get called when *that* module gets prepended in another class/module.
  private def prepended(other)
    # Prepending abstract methods is weird. You'd only be able to override them via other prepended
    # modules, or in subclasses. Punt until we have a use case.
    Kernel.raise "Prepending abstract mixins is not currently supported."
  end
end
