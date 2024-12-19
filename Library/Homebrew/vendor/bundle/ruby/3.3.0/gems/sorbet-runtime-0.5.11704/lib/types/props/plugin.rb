# frozen_string_literal: true
# typed: false

module T::Props::Plugin
  include T::Props
  extend T::Helpers

  module ClassMethods
    def included(child)
      super
      child.plugin(self)
    end
  end
  mixes_in_class_methods(ClassMethods)

  module Private
    # These need to be non-instance methods so we can use them without prematurely creating the
    # child decorator in `model_inherited` (see comments there for details).
    #
    # The dynamic constant access below forces this file to be `typed: false`
    def self.apply_class_methods(plugin, target)
      if plugin.const_defined?('ClassMethods')
        # FIXME: This will break preloading, selective test execution, etc if `mod::ClassMethods`
        # is ever defined in a separate file from `mod`.
        target.extend(plugin::ClassMethods)
      end
    end

    def self.apply_decorator_methods(plugin, target)
      if plugin.const_defined?('DecoratorMethods')
        # FIXME: This will break preloading, selective test execution, etc if `mod::DecoratorMethods`
        # is ever defined in a separate file from `mod`.
        target.extend(plugin::DecoratorMethods)
      end
    end
  end
end
