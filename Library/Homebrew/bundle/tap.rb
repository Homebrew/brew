# typed: strict
# frozen_string_literal: true

require "json"
require "bundle/package_type"
require "trust"

module Homebrew
  module Bundle
    class Tap < Homebrew::Bundle::PackageType
      class << self
        sig { override.returns(Symbol) }
        def type = :tap

        sig { override.returns(String) }
        def check_label = "Tap"

        sig { override.void }
        def reset!
          @taps = T.let(nil, T.nilable(T::Array[::Tap]))
          @installed_taps = T.let(nil, T.nilable(T::Array[String]))
        end

        sig {
          override.params(
            name:       String,
            no_upgrade: T::Boolean,
            verbose:    T::Boolean,
            _options:   Homebrew::Bundle::EntryOption,
          ).returns(T::Boolean)
        }
        def preinstall!(name, no_upgrade: false, verbose: false, **_options)
          _ = no_upgrade

          if installed_taps.include? name
            puts "Skipping install of #{name} tap. It is already installed." if verbose
            return false
          end

          true
        end

        sig {
          override.params(
            name:         String,
            preinstall:   T::Boolean,
            no_upgrade:   T::Boolean,
            verbose:      T::Boolean,
            force:        T::Boolean,
            clone_target: T.nilable(String),
            _options:     Homebrew::Bundle::EntryOption,
          ).returns(T::Boolean)
        }
        def install!(name, preinstall: true, no_upgrade: false, verbose: false, force: false, clone_target: nil,
                     **_options)
          _ = no_upgrade

          return true unless preinstall

          puts "Installing #{name} tap. It is not currently installed." if verbose
          args = []
          official_tap = name.downcase.start_with? "homebrew/"
          args << "--force" if force || (official_tap && Homebrew::EnvConfig.developer?)

          success = if clone_target
            Bundle.brew("tap", name, clone_target, *args, verbose:)
          else
            Bundle.brew("tap", name, *args, verbose:)
          end

          unless success
            require "bundle/skipper"
            Homebrew::Bundle::Skipper.tap_failed!(name)
            return false
          end

          require "tap"
          ::Tap.fetch(name).clear_cache
          installed_taps << name
          true
        end

        sig { override.params(_name: String, _options: Homebrew::Bundle::EntryOptions).returns(String) }
        def install_verb(_name = "", _options = {})
          "Tapping"
        end

        sig { override.params(dumped_formulae: T::Array[String], dumped_casks: T::Array[String]).returns(String) }
        def dump(dumped_formulae: [], dumped_casks: [])
          taps.map do |tap|
            remote = if (tap_remote = tap.remote) && tap_remote != tap.default_remote
              if (api_token = ENV.fetch("HOMEBREW_GITHUB_API_TOKEN", false).presence)
                # Replace the API token in the remote URL with interpolation.
                # Keep the interpolation unevaluated until the Brewfile is evaluated.
                tap_remote = tap_remote.gsub api_token, "\#{ENV.fetch(\"HOMEBREW_GITHUB_API_TOKEN\")}"
              end
              ", \"#{tap_remote}\""
            end
            tapline = "tap \"#{tap.name}\"#{remote}"
            trusted = if Homebrew::Trust.explicitly_trusted_tap?(tap)
              true
            else
              tap_trust = T.let({}, T::Hash[Symbol, T::Array[String]])
              {
                formula: [:formulae, dumped_formulae],
                cask:    [:casks, dumped_casks],
                command: [:commands, []],
              }.each do |type, values|
                key, dumped_items = values
                trusted_items = Homebrew::Trust.trusted_entries(type).filter_map do |entry|
                  reference, _, item = entry.rpartition("/")
                  next if reference.blank? || item.blank?
                  next if reference != tap.name && !tap.matches_reference?(reference)
                  next if dumped_items.include?("#{tap.name}/#{item}")

                  item
                end.sort.uniq
                tap_trust[key] = trusted_items if trusted_items.present?
              end
              tap_trust.presence
            end

            if trusted == true
              tapline += ", trusted: true"
            elsif trusted.present?
              trusted_options = trusted.map do |key, values|
                "#{key}: [#{values.map(&:inspect).join(", ")}]"
              end.join(", ")
              tapline += ", trusted: { #{trusted_options} }"
            end
            tapline
          end.sort.uniq.join("\n")
        end

        sig { override.params(describe: T::Boolean, no_restart: T::Boolean).returns(String) }
        def dump_output(describe: false, no_restart: false)
          _ = describe
          _ = no_restart

          dump
        end

        sig { returns(T::Array[String]) }
        def tap_names
          taps.map(&:name)
        end

        sig { returns(T::Array[String]) }
        def installed_taps
          @installed_taps ||= T.let(tap_names, T.nilable(T::Array[String]))
        end

        sig { returns(T::Array[::Tap]) }
        def taps
          @taps ||= begin
            require "tap"
            ::Tap.select(&:installed?).to_a
          end
        end
        private :taps
      end

      sig {
        override.params(entries: T::Array[Dsl::Entry], exit_on_first_error: T::Boolean,
                        no_upgrade: T::Boolean, verbose: T::Boolean).returns(T::Array[String])
      }
      def find_actionable(entries, exit_on_first_error: false, no_upgrade: false, verbose: false)
        _ = exit_on_first_error
        _ = no_upgrade
        _ = verbose

        requested_taps = format_checkable(entries)
        return [] if requested_taps.empty?

        current_taps = self.class.tap_names
        (requested_taps - current_taps).map { |entry| "Tap #{entry} needs to be tapped." }
      end

      sig { override.params(package: Object, no_upgrade: T::Boolean).returns(T::Boolean) }
      def installed_and_up_to_date?(package, no_upgrade: false)
        _ = no_upgrade

        self.class.installed_taps.include?(T.cast(package, String))
      end
    end
  end
end
