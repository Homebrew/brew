# typed: strict
# frozen_string_literal: true

require_relative "../../../global"
require "utils/tty"

module Tapioca
  module Compilers
    class Tty < Tapioca::Dsl::Compiler
      ConstantType = type_member { { fixed: Module } }

      sig { override.returns(T::Enumerable[Module]) }
      def self.gather_constants = [::Tty]

      sig { override.void }
      def decorate
        root.create_module(T.must(constant.name)) do |mod|
          dynamic_methods = ::Tty::COLOR_CODES.keys + ::Tty::STYLE_CODES.keys + ::Tty::SPECIAL_CODES.keys

          dynamic_methods.each do |method|
            mod.create_method(method.to_s, return_type: "String", class_method: true)
          end
        end
      end
    end
  end
end
