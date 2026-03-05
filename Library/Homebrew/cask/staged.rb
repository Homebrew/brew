# typed: strict
# frozen_string_literal: true

require "utils/popen"
require "utils/user"
require "utils/output"

module Cask
  # Helper functions for staged casks.
  module Staged
    include ::Utils::Output::Mixin
    extend T::Helpers

    requires_ancestor { ::Cask::DSL::Base }

    Paths = T.type_alias { T.any(String, Pathname, T::Array[T.any(String, Pathname)]) }

    sig { params(paths: Paths, permissions_str: String).void }
    def set_permissions(paths, permissions_str)
      full_paths = remove_nonexistent(paths)
      return if full_paths.empty?

      command.run!("chmod", args: ["-R", "--", permissions_str, *full_paths],
                            sudo: false)
    end

    sig { params(paths: Paths, user: T.any(String, User), group: String).void }
    def set_ownership(paths, user: T.must(User.current), group: "staff")
      full_paths = remove_nonexistent(paths)
      return if full_paths.empty?

      ohai "Changing ownership of paths required by #{cask} with `sudo` (which may request your password)..."
      command.run!("chown", args: ["-R", "--", "#{user}:#{group}", *full_paths],
                            sudo: true)
    end

    sig {
      params(
        commands:               T.any(Pathname, String),
        base_name:              T.nilable(String),
        shell_parameter_format: T.nilable(T.any(Symbol, String)),
        shells:                 T::Array[Symbol],
      ).void
    }
    def generate_completions_from_executable(*commands,
                                             base_name: nil,
                                             shell_parameter_format: nil,
                                             shells: default_completion_shells(shell_parameter_format))
      executable = commands.first.to_s
      base_name ||= cask.token

      config = cask.config
      completion_script_path_map = {
        bash: config.bash_completion/base_name,
        zsh:  config.zsh_completion/"_#{base_name}",
        fish: config.fish_completion/"#{base_name}.fish",
        pwsh: config.pwsh_completion/"_#{base_name}.ps1",
      }

      shells.each do |shell|
        popen_read_env = { "SHELL" => shell.to_s }
        script_path = completion_script_path_map[shell]
        next if script_path.nil?

        shell_parameter = completion_shell_parameter(
          shell_parameter_format,
          shell,
          executable,
          popen_read_env,
        )

        popen_read_args = %w[]
        popen_read_args << commands
        popen_read_args << shell_parameter if shell_parameter.present?
        popen_read_args.flatten!

        popen_read_options = {}
        popen_read_options[:err] = :err unless ENV["HOMEBREW_STDERR"]

        script_path.dirname.mkpath
        script_path.write ::Utils.safe_popen_read(popen_read_env, *popen_read_args, **popen_read_options)
      end
    end

    sig { params(base_name: String).void }
    def remove_generated_completions(base_name)
      config = cask.config

      [
        config.bash_completion/base_name,
        config.zsh_completion/"_#{base_name}",
        config.fish_completion/"#{base_name}.fish",
        config.pwsh_completion/"_#{base_name}.ps1",
      ].each do |path|
        path.delete if path.exist?
      end
    end

    private

    sig { params(format: T.nilable(T.any(Symbol, String))).returns(T::Array[Symbol]) }
    def default_completion_shells(format)
      case format
      when :cobra, :typer
        [:bash, :zsh, :fish, :pwsh]
      else
        [:bash, :zsh, :fish]
      end
    end

    sig {
      params(
        format:     T.nilable(T.any(Symbol, String)),
        shell:      Symbol,
        executable: String,
        env:        T::Hash[String, String],
      ).returns(T.nilable(T.any(String, T::Array[String])))
    }
    def completion_shell_parameter(format, shell, executable, env)
      shell_parameter = (shell == :pwsh) ? "powershell" : shell.to_s

      case format
      when nil
        shell_parameter
      when :arg
        "--shell=#{shell_parameter}"
      when :clap
        env["COMPLETE"] = shell_parameter
        nil
      when :click
        prog_name = File.basename(executable).upcase.tr("-", "_")
        env["_#{prog_name}_COMPLETE"] = "#{shell_parameter}_source"
        nil
      when :cobra
        ["completion", shell_parameter]
      when :flag
        "--#{shell_parameter}"
      when :none
        nil
      when :typer
        env["_TYPER_COMPLETE_TEST_DISABLE_SHELL_DETECTION"] = "1"
        ["--show-completion", shell_parameter]
      else
        "#{format}#{shell}"
      end
    end

    sig { params(paths: Paths).returns(T::Array[Pathname]) }
    def remove_nonexistent(paths)
      Array(paths).map { |p| Pathname(p).expand_path }.select(&:exist?)
    end
  end
end
