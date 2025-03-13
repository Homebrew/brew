# typed: true
# frozen_string_literal: true

module Bundle
  module Checker
    class BrewChecker < Bundle::Checker::Base
      PACKAGE_TYPE = :brew
      PACKAGE_TYPE_NAME = "Formula"

      def installed_and_up_to_date?(formula, no_upgrade: false)
        Bundle::BrewInstaller.formula_installed_and_up_to_date?(formula, no_upgrade:)
      end
    end
  end
end
