# typed: strict
# frozen_string_literal: true

module Homebrew
  module Bundle
    module Checker
      class VscodeExtensionChecker < Homebrew::Bundle::Checker::Base
        PACKAGE_TYPE = :vscode
        PACKAGE_TYPE_NAME = "VSCode Extension"

        sig { params(extension: String, no_upgrade: T::Boolean).returns(String) }
        def failure_reason(extension, no_upgrade:)
          "#{PACKAGE_TYPE_NAME} #{extension} needs to be installed."
        end

        sig { params(extension: String, no_upgrade: T::Boolean).returns(T::Boolean) }
        def installed_and_up_to_date?(extension, no_upgrade: false)
          require "bundle/vscode_extension_installer"
          Homebrew::Bundle::VscodeExtensionInstaller.extension_installed?(extension)
        end
      end
    end
  end
end
