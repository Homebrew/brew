# typed: strict
# frozen_string_literal: true

require "rubocop"
require_relative "../../../rubocops"

module Tapioca
  module Compilers
    class Stanza < Tapioca::Dsl::Compiler
      ConstantType = type_member { { fixed: T::Module[T.anything] } }

      sig { override.returns(T::Enumerable[T::Module[T.anything]]) }
      def self.gather_constants = [::RuboCop::Cask::AST::Stanza]

      sig { override.void }
      def decorate
        name = constant.name
        raise ArgumentError, "Cannot generate an RBI for anonymous module #{constant.inspect}" if name.nil?

        root.create_module(name) do |mod|
          ::RuboCop::Cask::Constants::STANZA_ORDER.each do |stanza|
            mod.create_method("#{stanza}?", return_type: "T::Boolean", class_method: false)
          end
        end
      end
    end
  end
end
