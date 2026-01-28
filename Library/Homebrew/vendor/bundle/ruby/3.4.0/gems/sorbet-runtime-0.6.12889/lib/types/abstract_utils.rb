# frozen_string_literal: true
# typed: true

module T::AbstractUtils
  Methods = T::Private::Methods

  # Returns whether a module is declared as abstract. After the module is finished being declared,
  # this is equivalent to whether it has any abstract methods that haven't been implemented
  # (because we validate that and raise an error otherwise).
  #
  # Note that checking `mod.is_a?(Abstract::Hooks)` is not a safe substitute for this method; when
  # a class extends `Abstract::Hooks`, all of its subclasses, including the eventual concrete
  # ones, will still have `Abstract::Hooks` as an ancestor.
  def self.abstract_module?(mod)
    !T::Private::Abstract::Data.get(mod, :abstract_type).nil?
  end

  def self.abstract_method?(method)
    signature = Methods.signature_for_method(method)
    signature&.mode == Methods::Modes.abstract
  end

  # Given a module, returns the set of methods declared as abstract (in itself or ancestors)
  # that have not been implemented.
  def self.abstract_methods_for(mod)
    declared_methods = declared_abstract_methods_for(mod)
    declared_methods.select do |declared_method|
      actual_method = mod.instance_method(declared_method.name)
      # Note that in the case where an abstract method is overridden by another abstract method,
      # this method will return them both. This is intentional to ensure we validate the final
      # implementation against all declarations of an abstract method (they might not all have the
      # same signature).
      abstract_method?(actual_method)
    end
  end

  # Given a module, returns the set of methods declared as abstract (in itself or ancestors)
  # regardless of whether they have been implemented.
  def self.declared_abstract_methods_for(mod)
    methods = []
    mod.ancestors.each do |ancestor|
      ancestor_methods = ancestor.private_instance_methods(false) + ancestor.instance_methods(false)
      ancestor_methods.each do |method_name|
        method = ancestor.instance_method(method_name)
        methods << method if abstract_method?(method)
      end
    end
    methods
  end
end
