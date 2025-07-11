# frozen_string_literal: true
# typed: strict

module T::Props
  module CustomType
    extend T::Sig
    extend T::Helpers

    abstract!

    include Kernel # for `is_a?`

    # Alias for backwards compatibility
    sig(:final) do
      params(
        value: BasicObject,
      )
      .returns(T::Boolean)
      .checked(:never)
    end
    def instance?(value)
      self.===(value)
    end

    # Alias for backwards compatibility
    sig(:final) do
      params(
        value: BasicObject,
      )
      .returns(T::Boolean)
      .checked(:never)
    end
    def valid?(value)
      instance?(value)
    end

    # Given an instance of this type, serialize that into a scalar type
    # supported by T::Props.
    #
    # @param [Object] instance
    # @return An instance of one of T::Configuration.scalar_types
    sig { abstract.params(instance: T.untyped).returns(T.untyped).checked(:never) }
    def serialize(instance); end

    # Given the serialized form of your type, this returns an instance
    # of that custom type representing that value.
    #
    # @param scalar One of T::Configuration.scalar_types
    # @return Object
    sig { abstract.params(scalar: T.untyped).returns(T.untyped).checked(:never) }
    def deserialize(scalar); end

    sig { override.params(_base: Module).void }
    def self.included(_base)
      super

      raise 'Please use "extend", not "include" to attach this module'
    end

    sig(:final) { params(val: T.untyped).returns(T::Boolean).checked(:never) }
    def self.scalar_type?(val)
      # We don't need to check for val's included modules in
      # T::Configuration.scalar_types, because T::Configuration.scalar_types
      # are all classes.
      klass = val.class
      until klass.nil?
        return true if T::Configuration.scalar_types.include?(klass.to_s)
        klass = klass.superclass
      end
      false
    end

    # We allow custom types to serialize to Arrays, so that we can
    # implement set-like fields that store a unique-array, but forbid
    # hashes; Custom hash types should be implemented via an emebdded
    # T::Struct (or a subclass like Chalk::ODM::Document) or via T.
    sig(:final) { params(val: Object).returns(T::Boolean).checked(:never) }
    def self.valid_serialization?(val)
      case val
      when Array
        val.each do |v|
          return false unless scalar_type?(v)
        end

        true
      else
        scalar_type?(val)
      end
    end

    sig(:final) do
      params(instance: Object)
      .returns(T.untyped)
      .checked(:never)
    end
    def self.checked_serialize(instance)
      val = T.cast(instance.class, T::Props::CustomType).serialize(instance)
      unless valid_serialization?(val)
        msg = "#{instance.class} did not serialize to a valid scalar type. It became a: #{val.class}"
        if val.is_a?(Hash)
          msg += "\nIf you want to store a structured Hash, consider using a T::Struct as your type."
        end
        raise TypeError.new(msg)
      end
      val
    end
  end
end
