# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cask
    # Constants available globally for use in all cask cops.
    module Constants
      ON_SYSTEM_METHODS = T.let(
        [:arm, :intel, *MacOSVersion::SYMBOLS.keys].map { |option| :"on_#{option}" }.freeze,
        T::Array[Symbol],
      )
      ON_SYSTEM_METHODS_STANZA_ORDER = T.let(
        [
          :arm,
          :intel,
          *MacOSVersion::SYMBOLS.reverse_each.to_h.keys, # Oldest OS blocks first since that's more common in Casks.
        ].map { |option, _| :"on_#{option}" }.freeze,
        T::Array[Symbol],
      )

      STANZA_GROUPS = T.let(
        [
          [:arch, :on_arch_conditional],
          [:version, :sha256],
          ON_SYSTEM_METHODS_STANZA_ORDER,
          [:language],
          [:url, :appcast, :name, :desc, :homepage],
          [:livecheck],
          [:deprecate!, :disable!],
          [
            :auto_updates,
            :conflicts_with,
            :depends_on,
            :container,
          ],
          [
            :suite,
            :app,
            :pkg,
            :installer,
            :binary,
            :manpage,
            :colorpicker,
            :dictionary,
            :font,
            :input_method,
            :internet_plugin,
            :keyboard_layout,
            :prefpane,
            :qlplugin,
            :mdimporter,
            :screen_saver,
            :service,
            :audio_unit_plugin,
            :vst_plugin,
            :vst3_plugin,
            :artifact,
            :stage_only,
          ],
          [:preflight],
          [:postflight],
          [:uninstall_preflight],
          [:uninstall_postflight],
          [:uninstall],
          [:zap],
          [:caveats],
        ].freeze,
        T::Array[T::Array[Symbol]],
      )

      STANZA_GROUP_HASH = T.let(
        STANZA_GROUPS.each_with_object({}) do |stanza_group, hash|
          stanza_group.each { |stanza| hash[stanza] = stanza_group }
        end.freeze,
        T::Hash[Symbol, T::Array[Symbol]],
      )

      STANZA_ORDER = T.let(STANZA_GROUPS.flatten.freeze, T::Array[Symbol])

      UNINSTALL_METHODS_ORDER = [
        :early_script,
        :launchctl,
        :quit,
        :signal,
        :login_item,
        :kext,
        :script,
        :pkgutil,
        :delete,
        :trash,
        :rmdir,
      ].freeze
    end
  end
end
