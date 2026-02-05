# typed: strict
# frozen_string_literal: true

module Homebrew
  module Tapioca
    module Utils
      sig { params(klass: T::Class[T.anything]).returns(T::Module[T.anything]) }
      def self.named_object_for(klass)
        return klass if klass.name

        attached_object = klass.attached_object
        case attached_object
        when Module then attached_object
        else raise "Unsupported attached object for: #{klass}"
        end
      end

      # @param class_methods [Boolean] whether to get class methods or instance methods
      # @return the `module` methods that are defined in the given file
      sig {
        params(mod: T::Module[T.anything], file_name: String,
               class_methods: T::Boolean).returns(T::Array[T.any(Method, UnboundMethod)])
      }
      def self.methods_from_file(mod, file_name, class_methods: false)
        methods = if class_methods
          mod.methods(false).map { mod.method(it) }
        else
          mod.instance_methods(false).map { mod.instance_method(it) }
        end
        methods.select { it.source_location&.first&.end_with?(file_name) }
      end

      sig { params(mod: T::Module[T.anything]).returns(T::Array[T::Module[T.anything]]) }
      def self.named_objects_with_module(mod)
        ObjectSpace.each_object(mod).map do |obj|
          case obj
          when Class then named_object_for(obj)
          when Module then obj
          else raise "Unsupported object: #{obj}"
          end
        end.uniq
      end
    end
  end
end
