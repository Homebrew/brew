# typed: strict
# frozen_string_literal: true

module Utils
  # Shared logic for generating shell completion scripts.
  # Used by both {Formula#generate_completions_from_executable} and
  # {Cask::Artifact::GeneratedCompletion}.
  module ShellCompletion
    sig { params(format: T.nilable(T.any(Symbol, String))).returns(T::Array[Symbol]) }
    def self.default_completion_shells(format)
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
    def self.completion_shell_parameter(format, shell, executable, env)
      # Go's cobra and Rust's clap accept "powershell".
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

    sig {
      params(
        commands:        T::Array[T.any(Pathname, String)],
        shell_parameter: T.nilable(T.any(String, T::Array[String])),
        env:             T::Hash[String, String],
        print_stderr:    T::Boolean,
      ).returns(String)
    }
    def self.generate_completion_output(commands, shell_parameter, env, print_stderr: true)
      args = T.let(commands + Array(shell_parameter), T::Array[T.any(Pathname, String)])
      options = T.let({}, T::Hash[Symbol, Symbol])
      options[:err] = :err if print_stderr || ENV["HOMEBREW_STDERR"]
      Utils.safe_popen_read(env, *args, **options)
    end
  end
end
