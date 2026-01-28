# frozen_string_literal: true
# typed: true

# Use as a mixin with extend (`extend T::Helpers`).
# Docs at https://sorbet.org/docs/
module T::Helpers
  extend T::Sig

  Private = T::Private

  ### Class/Module Helpers ###

  def abstract!
    if defined?(super)
      # This is to play nicely with Rails' AbstractController::Base,
      # which also defines an `abstract!` method.
      # https://api.rubyonrails.org/classes/AbstractController/Base.html#method-c-abstract-21
      super
    end

    Private::Abstract::Declare.declare_abstract(self, type: :abstract)
  end

  def interface!
    Private::Abstract::Declare.declare_abstract(self, type: :interface)
  end

  def final!
    Private::Final.declare(self)
  end

  def sealed!
    Private::Sealed.declare(self, Kernel.caller(1..1)&.first&.split(':')&.first)
  end

  # Causes a mixin to also mix in class methods from the named module.
  #
  # Nearly equivalent to
  #
  #  def self.included(other)
  #    other.extend(mod)
  #  end
  #
  # Except that it is statically analyzed by sorbet.
  def mixes_in_class_methods(mod, *mods)
    Private::Mixins.declare_mixes_in_class_methods(self, [mod].concat(mods))
  end

  # Specify an inclusion or inheritance requirement for `self`.
  #
  # Example:
  #
  #   module MyHelper
  #     extend T::Helpers
  #
  #     requires_ancestor { Kernel }
  #   end
  #
  #   class MyClass < BasicObject # error: `MyClass` must include `Kernel` (required by `MyHelper`)
  #     include MyHelper
  #   end
  #
  # TODO: implement the checks in sorbet-runtime.
  def requires_ancestor(&block); end
end
