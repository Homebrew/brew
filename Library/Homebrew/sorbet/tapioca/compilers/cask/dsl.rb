# typed: strict
# frozen_string_literal: true

require_relative "../../../../global"
require "cask/cask"

module Tapioca
  module Compilers
    class CaskDsl < Tapioca::Dsl::Compiler
      ConstantType = type_member { { fixed: T::Module[T.anything] } }

      sig { override.returns(T::Enumerable[T::Module[T.anything]]) }
      def self.gather_constants = [Cask::DSL]

      sig { override.void }
      def decorate
        root.create_path(constant) do |klass|
          Cask::DSL::ORDINARY_ARTIFACT_CLASSES.each do |artifact|
            klass.create_method(
              artifact.dsl_key.to_s,
              parameters:  [
                create_rest_param("args", type: "T.anything"),
                create_kw_rest_param("kwargs", type: "T.anything"),
              ],
              return_type: "void",
            )
          end

          Cask::DSL::ARTIFACT_BLOCK_CLASSES.each do |artifact|
            [artifact.dsl_key, artifact.uninstall_dsl_key].each do |dsl_key|
              dsl_class = artifact.class_for_dsl_key(dsl_key).to_s
              klass.create_method(
                dsl_key.to_s,
                parameters:  [create_block_param("block", type: block_type(dsl_class))],
                return_type: "void",
              )
            end
          end

          Cask::DSL::INSTALL_STEP_ARTIFACT_CLASSES.each do |artifact|
            klass.create_method(
              artifact.dsl_key.to_s,
              parameters:  [
                create_opt_param("steps", type: "T.anything", default: "nil"),
                create_kw_rest_param("kwargs", type: "T.anything"),
                create_block_param("block", type: block_type("Homebrew::InstallSteps::DSL")),
              ],
              return_type: "void",
            )
          end
        end
      end

      private

      sig { params(dsl_class: String).returns(String) }
      def block_type(dsl_class)
        "T.nilable(T.proc.bind(#{dsl_class}).params(dsl: #{dsl_class}).void)"
      end
    end
  end
end
