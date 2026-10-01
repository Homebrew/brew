# typed: strict
# frozen_string_literal: true

require "cask/cask"
require "formula"
require "on_system"
require "resource"

module Tapioca
  module Compilers
    class OnSystem < Tapioca::Dsl::Compiler
      ConstantType = type_member { { fixed: T::Module[T.anything] } }

      sig { override.returns(T::Enumerable[T::Module[T.anything]]) }
      def self.gather_constants
        [Cask::DSL, Formula, Resource]
      end

      sig { override.void }
      def decorate
        root.create_path(constant) do |scope|
          create_on_system_methods(scope, class_method: false)
          create_on_system_methods(scope, class_method: true) if constant == Formula
        end
      end

      private

      sig { params(scope: RBI::Scope, class_method: T::Boolean).void }
      def create_on_system_methods(scope, class_method:)
        (::OnSystem::ARCH_OPTIONS + ::OnSystem::BASE_OS_OPTIONS).each do |option|
          scope.create_method(
            "on_#{option}",
            parameters:   [
              create_block_param(
                "block",
                type: "T.proc.returns(T.type_parameter(:U))",
              ),
            ],
            return_type:  "T.nilable(T.type_parameter(:U))",
            class_method:,
          )
        end

        ::MacOSVersion::SYMBOLS.each_key do |version|
          scope.create_method(
            "on_#{version}",
            parameters:   [
              create_opt_param("or_condition", type: "T.nilable(Symbol)", default: "nil"),
              create_block_param(
                "block",
                type: "T.proc.returns(T.type_parameter(:U))",
              ),
            ],
            return_type:  "T.nilable(T.type_parameter(:U))",
            class_method:,
          )
        end

        scope.create_method(
          "on_system",
          parameters:   [
            create_param("linux", type: "Symbol"),
            create_kw_param("macos", type: "Symbol"),
            create_block_param(
              "block",
              type: "T.proc.returns(T.type_parameter(:U))",
            ),
          ],
          return_type:  "T.nilable(T.type_parameter(:U))",
          class_method:,
        )

        scope.create_method(
          "on_arch_conditional",
          parameters:   [
            create_kw_opt_param("arm", type: "T.nilable(T.type_parameter(:U))", default: "nil"),
            create_kw_opt_param("intel", type: "T.nilable(T.type_parameter(:U))", default: "nil"),
          ],
          return_type:  "T.nilable(T.type_parameter(:U))",
          class_method:,
        )

        scope.create_method(
          "on_system_conditional",
          parameters:   [
            create_kw_opt_param("macos", type: "T.nilable(T.type_parameter(:U))", default: "nil"),
            create_kw_opt_param("linux", type: "T.nilable(T.type_parameter(:U))", default: "nil"),
          ],
          return_type:  "T.nilable(T.type_parameter(:U))",
          class_method:,
        )
      end
    end
  end
end
