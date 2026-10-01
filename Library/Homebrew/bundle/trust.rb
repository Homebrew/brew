# typed: strict
# frozen_string_literal: true

require "bundle/dsl"
require "trust"
require "utils"

module Homebrew
  module Bundle
    # Converts Brewfile `trusted` options into trust-store entries.
    module Trust
      TRUSTED_ITEM_KEYS = T.let({
        formula: [:formula, :formulae],
        cask:    [:cask, :casks],
        command: [:command, :commands],
      }.freeze, T::Hash[Symbol, T::Array[Symbol]])
      private_constant :TRUSTED_ITEM_KEYS

      sig { params(entries: T::Array[Homebrew::Bundle::Dsl::Entry]).returns(T::Array[[Symbol, String]]) }
      def self.entries(entries)
        # Resolve every item through `Homebrew::Trust.target`, the same canonicalizer `brew trust`
        # uses, so bundle does not write a second, divergent entry for a custom-remote tap. A
        # `brew`/`cask` entry takes its remote from the matching `tap` entry, which can appear later
        # in the Brewfile, so map each tap name to its declared remote first.
        tap_remotes = entries.filter_map do |entry|
          next if entry.type != :tap

          clone_target = entry.options[:clone_target].presence
          [entry.name.downcase, clone_target.to_s] if clone_target
        end.to_h

        entries.flat_map do |entry|
          trusted = entry.options[:trusted]
          next [] if trusted.blank?

          targets = T.let([], T::Array[[Symbol, String, T.nilable(String)]])
          case entry.type
          when :tap
            tap_remote = entry.options[:clone_target].presence&.to_s
            if trusted == true
              targets << [:tap, entry.name, tap_remote]
            elsif trusted.is_a?(Hash)
              unsupported_keys = trusted.keys - TRUSTED_ITEM_KEYS.values.flatten
              if unsupported_keys.present?
                raise UsageError,
                      "Unsupported trusted keys: #{unsupported_keys.join(", ")}"
              end

              TRUSTED_ITEM_KEYS.each do |type, keys|
                keys.each do |key|
                  Array(trusted[key]).each do |item|
                    item_name = case item
                    when String, Symbol, Integer
                      Utils.name_from_full_name(item.to_s)
                    end
                    next if item_name.blank?

                    targets << [type, "#{entry.name}/#{item_name}", tap_remote]
                  end
                end
              end
            end
          when :brew, :cask
            full_name = T.cast(entry.options.fetch(:full_name, entry.name), String)
            next [] if trusted != true
            # Only fully-qualified names map to a tap, so unqualified names cannot be trusted.
            next [] unless Utils.full_name?(full_name)

            type = (entry.type == :brew) ? :formula : :cask
            tap_name = Utils.tap_from_full_name(full_name)
            canonical_tap_name = Dsl.sanitize_tap_name(tap_name) if tap_name
            tap_remote = tap_remotes[canonical_tap_name] if canonical_tap_name
            targets << [type, full_name, tap_remote]
          end

          targets.map { |type, name, tap_remote| Homebrew::Trust.target(name, type:, tap_remote:) }
        end.uniq
      end
    end
  end
end
