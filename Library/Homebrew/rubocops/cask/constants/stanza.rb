# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cask
    # Constants available globally for use in all cask cops.
    module Constants
      on_system_methods = [:arm, :intel, *MacOSVersion::SYMBOLS.keys, :macos, :linux].map do |option|
        :"on_#{option}"
      end
      ON_SYSTEM_METHODS = T.let(on_system_methods.freeze, T::Array[Symbol])
      on_system_methods_stanza_order = [
        :arm,
        :intel,
        *MacOSVersion::SYMBOLS.reverse_each.to_h.keys, # Oldest OS blocks first since that's more common in Casks.
        :macos,
        :linux,
      ].map { |option, _| :"on_#{option}" }
      ON_SYSTEM_METHODS_STANZA_ORDER = T.let(on_system_methods_stanza_order.freeze, T::Array[Symbol])
      SHA256_ARCH_ORDER = [:arm, :intel, :x86_64, :arm64_linux, :x86_64_linux].freeze

      STANZA_GROUPS = T.let(
        [
          [:arch, :on_arch_conditional, :os, :on_system_conditional],
          [:version, :sha256],
          ON_SYSTEM_METHODS_STANZA_ORDER,
          [:language],
          [:url, :appcast, :name, :desc, :homepage],
          [:livecheck],
          [:no_autobump!],
          [:deprecate!, :disable!],
          [
            :auto_updates,
            :conflicts_with,
            :depends_on,
            :container,
          ],
          [
            :rename,
          ],
          [
            :suite,
            :app,
            :app_image,
            :desktop_entry,
            :pkg,
            :generated_script,
            :installer,
            :binary,
            :command_wrapper,
            :manpage,
            :bash_completion,
            :zsh_completion,
            :fish_completion,
            :pwsh_completion,
            :generate_completions_from_executable,
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
          [:preflight_steps, :preflight],
          [:postflight_steps, :postflight],
          [:uninstall_preflight_steps, :uninstall_preflight],
          [:uninstall_postflight_steps, :uninstall_postflight],
          [:uninstall],
          [:zap],
          [:caveats],
        ].freeze,
        T::Array[T::Array[Symbol]],
      )

      stanza_group_hash = STANZA_GROUPS.each_with_object({}) do |stanza_group, hash|
        stanza_group.each { |stanza| hash[stanza] = stanza_group }
      end
      STANZA_GROUP_HASH = T.let(stanza_group_hash.freeze, T::Hash[Symbol, T::Array[Symbol]])

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
