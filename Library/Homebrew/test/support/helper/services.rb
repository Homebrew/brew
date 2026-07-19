# typed: strict
# frozen_string_literal: true

require "services/system"
require "services/system/systemctl"

module Test
  module Helper
    # Helpers for the `Homebrew::Services` specs.
    module Services
      # `Homebrew::Services::System.launchctl` and
      # `Homebrew::Services::System::Systemctl.executable` memoize their lookups
      # for the life of the process. Examples that manipulate `PATH` to probe
      # discovery must clear those caches so they don't leak across examples.
      sig { void }
      def reset_services_memoization!
        Homebrew::Services::System.instance_variable_set(:@launchctl, nil)
        Homebrew::Services::System::Systemctl.instance_variable_set(:@executable, nil)
      end
    end
  end
end
