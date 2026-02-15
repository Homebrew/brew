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
      Choices = T.type_alias { T.nilable(T.any(T::Array[T::Hash[T.anything, T.anything]], T::Hash[Symbol, T.anything])) }
      private_constant :Choices
      StanzaOptions = T.type_alias { { allow_untrusted: T.nilable(T::Boolean), choices: Choices } }
      private_constant :StanzaOptions

      sig { returns(Pathname) }
      attr_reader :path

      sig { returns(T::Hash[Symbol, T.anything]) }
      attr_reader :stanza_options

      # sig { params(cask: Cask, path: String, allow_untrusted: T.nilable(T::Boolean), choices: Choices).returns(Pkg) }
      # def self.from_args(cask, path, allow_untrusted: nil, choices: nil)
      sig { params(cask: Cask, path: String, stanza_options: T.anything).returns(Pkg) }
      def self.from_args(cask, path, **stanza_options)
        stanza_options.assert_valid_keys(:allow_untrusted, :choices)
        new(cask, path, **stanza_options)
      end

      # sig { params(cask: Cask, path: String, allow_untrusted: T.nilable(T::Boolean), choices: Choices).void }
      # def initialize(cask, path, allow_untrusted: nil, choices: nil)
      sig { params(cask: Cask, path: String, stanza_options: T.anything).void }
      def initialize(cask, path, **stanza_options)
        super
        @path = T.let(cask.staged_path.join(path), Pathname)
        @stanza_options = T.let(stanza_options, T::Hash[Symbol, T.anything])
      end

      sig { override.returns(String) }
      def summarize
        path.relative_path_from(cask.staged_path).to_s
      end

      sig { params(command: T.class_of(SystemCommand), options: T.anything).void }
      def install_phase(command:, **options)
        run_installer(command:, **options)
      end

      private

      sig { params(command: T.class_of(SystemCommand), verbose: T::Boolean, _options: T.anything).void }
      def run_installer(command:, verbose: false, **_options)
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
        args << "-allowUntrusted" if stanza_options.fetch(:allow_untrusted, false)
        with_choices_file do |choices_path|
          args << "-applyChoiceChangesXML" << choices_path if choices_path
          env = {
            "LOGNAME"  => User.current,
            "USER"     => User.current,
            "USERNAME" => User.current,
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

      sig { params(_block: T.proc.params(file_path: T.nilable(String)).void).void }
      def with_choices_file(&_block)
        choices = stanza_options.fetch(:choices, {})
        return yield nil if T.unsafe(choices).empty?

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
