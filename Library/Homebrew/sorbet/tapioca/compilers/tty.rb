# typed: strict
# frozen_string_literal: true

require_relative "../../../global"
require "utils/tty"

module Tapioca
  module Compilers
    class Tty < Tapioca::Dsl::Compiler
      ConstantType = type_member { { fixed: T::Module[T.anything] } }

      sig { override.returns(T::Enumerable[T::Module[T.anything]]) }
      def self.gather_constants = [::Tty]

      sig { override.void }
      def decorate
        # `create_path` would use the overridden `Tty.to_s` (the escape codes) as the module name.
        name = constant.name
        raise ArgumentError, "Cannot generate an RBI for anonymous module #{constant.inspect}" if name.nil?

        root.create_module(name) do |mod|
          dynamic_methods = ::Tty::COLOR_CODES.keys + ::Tty::STYLE_CODES.keys + ::Tty::SPECIAL_CODES.keys

          dynamic_methods.each do |method|
            mod.create_method(method.to_s, return_type: "String", class_method: true)
          end
        end
      end
    end
  end
end
