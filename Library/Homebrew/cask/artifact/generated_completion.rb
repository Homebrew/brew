# typed: strict
# frozen_string_literal: true

require "cask/artifact/abstract_artifact"
require "cask/artifact/bashcompletion"
require "cask/artifact/fishcompletion"
require "cask/artifact/zshcompletion"
require "extend/hash/keys"
require "utils/shell_completion"

module Cask
  module Artifact
    # Artifact corresponding to the `generate_completions_from_executable` stanza.
    class GeneratedCompletion < AbstractArtifact
      SUPPORTED_SHELLS = T.let([:bash, :zsh, :fish, :pwsh].freeze, T::Array[Symbol])

      sig { override.returns(Symbol) }
      def self.dsl_key
        :generate_completions_from_executable
      end

      sig {
        params(
          cask:                   Cask,
          args:                   T.any(Pathname, String),
          base_name:              T.nilable(String),
          shell_parameter_format: T.nilable(T.any(Symbol, String)),
          shells:                 T.nilable(T::Array[Symbol]),
        ).returns(T.attached_class)
      }
      def self.from_args(cask, *args, base_name: nil, shell_parameter_format: nil, shells: nil)
        raise CaskInvalidError.new(cask.token, "'#{dsl_key}' requires at least one command") if args.empty?

        commands = args.to_a
        resolved_shells = shells || ::Utils::ShellCompletion.default_completion_shells(shell_parameter_format)

        unsupported_shells = resolved_shells - SUPPORTED_SHELLS
        unless unsupported_shells.empty?
          raise CaskInvalidError.new(
            cask.token,
            "'#{dsl_key}' does not support shell(s): #{unsupported_shells.join(", ")}",
          )
        end

        new(
          cask,
          commands,
          base_name:,
          shell_parameter_format:,
          shells:                 resolved_shells,
        )
      end

      sig {
        params(
          cask:                   Cask,
          commands:               T::Array[T.any(Pathname, String)],
          base_name:              T.nilable(String),
          shell_parameter_format: T.nilable(T.any(Symbol, String)),
          shells:                 T::Array[Symbol],
        ).void
      }
      def initialize(cask, commands, base_name:, shell_parameter_format:, shells:)
        super(cask, *commands, base_name:, shell_parameter_format:, shells:)

        @commands = commands
        @base_name = base_name
        @shell_parameter_format = shell_parameter_format
        @shells = shells
        @resolved_base_name = T.let(nil, T.nilable(String))
      end

      sig { returns(T::Array[T.any(Pathname, String)]) }
      attr_reader :commands

      sig { returns(T.nilable(String)) }
      attr_reader :base_name

      sig { returns(T.nilable(T.any(Symbol, String))) }
      attr_reader :shell_parameter_format

      sig { returns(T::Array[Symbol]) }
      attr_reader :shells

      sig { override.returns(String) }
      def summarize
        "#{commands.join(" ")} (base_name: #{resolved_base_name}, shells: #{shells.join(", ")})"
      end

      sig { params(_options: T.untyped).void }
      def install_phase(**_options)
        executable = staged_path_join_executable(T.must(commands.first))

        shells.each do |shell|
          popen_read_env = { "SHELL" => shell.to_s }
          shell_parameter = ::Utils::ShellCompletion.completion_shell_parameter(
            shell_parameter_format, shell, executable.to_s, popen_read_env
          )

          script_path = completion_script_path(shell)
          script_path.dirname.mkpath
          script_path.write(::Utils::ShellCompletion.generate_completion_output(
                              [executable, *commands[1..]],
                              shell_parameter,
                              popen_read_env,
                            ))
        rescue => e
          opoo "Failed to generate #{shell} completions from #{executable}: #{e}"
        end
      end

      sig { params(command: T.class_of(SystemCommand), _options: T.untyped).void }
      def uninstall_phase(command: SystemCommand, **_options)
        shells.each do |shell|
          path = completion_script_path(shell)
          next unless path.exist?

          Utils.gain_permissions_remove(path, command:)
        rescue => e
          opoo "Failed to remove #{shell} generated completions: #{e}"
        end
      end

      private

      sig { returns(String) }
      def resolved_base_name
        @resolved_base_name ||= T.let(begin
          executable = staged_path_join_executable(T.must(commands.first))
          name = base_name || File.basename(executable.to_s)
          name = cask.token if name.empty?
          name
        end, T.nilable(String))
        @resolved_base_name
      end

      sig { params(shell: Symbol).returns(Pathname) }
      def completion_script_path(shell)
        case shell
        when :bash
          BashCompletion.new(cask, resolved_base_name).resolve_target(resolved_base_name)
        when :zsh
          ZshCompletion.new(cask, resolved_base_name).resolve_target(resolved_base_name)
        when :fish
          FishCompletion.new(cask, resolved_base_name).resolve_target(resolved_base_name)
        when :pwsh
          HOMEBREW_PREFIX/"share/pwsh/completions"/"_#{resolved_base_name}.ps1"
        else
          raise ArgumentError, "unsupported shell: #{shell}"
        end
      end
    end
  end
end
