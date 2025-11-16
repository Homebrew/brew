# typed: strict
# frozen_string_literal: true

module OS
  module Mac
    module Bundle
      module FlatpakRemoteInstaller
        module ClassMethods
          sig { params(_name: String, verbose: T::Boolean, _options: T.untyped).returns(T::Boolean) }
          def preinstall!(_name, verbose: false, **_options)
            false
          end
        end
      end
    end
  end
end

Homebrew::Bundle::FlatpakRemoteInstaller.singleton_class.prepend(OS::Mac::Bundle::FlatpakRemoteInstaller::ClassMethods)
