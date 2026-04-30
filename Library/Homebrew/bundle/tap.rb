# typed: strict
# frozen_string_literal: true

require "json"
require "bundle/package_type"

module Homebrew
  module Bundle
    class Tap < Homebrew::Bundle::PackageType
      PACKAGE_TYPE = :tap
      PACKAGE_TYPE_NAME = "Tap"

      class << self
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

          installed_taps << name
          true
        end

        sig { override.params(_name: String, _options: Homebrew::Bundle::EntryOptions).returns(String) }
        def install_verb(_name = "", _options = {})
          "Tapping"
        end

        sig { override.params(name: String, options: Homebrew::Bundle::EntryOptions).returns(Homebrew::Bundle::LockEntry) }
        def lock_entry(name, options = {})
          tap = ::Tap.fetch(name)
          result = super

          result["remote"] = tap.remote if tap.remote.present?
          result["branch"] = tap.git_branch if tap.git_branch.present?
          result
        rescue
          super
        end

        sig { override.returns(String) }
        def dump
          taps.map do |tap|
            remote = if tap.custom_remote? && (tap_remote = tap.remote)
              if (api_token = ENV.fetch("HOMEBREW_GITHUB_API_TOKEN", false).presence)
                # Replace the API token in the remote URL with interpolation.
                # Rubocop's warning here is wrong; we intentionally want to not
                # evaluate this string until the Brewfile is evaluated.
                # rubocop:disable Lint/InterpolationCheck
                tap_remote = tap_remote.gsub api_token, '#{ENV.fetch("HOMEBREW_GITHUB_API_TOKEN")}'
                # rubocop:enable Lint/InterpolationCheck
              end
              ", \"#{tap_remote}\""
            end
            "tap \"#{tap.name}\"#{remote}"
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
        override.params(entries: T::Array[Object], exit_on_first_error: T::Boolean,
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
