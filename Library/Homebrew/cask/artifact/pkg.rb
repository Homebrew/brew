# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "plist"

require "utils/user"
require "cask/artifact/abstract_artifact"
require "extend/hash/keys"

module Cask
  module Artifact
    # Artifact corresponding to the `pkg` stanza.
    class Pkg < AbstractArtifact
      attr_reader :path, :stanza_options

      def self.from_args(cask, path, **stanza_options)
        stanza_options.assert_valid_keys(:allow_untrusted, :choices)
        new(cask, path, **stanza_options)
      end

      def initialize(cask, path, **stanza_options)
        super
        @path = cask.staged_path.join(path)
        @stanza_options = stanza_options
      end

      def summarize
        path.relative_path_from(cask.staged_path).to_s
      end

      def install_phase(**options)
        run_installer(**options)
      end

      private

      def run_installer(command: nil, verbose: false, **_options)
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

      def with_choices_file
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
