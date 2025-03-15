# typed: true
# frozen_string_literal: true

module Bundle
  module Checker
    class VscodeExtensionChecker < Bundle::Checker::Base
      PACKAGE_TYPE = :vscode
      PACKAGE_TYPE_NAME = "VSCode Extension"

      def failure_reason(extension, no_upgrade:)
        "#{PACKAGE_TYPE_NAME} #{extension} needs to be installed."
      end

      def installed_and_up_to_date?(extension, no_upgrade: false)
        Bundle::VscodeExtensionInstaller.extension_installed?(extension)
      end
    end
  end
end
