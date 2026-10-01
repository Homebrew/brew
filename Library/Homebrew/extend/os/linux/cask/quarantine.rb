# typed: strict
# frozen_string_literal: true

module OS
  module Linux
    module Cask
      module Quarantine
        module ClassMethods
          extend T::Helpers

          requires_ancestor { ::Cask::Quarantine }

          sig { returns(T::Boolean) }
          def available? = false
        end
      end
    end
  end
end

Cask::Quarantine.singleton_class.prepend(OS::Linux::Cask::Quarantine::ClassMethods)
