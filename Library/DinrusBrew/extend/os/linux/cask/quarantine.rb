# typed: strict
# frozen_string_literal: true

module OS
  module Linux
    module Cask
      module Quarantine
        extend T::Helpers

        requires_ancestor { ::Cask::Quarantine }

        sig { returns(Symbol) }
        def self.check_quarantine_support = :linux

        sig { returns(T::Boolean) }
        def self.available? = false
      end
    end
  end
end

Cask::Quarantine.prepend(OS::Linux::Cask::Quarantine)
