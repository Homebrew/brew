# frozen_string_literal: true
# typed: true

# A mixin for defining typed properties (attributes).
# To get serialization methods (to/from JSON-style hashes), add T::Props::Serializable.
# To get a constructor based on these properties, inherit from T::Struct.
module T::Props
  extend T::Helpers

  #####
  # CAUTION: This mixin is used in hundreds of classes; we want to keep its surface area as narrow
  # as possible and avoid polluting (and possibly conflicting with) the classes that use it.
  #
  # It currently has *zero* instance methods; let's try to keep it that way.
  # For ClassMethods (below), try to add things to T::Props::Decorator instead unless you are sure
  # it needs to be exposed here.
  #####

  module ClassMethods
    extend T::Sig
    extend T::Helpers

    def props
      decorator.props
    end
    def plugins
      @plugins ||= []
    end

    def decorator_class
      Decorator
    end

    def decorator
      @decorator ||= decorator_class.new(self)
    end
    def reload_decorator!
      @decorator = decorator_class.new(self)
    end

    # Define a new property. See {file:README.md} for some concrete
    #  examples.
    #
    # Defining a property defines a method with the same name as the
    # property, that returns the current value, and a `prop=` method
    # to set its value. Properties will be inherited by subclasses of
    # a document class.
    #
    # @param name [Symbol] The name of this property
    # @param cls [Class,T::Types::Base] The type of this
    #   property. If the type is itself a `Document` subclass, this
    #   property will be recursively serialized/deserialized.
    # @param rules [Hash] Options to control this property's behavior.
    # @option rules [T::Boolean,Symbol] :optional If `true`, this property
    #   is never required to be set before an instance is serialized.
    #   If `:on_load` (default), when this property is missing or nil, a
    #   new model cannot be saved, and an existing model can only be
    #   saved if the property was already missing when it was loaded.
    #   If `false`, when the property is missing/nil after deserialization, it
    #   will be set to the default value (as defined by the `default` or
    #   `factory` option) or will raise if they are not present.
    #   Deprecated: For `Model`s, if `:optional` is set to the special value
    #   `:existing`, the property can be saved as nil even if it was
    #   deserialized with a non-nil value. (Deprecated because there should
    #   never be a need for this behavior; the new behavior of non-optional
    #   properties should be sufficient.)
    # @option rules [Array] :enum An array of legal values; The
    #  property is required to take on one of those values.
    # @option rules [T::Boolean] :dont_store If true, this property will
    #   not be saved on the hash resulting from
    #   {T::Props::Serializable#serialize}
    # @option rules [Object] :ifunset A value to be returned if this
    #   property is requested but has never been set (is set to
    #   `nil`). It is applied at property-access time, and never saved
    #   back onto the object or into the database.
    #
    #   ``:ifunset`` is considered **DEPRECATED** and should not be used
    #    in new code, in favor of just setting a default value.
    # @option rules [Model, Symbol, Proc] :foreign A model class that this
    #  property is a reference to. Passing `:foreign` will define a
    #  `:"#{name}_"` method, that will load and return the
    #  corresponding foreign model.
    #
    #  A symbol can be passed to avoid load-order dependencies; It
    #  will be lazily resolved relative to the enclosing module of the
    #  defining class.
    #
    #  A callable (proc or method) can be passed to dynamically specify the
    #  foreign model. This will be passed the object instance so that other
    #  properties of the object can be used to determine the relevant model
    #  class. It should return a string/symbol class name or the foreign model
    #  class directly.
    #
    # @option rules [Object] :default A default value that will be set
    #   by `#initialize` if none is provided in the initialization
    #   hash. This will not affect objects loaded by {.from_hash}.
    # @option rules [Proc] :factory A `Proc` that will be called to
    #   generate an initial value for this prop on `#initialize`, if
    #   none is provided.
    # @option rules [T::Boolean] :immutable If true, this prop cannot be
    #   modified after an instance is created or loaded from a hash.
    # @option rules [T::Boolean] :override It is an error to redeclare a
    #   `prop` that has already been declared (including on a
    #   superclass), unless `:override` is set to `true`.
    # @option rules [Symbol, Array] :redaction A redaction directive that may
    #   be passed to Chalk::Tools::RedactionUtils.redact_with_directive to
    #   sanitize this parameter for display. Will define a
    #   `:"#{name}_redacted"` method, which will return the value in sanitized
    #   form.
    #
    # @return [void]
    sig { params(name: Symbol, cls: T.untyped, rules: T.untyped).void }
    def prop(name, cls, **rules)
      cls = T::Utils.coerce(cls) if !cls.is_a?(Module)
      decorator.prop_defined(name, cls, rules)
    end

    # Validates the value of the specified prop. This method allows the caller to
    #  validate a value for a prop without having to set the data on the instance.
    #  Throws if invalid.
    #
    # @param prop [Symbol]
    # @param val [Object]
    # @return [void]
    def validate_prop_value(prop, val)
      decorator.validate_prop_value(prop, val)
    end

    # Needs to be documented
    def plugin(mod)
      decorator.plugin(mod)
    end

    # Shorthand helper to define a `prop` with `immutable => true`
    sig { params(name: Symbol, cls_or_args: T.untyped, args: T.untyped).void }
    def const(name, cls_or_args, **args)
      if (cls_or_args.is_a?(Hash) && cls_or_args.key?(:immutable)) || args.key?(:immutable)
        Kernel.raise ArgumentError.new("Cannot pass 'immutable' argument when using 'const' keyword to define a prop")
      end

      if cls_or_args.is_a?(Hash)
        self.prop(name, **cls_or_args.merge(immutable: true))
      else
        self.prop(name, cls_or_args, **args.merge(immutable: true))
      end
    end

    def included(child)
      decorator.model_inherited(child)
      super
    end

    def prepended(child)
      decorator.model_inherited(child)
      super
    end

    def extended(child)
      decorator.model_inherited(child.singleton_class)
      super
    end

    def inherited(child)
      decorator.model_inherited(child)
      super
    end
  end
  mixes_in_class_methods(ClassMethods)
end
