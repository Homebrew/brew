# typed: strict
# frozen_string_literal: true

require "system_command"
require "utils/shell"

module Utils
  module Browser
    module_function

    sig { params(args: T.any(String, Pathname)).void }
    def open(*args)
      browser = Homebrew::EnvConfig.browser
      browser ||= OS::PATH_OPEN if defined?(OS::PATH_OPEN)
      return unless browser

      ENV["DISPLAY"] = Homebrew::EnvConfig.display

      Utils::Shell.with_env(DBUS_SESSION_BUS_ADDRESS: ENV.fetch("HOMEBREW_DBUS_SESSION_BUS_ADDRESS", nil)) do
        SystemCommand.safe_system(browser, *args)
      end
    end
  end
end
