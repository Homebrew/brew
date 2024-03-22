# typed: strict
# frozen_string_literal: true

require_relative "../../../global"
require_relative "../../../utils/tty"

module Tapioca
  module Compilers
    class Tty < Tapioca::Dsl::Compiler
      # FIXME: Enable cop again when https://github.com/sorbet/sorbet/issues/3532 is fixed.
      # rubocop:disable Style/MutableConstant
      # This should be a module whose singleton class contains RuboCop::AST::NodePattern::Macros,
      #   but I don't know how to express that in Sorbet.
      ConstantType = type_member { { fixed: Module } }
      # rubocop:enable Style/MutableConstant

      sig { override.returns(T::Enumerable[Module]) }
      def self.gather_constants
        [::Tty]
      end

      sig { override.void }
      def decorate
        root.create_module(constant.name) do |mod|
          dynamic_methods = ::Tty::COLOR_CODES.keys + ::Tty::STYLE_CODES.keys + ::Tty::SPECIAL_CODES.keys
          methods = ::Tty.methods(false).sort.select { |method| dynamic_methods.include?(method) }

          methods.each do |method|
            return_type = (method.to_s.end_with?("?") ? "T::Boolean" : "String")
            mod.create_method(method.to_s, return_type:)
          end
        end
      end
    end
  end
end
