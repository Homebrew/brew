# frozen_string_literal: true
# typed: true

module T::Private::Abstract::Validate
  Abstract = T::Private::Abstract
  AbstractUtils = T::AbstractUtils
  Methods = T::Private::Methods
  SignatureValidation = T::Private::Methods::SignatureValidation

  def self.validate_abstract_module(mod)
    type = Abstract::Data.get(mod, :abstract_type)
    validate_interface(mod) if type == :interface
  end

  # Validates a class/module with an abstract class/module as an ancestor. This must be called
  # after all methods on `mod` have been defined.
  def self.validate_subclass(mod)
    can_have_abstract_methods = !T::Private::Abstract::Data.get(mod, :can_have_abstract_methods)
    unimplemented_methods = []

    T::AbstractUtils.declared_abstract_methods_for(mod).each do |abstract_method|
      implementation_method = mod.instance_method(abstract_method.name)
      if AbstractUtils.abstract_method?(implementation_method)
        # Note that when we end up here, implementation_method might not be the same as
        # abstract_method; the latter could've been overridden by another abstract method. In either
        # case, if we have a concrete definition in an ancestor, that will end up as the effective
        # implementation (see CallValidation.wrap_method_if_needed), so that's what we'll validate
        # against.
        implementation_method = T.unsafe(nil)
        mod.ancestors.each do |ancestor|
          if ancestor.instance_methods.include?(abstract_method.name)
            method = ancestor.instance_method(abstract_method.name)
            T::Private::Methods.maybe_run_sig_block_for_method(method)
            if !T::AbstractUtils.abstract_method?(method)
              implementation_method = method
              break
            end
          end
        end
        if !implementation_method
          # There's no implementation
          if can_have_abstract_methods
            unimplemented_methods << describe_method(abstract_method)
          end
          next # Nothing to validate
        end
      end

      implementation_signature = Methods.signature_for_method(implementation_method)
      # When a signature exists and the method is defined directly on `mod`, we skip the validation
      # here, because it will have already been done when the method was defined (by
      # T::Private::Methods._on_method_added).
      next if implementation_signature&.owner == mod

      # We validate the remaining cases here: (a) methods defined directly on `mod` without a
      # signature and (b) methods from ancestors (note that these ancestors can come before or
      # after the abstract module in the inheritance chain -- the former coming from
      # walking `mod.ancestors` above).
      abstract_signature = Methods.signature_for_method(abstract_method)
      # We allow implementation methods to be defined without a signature.
      # In that case, get its untyped signature.
      implementation_signature ||= Methods::Signature.new_untyped(
        method: implementation_method,
        mode: Methods::Modes.override
      )
      SignatureValidation.validate_override_shape(implementation_signature, abstract_signature)
      SignatureValidation.validate_override_types(implementation_signature, abstract_signature)
    end

    method_type = mod.singleton_class? ? "class" : "instance"
    if !unimplemented_methods.empty?
      raise "Missing implementation for abstract #{method_type} method(s) in #{mod}:\n" \
            "#{unimplemented_methods.join("\n")}\n" \
            "If #{mod} is meant to be an abstract class/module, you can call " \
            "`abstract!` or `interface!`. Otherwise, you must implement the method(s)."
    end
  end

  private_class_method def self.validate_interface_all_abstract(mod, method_names)
    violations = method_names.map do |method_name|
      method = mod.instance_method(method_name)
      if !AbstractUtils.abstract_method?(method)
        describe_method(method, show_owner: false)
      end
    end.compact

    if !violations.empty?
      raise "`#{mod}` is declared as an interface, but the following methods are not declared " \
            "with `abstract`:\n#{violations.join("\n")}"
    end
  end

  private_class_method def self.validate_interface(mod)
    interface_methods = T::Utils.methods_excluding_object(mod)
    validate_interface_all_abstract(mod, interface_methods)
    validate_interface_all_public(mod, interface_methods)
  end

  private_class_method def self.validate_interface_all_public(mod, method_names)
    violations = method_names.map do |method_name|
      if !mod.public_method_defined?(method_name)
        describe_method(mod.instance_method(method_name), show_owner: false)
      end
    end.compact

    if !violations.empty?
      raise "All methods on an interface must be public. If you intend to have non-public " \
            "methods, declare your class/module using `abstract!` instead of `interface!`. " \
            "The following methods on `#{mod}` are not public: \n#{violations.join("\n")}"
    end
  end

  private_class_method def self.describe_method(method, show_owner: true)
    loc = if method.source_location
      method.source_location.join(':')
    else
      "<unknown location>"
    end

    owner = if show_owner
      " declared in #{method.owner}"
    else
      ""
    end

    "    * `#{method.name}`#{owner} at #{loc}"
  end
end
