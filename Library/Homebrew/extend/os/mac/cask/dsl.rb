# typed: strict
# frozen_string_literal: true

require "cask/macos"

module OS
  module Mac
    module Cask
      module DSL
        extend T::Helpers

        requires_ancestor { ::Cask::DSL }

        sig { returns(T.nilable(MacOSVersion)) }
        def os_version
          MacOS.full_version
        end
      end
    end
  end
end

Cask::DSL.prepend(OS::Mac::Cask::DSL)
