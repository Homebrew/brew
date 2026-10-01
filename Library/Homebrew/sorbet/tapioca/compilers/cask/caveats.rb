# typed: strict
# frozen_string_literal: true

require_relative "../../../../global"
require "cask/cask"

module Tapioca
  module Compilers
    class CaskCaveats < Tapioca::Dsl::Compiler
      ConstantType = type_member { { fixed: T::Module[T.anything] } }

      sig { override.returns(T::Enumerable[T::Module[T.anything]]) }
      def self.gather_constants = [Cask::DSL::Caveats]

      sig { override.void }
      def decorate
        root.create_path(constant) do |klass|
          Cask::DSL::Caveats.caveat_names.each do |name|
            klass.create_method(
              name.to_s,
              parameters:  [create_rest_param("args", type: "T.anything")],
              return_type: "Symbol",
            )
          end
        end
      end
    end
  end
end
