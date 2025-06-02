# frozen_string_literal: true

module RBS
  module BuiltinNames
    class Name
      attr_reader :name

      def initialize(name:)
        @name = name
      end

      def to_s
        name.to_s
      end

      def instance_type(*args)
        Types::ClassInstance.new(name: name, args: args, location: nil)
      end

      def instance_type?(type)
        type.is_a?(Types::ClassInstance) && type.name == name
      end

      def singleton_type
        @singleton_type ||= Types::ClassSingleton.new(name: name, location: nil)
      end

      def singleton_type?(type)
        type.is_a?(Types::ClassSingleton) && type.name == name
      end

      def self.define(name, namespace: Namespace.root)
        new(name: TypeName.new(name: name, namespace: namespace))
      end
    end

    BasicObject = Name.new(name: TypeName.new(name: :BasicObject, namespace: Namespace.root))
    Object = Name.new(name: TypeName.new(name: :Object, namespace: Namespace.root))
    Kernel = Name.new(name: TypeName.new(name: :Kernel, namespace: Namespace.root))
    String = Name.define(:String)
    Comparable = Name.define(:Comparable)
    Enumerable = Name.define(:Enumerable)
    Class = Name.define(:Class)
    Module = Name.define(:Module)
    Array = Name.define(:Array)
    Hash = Name.define(:Hash)
    Range = Name.define(:Range)
    Enumerator = Name.define(:Enumerator)
    Set = Name.define(:Set)
    Symbol = Name.define(:Symbol)
    Integer = Name.define(:Integer)
    Float = Name.define(:Float)
    Regexp = Name.define(:Regexp)
    TrueClass = Name.define(:TrueClass)
    FalseClass = Name.define(:FalseClass)
    Numeric = Name.define(:Numeric)
  end
end
