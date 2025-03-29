# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "bundle/cask_installer"

module Homebrew
  module Bundle
    module Checker
      class CaskChecker < Homebrew::Bundle::Checker::Base
        PACKAGE_TYPE = :cask
        PACKAGE_TYPE_NAME = "Cask"

        def installed_and_up_to_date?(cask, no_upgrade: false)
          Homebrew::Bundle::CaskInstaller.cask_installed_and_up_to_date?(cask, no_upgrade:)
        end
      end
    end
  end
end
