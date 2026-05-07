# typed: strict
# frozen_string_literal: true

require_relative "../../../global"
require "api/formula_struct"
require "api/cask_struct"

module Tapioca
  module Compilers
    class ApiStructs < Tapioca::Dsl::Compiler
      ConstantType = type_member { { fixed: T.class_of(T::Struct) } }

      sig { override.returns(T::Enumerable[T::Module[T.anything]]) }
      def self.gather_constants = [::Homebrew::API::FormulaStruct, ::Homebrew::API::CaskStruct]

      sig { override.void }
      def decorate
        root.create_class(T.must(constant.name)) do |klass|
          constant.const_get(:PREDICATES).each do |predicate_name|
            klass.create_method("#{predicate_name}?", return_type: "T::Boolean")
          end
        end
      end
    end
  end
end
