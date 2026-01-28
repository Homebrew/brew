# typed: strict
# frozen_string_literal: true

module Homebrew
  module Bundle
    module Checker
      class GoChecker < Homebrew::Bundle::Checker::Base
        PACKAGE_TYPE = :go
        PACKAGE_TYPE_NAME = "Go Package"

        sig { params(package: String, no_upgrade: T::Boolean).returns(String) }
        def failure_reason(package, no_upgrade:)
          "#{PACKAGE_TYPE_NAME} #{package} needs to be installed."
        end

        sig { params(package: String, no_upgrade: T::Boolean).returns(T::Boolean) }
        def installed_and_up_to_date?(package, no_upgrade: false)
          require "bundle/go_installer"
          Homebrew::Bundle::GoInstaller.package_installed?(package)
        end
      end
    end
  end
end
