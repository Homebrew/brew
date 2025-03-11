# typed: strict
# frozen_string_literal: true

module Utils
  module Bottles
    class << self
      module LinuxOverride
        # Linux implementation stays with the default
        sig { returns(T::Boolean) }
        def on_macos?
          false
        end
      end

      prepend LinuxOverride
    end
  end
end
