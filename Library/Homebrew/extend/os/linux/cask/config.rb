# typed: strict
# frozen_string_literal: true

require "os/linux"

module OS
  module Linux
    module Cask
      module Config
        module ClassMethods
          DEFAULT_DIRS = T.let({
            vst_plugindir:  "~/.vst",
            vst3_plugindir: "~/.vst3",
            fontdir:        "#{ENV.fetch("XDG_DATA_HOME", "~/.local/share")}/fonts",
            appdir:         "~/.config/apps",
          }.freeze, T::Hash[Symbol, String])

          sig { returns(T::Hash[Symbol, String]) }
          def defaults
            {
              languages: LazyObject.new { Linux.languages },
            }.merge(DEFAULT_DIRS).freeze
          end
        end
      end
    end
  end
end

Cask::Config.singleton_class.prepend(OS::Linux::Cask::Config::ClassMethods)
