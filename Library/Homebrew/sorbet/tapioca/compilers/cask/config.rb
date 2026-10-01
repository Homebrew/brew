# typed: strict
# frozen_string_literal: true

require_relative "../../../../global"
require "cask/config"

module Tapioca
  module Compilers
    class CaskConfig < Tapioca::Dsl::Compiler
      ConstantType = type_member { { fixed: T::Module[T.anything] } }

      sig { override.returns(T::Enumerable[T::Module[T.anything]]) }
      def self.gather_constants = [Cask::Config]

      sig { override.void }
      def decorate
        keys = [:languages, *Cask::Config::DEFAULT_DIRS.keys]

        root.create_module("Cask") do |mod|
          mod.create_class("Config") do |klass|
            keys.each do |key|
              return_type = if key == :languages
                # :languages is a `LazyObject`, so it lazily evaluates to an
                # array of strings when a method is called on it.
                "T::Array[String]"
              elsif key.end_with?("?")
                "T::Boolean"
              else
                "Pathname"
              end

              klass.create_method(key.to_s, return_type:, class_method: false)
            end
          end
        end
      end
    end
  end
end
