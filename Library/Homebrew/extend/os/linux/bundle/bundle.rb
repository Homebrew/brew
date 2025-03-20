# typed: strict
# frozen_string_literal: true

module OS
  module Linux
    module Bundle
      module ClassMethods
        sig { returns(T::Boolean) }
        def mas_installed?
          false
        end
      end
    end
  end
end

Homebrew::Bundle.singleton_class.prepend(OS::Linux::Bundle::ClassMethods)
