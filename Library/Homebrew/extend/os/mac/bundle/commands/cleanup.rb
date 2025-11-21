# typed: strict
# frozen_string_literal: true

module OS
  module Mac
    module Bundle
      module Commands
        module Cleanup
          module ClassMethods
            sig { params(global: T::Boolean, file: T.nilable(String)).returns(T::Array[String]) }
            def flatpaks_to_uninstall(global: false, file: nil)
              [].freeze
            end

            sig { params(global: T::Boolean, file: T.nilable(String)).returns(T::Array[String]) }
            def flatpak_remotes_to_remove(global: false, file: nil)
              [].freeze
            end
          end
        end
      end
    end
  end
end

Homebrew::Bundle::Commands::Cleanup.singleton_class.prepend(OS::Mac::Bundle::Commands::Cleanup::ClassMethods)
