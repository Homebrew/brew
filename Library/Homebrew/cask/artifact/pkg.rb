# typed: strict
# frozen_string_literal: true

require "plist"

require "utils/user"
require "cask/artifact/abstract_artifact"
require "extend/hash/keys"

module Cask
  module Artifact
    # Artifact corresponding to the `pkg` stanza.
    class Pkg < AbstractArtifact
      sig { returns(Pathname) }
      attr_reader :path

      sig { returns(T::Hash[Symbol, T.untyped]) }
      attr_reader :stanza_options

      sig { params(cask: Cask, path: T.any(String, Pathname), stanza_options: T.untyped).returns(T.attached_class) }
      def self.from_args(cask, path, **stanza_options)
        # odeprecated: `allow_untrusted` disables certificate verification and is being removed.
        stanza_options.assert_valid_keys(:allow_untrusted, :choices)
        new(cask, path, **stanza_options)
      end

      sig { params(cask: Cask, path: T.any(String, Pathname), stanza_options: T.untyped).void }
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
          command:  T.class_of(SystemCommand),
          verbose:  T::Boolean,
          _options: T.anything,
        ).void
      }
      def install_phase(command: SystemCommand, verbose: false, **_options)
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
          message += ", found #{pkgs.map { |path| "'#{path}'" }.to_sentence} instead" if pkgs.any?
          message += "."

          raise CaskError, message
        end

        args = [
          "-pkg",    path,
          "-target", "/"
        ]
        args << "-verboseR" if verbose
        # odeprecated: `allow_untrusted` disables certificate verification and is being removed.
        args << "-allowUntrusted" if stanza_options.fetch(:allow_untrusted, false)
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
        choices = stanza_options.fetch(:choices, {})
        return yield nil if choices.empty?

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
