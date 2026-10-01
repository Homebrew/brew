# typed: strict
# frozen_string_literal: true

require "os/mac"

module OS
  module Mac
    module Cask
      module Config
        module ClassMethods
          T::Sig::WithoutRuntime.sig { returns(::Cask::Config::ConfigHash) }
          def defaults
            {
              languages: LazyObject.new { Mac.languages },
            }.merge(::Cask::Config::DEFAULT_DIRS).freeze
          end
        end
      end
    end
  end
end

Cask::Config.singleton_class.prepend(OS::Mac::Cask::Config::ClassMethods)
