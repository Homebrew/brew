# typed: strict
# frozen_string_literal: true

module OS
  module Mac
    module Bundle
      module FlatpakDumper
        module ClassMethods
          sig { returns(T::Array[T::Hash[Symbol, String]]) }
          def packages_with_remotes
            []
          end
        end
      end
    end
  end
end

Homebrew::Bundle::FlatpakDumper.singleton_class.prepend(OS::Mac::Bundle::FlatpakDumper::ClassMethods)
