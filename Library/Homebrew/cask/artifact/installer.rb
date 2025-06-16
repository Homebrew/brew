# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "cask/artifact/abstract_artifact"
require "extend/hash/keys"

module Cask
  module Artifact
    # Artifact corresponding to the `installer` stanza.
    class Installer < AbstractArtifact
      VALID_KEYS = Set.new([
        :manual,
        :script,
      ]).freeze

      def install_phase(command: nil, **_)
        if manual_install
          puts <<~EOS
            Cask #{cask} only provides a manual installer. To run it and complete the installation:
              open #{cask.staged_path.join(path).to_s.shellescape}
          EOS
        else
          ohai "Running #{self.class.dsl_key} script '#{path}'"

          executable_path = staged_path_join_executable(path)

          command.run!(
            executable_path,
            **args,
            env:       { "PATH" => PATH.new(
              HOMEBREW_PREFIX/"bin", HOMEBREW_PREFIX/"sbin", ENV.fetch("PATH")
            ) },
            reset_uid: !args[:sudo],
          )
        end
      end

      def self.from_args(cask, **args)
        raise CaskInvalidError.new(cask, "'installer' stanza requires an argument.") if args.empty?

        if args.key?(:script) && !args[:script].respond_to?(:key?)
          if args.key?(:executable)
            raise CaskInvalidError.new(cask, "'installer' stanza gave arguments for both :script and :executable.")
          end

          args[:executable] = args[:script]
          args.delete(:script)
          args = { script: args }
        end

        if args.keys.count != 1
          raise CaskInvalidError.new(
            cask,
            "invalid 'installer' stanza: Only one of #{VALID_KEYS.inspect} is permitted.",
          )
        end

        args.assert_valid_keys(*VALID_KEYS)
        new(cask, **args)
      end

      attr_reader :path, :args

      sig { returns(T::Boolean) }
      attr_reader :manual_install

      def initialize(cask, **args)
        super

        if args.key?(:manual)
          @path = Pathname(args[:manual])
          @args = []
          @manual_install = true
        else
          path, @args = self.class.read_script_arguments(
            args[:script], self.class.dsl_key.to_s, { must_succeed: true, sudo: false }, print_stdout: true
          )
          raise CaskInvalidError.new(cask, "#{self.class.dsl_key} missing executable") if path.nil?

          @path = Pathname(path)
          @manual_install = false
        end
      end

      sig { override.returns(String) }
      def summarize = path.to_s

      def to_h
        { path: }.tap do |h|
          h[:args] = args unless manual_install
        end
      end
    end
  end
end
