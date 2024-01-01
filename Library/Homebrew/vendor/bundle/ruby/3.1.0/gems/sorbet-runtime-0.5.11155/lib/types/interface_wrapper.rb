# frozen_string_literal: true
# typed: false

# Wraps an object, exposing only the methods defined on a given class/module. The idea is that, in
# the absence of a static type checker that would prevent you from calling non-Bar methods on a
# variable of type Bar, we can use these wrappers as a way of enforcing it at runtime.
#
# Once we ship static type checking, we should get rid of this entirely.
class T::InterfaceWrapper
  extend T::Sig

  module Helpers
    def wrap_instance(obj)
      T::InterfaceWrapper.wrap_instance(obj, self)
    end

    def wrap_instances(arr)
      T::InterfaceWrapper.wrap_instances(arr, self)
    end
  end

  private_class_method :new # use `wrap_instance`

  def self.wrap_instance(obj, interface_mod)
    wrapper = wrapped_dynamic_cast(obj, interface_mod)
    if wrapper.nil?
      raise "#{obj.class} cannot be cast to #{interface_mod}"
    end
    wrapper
  end

  sig do
    params(
      arr: Array,
      interface_mod: T.untyped
    )
    .returns(Array)
  end
  def self.wrap_instances(arr, interface_mod)
    arr.map {|instance| self.wrap_instance(instance, interface_mod)}
  end

  def initialize(target_obj, interface_mod)
    if target_obj.is_a?(T::InterfaceWrapper)
      # wrapped_dynamic_cast should guarantee this never happens.
      raise "Unexpected: wrapping a wrapper. Please report this bug at https://github.com/sorbet/sorbet/issues"
    end

    if !target_obj.is_a?(interface_mod)
      # wrapped_dynamic_cast should guarantee this never happens.
      raise "Unexpected: `is_a?` failed. Please report this bug at https://github.com/sorbet/sorbet/issues"
    end

    if target_obj.class == interface_mod
      # wrapped_dynamic_cast should guarantee this never happens.
      raise "Unexpected: exact class match. Please report this bug at https://github.com/sorbet/sorbet/issues"
    end

    @target_obj = target_obj
    @interface_mod = interface_mod
    self_methods = self.class.self_methods

    # If perf becomes an issue, we can define these on an anonymous subclass, and keep a cache
    # so we only need to do it once per unique `interface_mod`
    T::Utils.methods_excluding_object(interface_mod).each do |method_name|
      if self_methods.include?(method_name)
        raise "interface_mod has a method that conflicts with #{self.class}: #{method_name}"
      end

      define_singleton_method(method_name) do |*args, &blk|
        target_obj.send(method_name, *args, &blk)
      end

      if singleton_class.respond_to?(:ruby2_keywords, true)
        singleton_class.send(:ruby2_keywords, method_name)
      end

      if target_obj.singleton_class.public_method_defined?(method_name)
        # no-op, it's already public
      elsif target_obj.singleton_class.protected_method_defined?(method_name)
        singleton_class.send(:protected, method_name)
      elsif target_obj.singleton_class.private_method_defined?(method_name)
        singleton_class.send(:private, method_name)
      else
        raise "This should never happen. Report this bug at https://github.com/sorbet/sorbet/issues"
      end
    end
  end

  def kind_of?(other)
    is_a?(other)
  end

  def is_a?(other)
    if !other.is_a?(Module)
      raise TypeError.new("class or module required")
    end

    # This makes is_a? return true for T::InterfaceWrapper (and its ancestors),
    # as well as for @interface_mod and its ancestors.
    self.class <= other || @interface_mod <= other
  end

  # Prefixed because we're polluting the namespace of the interface we're wrapping, and we don't
  # want anyone else (besides dynamic_cast) calling it.
  def __target_obj_DO_NOT_USE # rubocop:disable Naming/MethodName
    @target_obj
  end

  # Prefixed because we're polluting the namespace of the interface we're wrapping, and we don't
  # want anyone else (besides wrapped_dynamic_cast) calling it.
  def __interface_mod_DO_NOT_USE # rubocop:disable Naming/MethodName
    @interface_mod
  end

  # "Cast" an object to another type. If `obj` is an InterfaceWrapper, returns the the wrapped
  # object if that matches `type`. Otherwise, returns `obj` if it matches `type`. Otherwise,
  # returns nil.
  #
  # @param obj [Object] object to cast
  # @param mod [Module] type to cast `obj` to
  #
  # @example
  #   if (impl = T::InterfaceWrapper.dynamic_cast(iface, MyImplementation))
  #     impl.do_things
  #   end
  def self.dynamic_cast(obj, mod)
    if obj.is_a?(T::InterfaceWrapper)
      target_obj = obj.__target_obj_DO_NOT_USE
      target_obj.is_a?(mod) ? target_obj : nil
    elsif obj.is_a?(mod)
      obj
    else
      nil
    end
  end

  # Like dynamic_cast, but puts the result in its own wrapper if necessary.
  #
  # @param obj [Object] object to cast
  # @param mod [Module] type to cast `obj` to
  def self.wrapped_dynamic_cast(obj, mod)
    # Avoid unwrapping and creating an equivalent wrapper.
    if obj.is_a?(T::InterfaceWrapper) && obj.__interface_mod_DO_NOT_USE == mod
      return obj
    end

    cast_obj = dynamic_cast(obj, mod)
    if cast_obj.nil?
      nil
    elsif cast_obj.class == mod
      # Nothing to wrap, they want the full class
      cast_obj
    else
      new(cast_obj, mod)
    end
  end

  def self.self_methods
    @self_methods ||= self.instance_methods(false).to_set
  end
end
