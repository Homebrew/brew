# typed: true
# frozen_string_literal: true

require "cask/artifact/abstract_artifact"

module Cask
  module Artifact
    # Artifact corresponding to the `installer` stanza.
    #
    # @api private
    class Installer < AbstractArtifact
      VALID_KEYS = Set.new([
        :manual,
        :script,
      ]).freeze

      # Extension module for manual installers.
      module ManualInstaller
        def install_phase(**)
          puts <<~EOS
            Cask #{cask} only provides a manual installer. To run it and complete the installation:
              open #{cask.staged_path.join(path).to_s.shellescape}
          EOS
        end
      end

      # Extension module for script installers.
      module ScriptInstaller
        def install_phase(command: nil, **_)
          # TODO: The `T.unsafe` is a false positive that is unnecessary in newer releasese of Sorbet
          # (confirmend with sorbet v0.5.10672)
          ohai "Running #{T.unsafe(self.class).dsl_key} script '#{path}'"

          executable_path = staged_path_join_executable(path)

          command.run!(
            executable_path,
            **args,
            env: { "PATH" => PATH.new(
              HOMEBREW_PREFIX/"bin", HOMEBREW_PREFIX/"sbin", ENV.fetch("PATH")
            ) },
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

      def initialize(cask, **args)
        super(cask, **args)

        if args.key?(:manual)
          @path = Pathname(args[:manual])
          @args = []
          extend(ManualInstaller)
          return
        end

        path, @args = self.class.read_script_arguments(
          args[:script], self.class.dsl_key.to_s, { must_succeed: true, sudo: false }, print_stdout: true
        )
        raise CaskInvalidError.new(cask, "#{self.class.dsl_key} missing executable") if path.nil?

        @path = Pathname(path)
        extend(ScriptInstaller)
      end

      def summarize
        path.to_s
      end

      def to_h
        { path: path }.tap do |h|
          h[:args] = args unless is_a?(ManualInstaller)
        end
      end
    end
  end
end
