# typed: strict
# frozen_string_literal: true

require "bundle/dsl"

module Homebrew
  module Bundle
    module Brewfile
      sig {
        params(
          dash_writes_to_stdout: T::Boolean,
          global:                T::Boolean,
          file:                  T.nilable(String),
        ).returns(Pathname)
      }
      def self.path(dash_writes_to_stdout: false, global: false, file: nil)
        env_bundle_file_global = ENV.fetch("HOMEBREW_BUNDLE_FILE_GLOBAL", nil)
        env_bundle_file = ENV.fetch("HOMEBREW_BUNDLE_FILE", nil)
        user_config_home = ENV.fetch("HOMEBREW_USER_CONFIG_HOME", nil)

        filename = if global
          if env_bundle_file_global.present?
            env_bundle_file_global
          else
            raise "'HOMEBREW_BUNDLE_FILE' cannot be specified with '--global'" if env_bundle_file.present?

            if user_config_home
              xdg_path = "#{user_config_home}/Brewfile"
              legacy_path = Bundle.exchange_uid_if_needed! { "#{Dir.home}/.Brewfile" }

              # Prefer existing file to maintain backwards compatibility
              if File.exist?(xdg_path) || !File.exist?(legacy_path)
                xdg_path
              else
                legacy_path
              end
            else
              Bundle.exchange_uid_if_needed! do
                "#{Dir.home}/.Brewfile"
              end
            end
          end
        elsif file.present?
          handle_file_value(file, dash_writes_to_stdout)
        elsif env_bundle_file.present?
          env_bundle_file
        else
          "Brewfile"
        end

        Pathname.new(filename).expand_path(Dir.pwd)
      end

      sig { params(global: T::Boolean, file: T.nilable(String)).returns(Dsl) }
      def self.read(global: false, file: nil)
        Homebrew::Bundle::Dsl.new(Brewfile.path(global:, file:))
      rescue Errno::ENOENT
        raise "No Brewfile found"
      end

      sig {
        params(
          filename:              String,
          dash_writes_to_stdout: T::Boolean,
        ).returns(String)
      }
      private_class_method def self.handle_file_value(filename, dash_writes_to_stdout)
        if filename != "-"
          filename
        elsif dash_writes_to_stdout
          "/dev/stdout"
        else
          "/dev/stdin"
        end
      end
    end
  end
end
