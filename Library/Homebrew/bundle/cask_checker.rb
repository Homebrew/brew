# typed: strict
# frozen_string_literal: true

require "bundle/cask_installer"

module Homebrew
  module Bundle
    module Checker
      class CaskChecker < Homebrew::Bundle::Checker::Base
        PACKAGE_TYPE = :cask
        PACKAGE_TYPE_NAME = "Cask"

        sig { params(cask: String, no_upgrade: T::Boolean).returns(T::Boolean) }
        def installed_and_up_to_date?(cask, no_upgrade: false)
          Homebrew::Bundle::CaskInstaller.cask_installed_and_up_to_date?(cask, no_upgrade:)
        end
      end
    end
  end
end
