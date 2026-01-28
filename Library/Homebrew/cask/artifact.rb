# typed: strict
# frozen_string_literal: true

require "cask/artifact/app"
require "cask/artifact/artifact" # generic 'artifact' stanza
require "cask/artifact/audio_unit_plugin"
require "cask/artifact/binary"
require "cask/artifact/colorpicker"
require "cask/artifact/dictionary"
require "cask/artifact/font"
require "cask/artifact/input_method"
require "cask/artifact/installer"
require "cask/artifact/internet_plugin"
require "cask/artifact/keyboard_layout"
require "cask/artifact/manpage"
require "cask/artifact/vst_plugin"
require "cask/artifact/vst3_plugin"
require "cask/artifact/pkg"
require "cask/artifact/postflight_block"
require "cask/artifact/preflight_block"
require "cask/artifact/prefpane"
require "cask/artifact/qlplugin"
require "cask/artifact/mdimporter"
require "cask/artifact/screen_saver"
require "cask/artifact/bashcompletion"
require "cask/artifact/fishcompletion"
require "cask/artifact/zshcompletion"
require "cask/artifact/service"
require "cask/artifact/stage_only"
require "cask/artifact/suite"
require "cask/artifact/uninstall"
require "cask/artifact/zap"

module Cask
  # Module containing all cask artifact classes.
  module Artifact
    MACOS_ONLY_ARTIFACTS = [
      ::Cask::Artifact::App,
      ::Cask::Artifact::AudioUnitPlugin,
      ::Cask::Artifact::Colorpicker,
      ::Cask::Artifact::Dictionary,
      ::Cask::Artifact::InputMethod,
      ::Cask::Artifact::InternetPlugin,
      ::Cask::Artifact::KeyboardLayout,
      ::Cask::Artifact::Mdimporter,
      ::Cask::Artifact::Pkg,
      ::Cask::Artifact::Prefpane,
      ::Cask::Artifact::Qlplugin,
      ::Cask::Artifact::ScreenSaver,
      ::Cask::Artifact::Service,
      ::Cask::Artifact::Suite,
      ::Cask::Artifact::VstPlugin,
      ::Cask::Artifact::Vst3Plugin,
    ].freeze
  end
end
