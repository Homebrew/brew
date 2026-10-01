# typed: true
# frozen_string_literal: true

raise "This needs to be required before Cacheable gets loaded normally." if defined?(Cacheable)

# Collect all classes that mix in Cacheable so that those caches can be cleared in-between tests.
module Cacheable
  private_class_method def self.included(klass)
    # It's difficult to backtrack from a singleton class to find the original class
    # and you can always just extend this module instead for equivalent behavior.
    raise ArgumentError, "Don't use Cacheable with singleton classes" if klass.singleton_class?

    super if defined?(super)
  end

  private_class_method def self.extended(klass)
    Registry.class_list << klass
    # Ignore the `Formula` class that gets inherited from a lot and
    # that has caches that we don't need to clear on the class level.
    klass.extend(Inherited) if klass.name != "Formula"
    super if defined?(super)
  end

  module Inherited
    def inherited(klass)
      # A class might inherit Cacheable at the instance level
      # and in that case we just want to skip registering it.
      Registry.class_list << klass if klass.respond_to?(:clear_cache)
      super if defined?(super)
    end
  end

  module Registry
    # A list of all classes that have been loaded into memory that mixin or
    # inherit `Cacheable` at the class or module level.
    #
    # NOTE: Classes that inherit from `Formula` are excluded since it's not
    #       necessary to track and clear individual formula caches.
    def self.class_list
      @class_list ||= []
    end

    # Clear the cache of every class or module that mixes in or inherits
    # `Cacheable` at the class or module level.
    #
    # NOTE: Classes that inherit from `Formula` are excluded since it's not
    #       necessary to track and clear individual formula caches.
    def self.clear_all_caches
      class_list.each(&:clear_cache)
    end
  end
end
