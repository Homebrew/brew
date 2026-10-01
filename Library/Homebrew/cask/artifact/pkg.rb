# typed: strict
# frozen_string_literal: true

require "utils/data"
require "utils/text"

require "utils/user"
require "cask/artifact/abstract_artifact"
require "extend/hash/keys"

module Cask
  module Artifact
    # Artifact corresponding to the `pkg` stanza.
    class Pkg < AbstractArtifact
      sig { override.returns(T::Boolean) }
      def requires_sudo? = true

      sig { returns(Pathname) }
      attr_reader :path

      sig { returns(T::Hash[Symbol, DirectivesType]) }
      attr_reader :stanza_options

      # The stanza options are validated below rather than typed as keywords so
      # that an unknown key names itself in the error.
      sig {
        params(cask: Cask, path: T.any(String, Pathname), stanza_options: DirectivesType)
          .returns(T.attached_class)
      }
      def self.from_args(cask, path, **stanza_options)
        if stanza_options.key?(:allow_untrusted)
          odeprecated "`allow_untrusted` in the `pkg` stanza", "a trusted package"
        end
        ::Utils::Data.assert_valid_keys(stanza_options, :allow_untrusted, :choices)
        new(cask, path, **stanza_options)
      end

      sig { params(cask: Cask, path: T.any(String, Pathname), stanza_options: DirectivesType).void }
      def initialize(cask, path, **stanza_options)
        super
        @path = T.let(cask.staged_path.join(path), Pathname)
        @stanza_options = stanza_options
      end

      sig { override.returns(String) }
      def summarize
        path.relative_path_from(cask.staged_path).to_s
      end

      sig {
        params(
          adopt:        T::Boolean,
          auto_updates: T.nilable(T::Boolean),
          force:        T::Boolean,
          verbose:      T::Boolean,
          predecessor:  T.nilable(Cask),
          command:      T.class_of(SystemCommand),
        ).void
      }
      def install_phase(adopt: false, auto_updates: false, force: false, verbose: false, predecessor: nil,
                        command: SystemCommand)
        run_installer(command:, verbose:)
      end

      private

      sig { params(command: T.class_of(SystemCommand), verbose: T::Boolean).void }
      def run_installer(command: SystemCommand, verbose: false)
        ohai "Running installer for #{cask} with `sudo` (which may request your password)..."
        unless path.exist?
          pkg = path.relative_path_from(cask.staged_path)
          pkgs = Pathname.glob(cask.staged_path/"**"/"*.pkg").map { |path| path.relative_path_from(cask.staged_path) }

          message = "Could not find PKG source file '#{pkg}'"
          message += ", found #{::Utils::Text.to_sentence(pkgs.map { |path| "'#{path}'" })} instead" if pkgs.any?
          message += "."

          raise CaskError, message
        end

        args = [
          "-pkg",    path,
          "-target", "/"
        ]
        args << "-verboseR" if verbose
        args << "-allowUntrusted" if stanza_options[:allow_untrusted]
        with_choices_file do |choices_path|
          args << "-applyChoiceChangesXML" << choices_path if choices_path

          current_user_str = User.current&.to_s
          env = {
            "LOGNAME"  => current_user_str,
            "USER"     => current_user_str,
            "USERNAME" => current_user_str,
          }

          command.run!(
            "/usr/sbin/installer",
            sudo:         true,
            sudo_as_root: true,
            args:,
            print_stdout: true,
            env:,
          )
        end
      end

      sig {
        params(_blk: T.proc.params(choices_path: T.nilable(String)).void)
          .void
      }
      def with_choices_file(&_blk)
        choices = stanza_options[:choices]
        # An invalid `choices` still reaches `Plist::Emit.dump` below, so that
        # `installer` rejects it instead of using the default choices.
        return yield nil if choices.nil?
        return yield nil if (choices.is_a?(Array) || choices.is_a?(Hash)) && choices.empty?

        require "plist"
        Tempfile.open(["choices", ".xml"]) do |file|
          file.write Plist::Emit.dump(choices)
          file.close
          yield file.path
        ensure
          file.unlink
        end
      end
    end
  end
end
