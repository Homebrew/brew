# typed: strict
# frozen_string_literal: true

require_relative "../../../global"
require "cask/url"

module Tapioca
  module Compilers
    # A compiler for subclasses of Delegator.
    # To add a new delegator: require it above and add it to the DELEGATIONS hash below.
    class Delegators < Tapioca::Dsl::Compiler
      # Mapping of delegator classes to the classes they delegate to (as defined in `__getobj__`).
      DELEGATIONS = T.let({
        Cask::URL => Cask::URL::DSL,
      }.freeze, T::Hash[Module, Module])
      ConstantType = type_member { { fixed: Module } }

      sig { override.returns(T::Enumerable[Module]) }
      def self.gather_constants = DELEGATIONS.keys

      sig { override.void }
      def decorate
        root.create_path(constant) do |klass|
          # Note that `Delegtor` does not subclass `Object`:
          #   https://github.com/ruby/ruby/blob/a6383fb/lib/delegate.rb#L41
          # but we assume that we are delegating to a class that does.
          klass.create_include("Kernel")
          delegated = DELEGATIONS.fetch(constant)

          delegated.instance_methods(false).each do |method|
            signature = T::Utils.signature_for_method(delegated.instance_method(method))
            # TODO: handle methods with parameters
            return_type = signature&.return_type&.to_s || "T.untyped"
            klass.create_method(method.to_s, return_type:)
          end
        end
      end
    end
  end
end
