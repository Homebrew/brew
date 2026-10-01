# typed: strict
# frozen_string_literal: true

require "api/formula_struct"
require "bottle"
require "bottle_specification"
require "pkg_version"

module Homebrew
  module API
    module FormulaBottle
      sig {
        params(
          name:           String,
          formula_struct: Homebrew::API::FormulaStruct,
          bottle_tag:     Utils::Bottles::Tag,
          formula:        T.nilable(::Formula),
        ).returns(T.nilable(::Bottle))
      }
      def self.bottle(name:, formula_struct:, bottle_tag: Utils::Bottles.tag, formula: nil)
        return unless formula_struct.stable?
        return unless formula_struct.bottle?

        bottle_specification = BottleSpecification.new
        bottle_specification.root_url(
          if Homebrew::EnvConfig.bottle_domain_custom?
            Homebrew::EnvConfig.bottle_domain
          else
            HOMEBREW_BOTTLE_DEFAULT_DOMAIN
          end,
        )
        bottle_specification.rebuild(formula_struct.bottle_rebuild)
        formula_struct.bottle_checksums.each { |args| bottle_specification.sha256(args) }

        return unless bottle_specification.tag?(bottle_tag)

        if formula
          ::Bottle.new(formula, bottle_specification, bottle_tag)
        else
          ::Bottle.new(
            nil,
            bottle_specification,
            bottle_tag,
            name:,
            pkg_version: PkgVersion.new(::Version.new(formula_struct.stable_version), formula_struct.revision),
          )
        end
      end
    end
  end
end
