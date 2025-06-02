# typed: strict
# frozen_string_literal: true

require "method_source"
require "rubocop"
require_relative "../../../rubocops"

module Tapioca
  module Compilers
    class Stanza < Tapioca::Dsl::Compiler
      ConstantType = type_member { { fixed: Module } }

      sig { override.returns(T::Enumerable[Module]) }
      def self.gather_constants = [::RuboCop::Cask::AST::Stanza]

      sig { override.void }
      def decorate
        root.create_module(T.must(constant.name)) do |mod|
          ::RuboCop::Cask::Constants::STANZA_ORDER.each do |stanza|
            mod.create_method("#{stanza}?", return_type: "T::Boolean", class_method: false)
          end
        end
      end
    end
  end
end
