# typed: strict
# frozen_string_literal: true

require "cask/macos"

module OS
  module Mac
    module Cask
      module Config
        extend T::Helpers

        requires_ancestor { ::Cask::Config }

        DEFAULT_DIRS = T.let(
          {
            appdir:               "/Applications",
            keyboard_layoutdir:   "/Library/Keyboard Layouts",
            colorpickerdir:       "~/Library/ColorPickers",
            prefpanedir:          "~/Library/PreferencePanes",
            qlplugindir:          "~/Library/QuickLook",
            mdimporterdir:        "~/Library/Spotlight",
            dictionarydir:        "~/Library/Dictionaries",
            fontdir:              "~/Library/Fonts",
            servicedir:           "~/Library/Services",
            input_methoddir:      "~/Library/Input Methods",
            internet_plugindir:   "~/Library/Internet Plug-Ins",
            audio_unit_plugindir: "~/Library/Audio/Plug-Ins/Components",
            vst_plugindir:        "~/Library/Audio/Plug-Ins/VST",
            vst3_plugindir:       "~/Library/Audio/Plug-Ins/VST3",
            screen_saverdir:      "~/Library/Screen Savers",
          }.freeze,
          T::Hash[Symbol, String],
        )

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def self.defaults
          {
            languages: LazyObject.new { ::OS::Mac.languages },
          }.merge(DEFAULT_DIRS).freeze
        end
      end
    end
  end
end

Cask::Config.prepend(OS::Mac::Cask::Config)
