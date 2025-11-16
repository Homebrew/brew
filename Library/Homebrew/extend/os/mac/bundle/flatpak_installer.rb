# typed: strict
# frozen_string_literal: true

module OS
  module Mac
    module Bundle
      module FlatpakInstaller
        module ClassMethods
          sig { params(_name: String, verbose: T::Boolean, remote: String, _options: T.untyped).returns(T::Boolean) }
          def preinstall!(_name, verbose: false, remote: "flathub", **_options)
            false
          end
        end
      end
    end
  end
end

Homebrew::Bundle::FlatpakInstaller.singleton_class.prepend(OS::Mac::Bundle::FlatpakInstaller::ClassMethods)
