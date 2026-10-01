# typed: strict
# frozen_string_literal: true

require "utils/data"

require "cask/artifact/abstract_artifact"
require "extend/hash/keys"

module Cask
  module Artifact
    # Artifact corresponding to the `installer` stanza.
    class Installer < AbstractArtifact
      VALID_KEYS = T.let(Set.new([
        :manual,
        :script,
      ]).freeze, T::Set[Symbol])

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
            env: { "PATH" => PATH.new(
              HOMEBREW_PREFIX/"bin", HOMEBREW_PREFIX/"sbin", ENV.fetch("PATH")
            ) },
          )
        end
      end

      # The stanza arguments are validated below rather than typed as keywords so
      # that an unknown key names itself in the error.
      sig { params(cask: Cask, args: DirectivesType).returns(T.attached_class) }
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

        ::Utils::Data.assert_valid_keys(args, *VALID_KEYS)
        new(cask, **args)
      end

      sig { returns(Pathname) }
      attr_reader :path

      sig { returns(T::Hash[Symbol, T.untyped]) }
      attr_reader :args

      sig { returns(T::Boolean) }
      attr_reader :manual_install

      sig { override.returns(T::Boolean) }
      def requires_sudo? = args[:sudo] == true

      sig { params(cask: Cask, args: DirectivesType).void }
      def initialize(cask, **args)
        super

        if args.key?(:manual)
          manual = args[:manual]
          if !manual.is_a?(String) && !manual.is_a?(Pathname)
            raise CaskInvalidError.new(cask, "#{self.class.dsl_key} requires a path for :manual")
          end

          @path = T.let(Pathname(manual), Pathname)
          @args = T.let({}, T::Hash[Symbol, T.untyped])
          @manual_install = T.let(true, T::Boolean)
        else
          script_path, script_args = self.class.read_script_arguments(
            args[:script], self.class.dsl_key.to_s, { must_succeed: true, sudo: false }, print_stdout: true
          )
          raise CaskInvalidError.new(cask, "#{self.class.dsl_key} missing executable") if script_path.nil?

          @path = T.let(Pathname(script_path), Pathname)
          @args = T.let(script_args, T::Hash[Symbol, T.untyped])
          @manual_install = T.let(false, T::Boolean)
        end
      end

      sig { override.returns(String) }
      def summarize = path.to_s

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_h
        { path: }.tap do |h|
          h[:args] = args unless manual_install
        end
      end
    end
  end
end
