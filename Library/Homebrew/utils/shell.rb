# typed: strict
# frozen_string_literal: true

module Utils
  module Shell
    extend T::Helpers

    requires_ancestor { Kernel }

    module_function

    # Take a path and heuristically convert it to a shell name,
    # return `nil` if there's no match.
    sig { params(path: String).returns(T.nilable(Symbol)) }
    def from_path(path)
      # we only care about the basename
      shell_name = File.basename(path)
      # handle possible version suffix like `zsh-5.2`
      shell_name.sub!(/-.*\z/m, "")
      shell_name.to_sym if %w[bash csh fish ksh mksh pwsh rc sh tcsh zsh].include?(shell_name)
    end

    sig { params(default: String).returns(String) }
    def preferred_path(default: "")
      ENV.fetch("SHELL", default)
    end

    sig { returns(T.nilable(Symbol)) }
    def preferred
      from_path(preferred_path)
    end

    sig { returns(T.nilable(Symbol)) }
    def parent
      from_path(`ps -p #{Process.ppid} -o ucomm=`.strip)
    end

    # Quote values. Quoting keys is overkill.
    sig { params(key: String, value: String, shell: T.nilable(Symbol)).returns(T.nilable(String)) }
    def export_value(key, value, shell = preferred)
      case shell
      when :bash, :ksh, :mksh, :sh, :zsh
        "export #{key}=\"#{sh_quote(value)}\""
      when :fish
        # fish quoting is mostly Bourne compatible except that
        # a single quote can be included in a single-quoted string via \'
        # and a literal \ can be included via \\
        "set -gx #{key} \"#{sh_quote(value)}\""
      when :rc
        "#{key}=(#{sh_quote(value)})"
      when :csh, :tcsh
        "setenv #{key} #{csh_quote(value)};"
      end
    end

    # Return the shell profile file based on user's preferred shell.
    sig { returns(String) }
    def profile
      case preferred
      when :bash
        bash_profile = "#{Dir.home}/.bash_profile"
        return bash_profile if File.exist? bash_profile
      when :pwsh
        pwsh_profile = "#{Dir.home}/.config/powershell/Microsoft.PowerShell_profile.ps1"
        return pwsh_profile if File.exist? pwsh_profile
      when :rc
        rc_profile = "#{Dir.home}/.rcrc"
        return rc_profile if File.exist? rc_profile
      when :zsh
        return "#{ENV["HOMEBREW_ZDOTDIR"]}/.zshrc" if ENV["HOMEBREW_ZDOTDIR"].present?
      end

      shell = preferred
      return "~/.profile" if shell.nil?

      SHELL_PROFILE_MAP.fetch(shell, "~/.profile")
    end

    sig { params(variable: String, value: String).returns(T.nilable(String)) }
    def set_variable_in_profile(variable, value)
      case preferred
      when :bash, :ksh, :sh, :zsh, nil
        "echo 'export #{variable}=#{sh_quote(value)}' >> #{profile}"
      when :pwsh
        "$env:#{variable}='#{value}' >> #{profile}"
      when :rc
        "echo '#{variable}=(#{sh_quote(value)})' >> #{profile}"
      when :csh, :tcsh
        "echo 'setenv #{variable} #{csh_quote(value)}' >> #{profile}"
      when :fish
        "echo 'set -gx #{variable} #{sh_quote(value)}' >> #{profile}"
      end
    end

    sig { params(path: String).returns(T.nilable(String)) }
    def prepend_path_in_profile(path)
      case preferred
      when :bash, :ksh, :mksh, :sh, :zsh, nil
        "echo 'export PATH=\"#{sh_quote(path)}:$PATH\"' >> #{profile}"
      when :pwsh
        "$env:PATH = '#{path}' + \":${env:PATH}\" >> #{profile}"
      when :rc
        "echo 'path=(#{sh_quote(path)} $path)' >> #{profile}"
      when :csh, :tcsh
        "echo 'setenv PATH #{csh_quote(path)}:$PATH' >> #{profile}"
      when :fish
        "fish_add_path #{sh_quote(path)}"
      end
    end

    SHELL_PROFILE_MAP = T.let(
      {
        bash: "~/.profile",
        csh:  "~/.cshrc",
        fish: "~/.config/fish/config.fish",
        ksh:  "~/.kshrc",
        mksh: "~/.kshrc",
        pwsh: "~/.config/powershell/Microsoft.PowerShell_profile.ps1",
        rc:   "~/.rcrc",
        sh:   "~/.profile",
        tcsh: "~/.tcshrc",
        zsh:  "~/.zshrc",
      }.freeze,
      T::Hash[Symbol, String],
    )

    UNSAFE_SHELL_CHAR = %r{([^A-Za-z0-9_\-.,:/@~+\n])}

    sig { params(str: String).returns(String) }
    def csh_quote(str)
      # Ruby's implementation of `shell_escape`.
      str = str.to_s
      return "''" if str.empty?

      str = str.dup
      # Anything that isn't a known safe character is padded.
      str.gsub!(UNSAFE_SHELL_CHAR, "\\\\" + "\\1") # rubocop:disable Style/StringConcatenation
      # Newlines have to be specially quoted in `csh`.
      str.gsub!("\n", "'\\\n'")
      str
    end

    sig { params(str: String).returns(String) }
    def sh_quote(str)
      # Ruby's implementation of `shell_escape`.
      str = str.to_s
      return "''" if str.empty?

      str = str.dup
      # Anything that isn't a known safe character is padded.
      str.gsub!(UNSAFE_SHELL_CHAR, "\\\\" + "\\1") # rubocop:disable Style/StringConcatenation
      str.gsub!("\n", "'\n'")
      str
    end
  end
end
