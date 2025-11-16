# typed: strict
# frozen_string_literal: true

module OS
  module Mac
    module Bundle
      module FlatpakRemoteDumper
        module ClassMethods
          sig { returns(T::Array[T::Hash[Symbol, String]]) }
          def remotes
            []
          end
        end
      end
    end
  end
end

Homebrew::Bundle::FlatpakRemoteDumper.singleton_class.prepend(OS::Mac::Bundle::FlatpakRemoteDumper::ClassMethods)
