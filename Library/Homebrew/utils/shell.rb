# typed: strict
# frozen_string_literal: true

require "utils/path"
require "utils/popen"

module Utils
  module Shell
    extend T::Helpers

    requires_ancestor { Kernel }

    module_function

    sig { params(cmd: String, path: PATH::Elements).returns(T.nilable(Pathname)) }
    def which(cmd, path = ENV.fetch("PATH"))
      PATH.new(path).each do |entry|
        begin
          executable = File.expand_path(cmd, entry)
        rescue ArgumentError
          next
        end
        return Pathname.new(executable) if File.file?(executable) && File.executable?(executable)
      end
      nil
    end

    sig {
      type_parameters(:U)
        .params(
          hash:   T::Hash[Object, T.nilable(T.any(PATH, Pathname, String))],
          _block: T.proc.returns(T.type_parameter(:U)),
        ).returns(T.type_parameter(:U))
    }
    def with_env(hash, &_block)
      old_values = {}
      begin
        hash.each do |key, value|
          key = key.to_s
          old_values[key] = ENV.delete(key)
          ENV[key] = value&.to_s
        end

        yield
      ensure
        ENV.update(old_values)
      end
    end

    sig { type_parameters(:U).params(block: T.proc.returns(T.type_parameter(:U))).returns(T.type_parameter(:U)) }
    def with_homebrew_path(&block)
      with_env(PATH: PATH.new(ORIGINAL_PATHS).to_s, &block)
    end

    sig { params(formula: T.nilable(Formula)).void }
    def interactive(formula = nil)
      unless formula.nil?
        ENV["HOMEBREW_DEBUG_PREFIX"] = formula.prefix.to_s
        ENV["HOMEBREW_DEBUG_INSTALL"] = formula.full_name
      end

      if preferred == :zsh && (home = Dir.home).start_with?(Utils::Path.resolved_path(HOMEBREW_TEMP).to_s)
        FileUtils.mkdir_p home
        FileUtils.touch "#{home}/.zshrc"
      end

      term = ENV.fetch("HOMEBREW_TERM", ENV.fetch("TERM", nil))
      with_env(TERM: term) do
        Process.wait fork { exec preferred_path(default: "/bin/bash") }
      end

      return if $CHILD_STATUS.success?
      raise "Aborted due to non-zero exit status (#{$CHILD_STATUS.exitstatus})" if $CHILD_STATUS.exited?

      raise $CHILD_STATUS.inspect
    end

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
      from_path(Utils.popen_read_text("ps", "-p", Process.ppid.to_s, "-o", "ucomm=", err: :err).strip)
    end

    # Quote values. Quoting keys is overkill.
    sig { params(key: String, value: String, shell: T.nilable(Symbol)).returns(T.nilable(String)) }
    def export_value(key, value, shell = preferred)
      case shell
      when :bash, :ksh, :mksh, :sh, :zsh
        "export #{key}=#{sh_quote(value)}"
      when :fish
        # fish quoting is mostly Bourne compatible except that
        # a single quote can be included in a single-quoted string via \'
        # and a literal \ can be included via \\
        "set -gx #{key} #{sh_quote(value)}"
      when :pwsh
        "$env:#{key} = #{pwsh_quote(value)}"
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
      when :bash, :ksh, :mksh, :sh, :zsh, nil
        "echo 'export #{variable}=#{sh_quote(value)}' >> #{profile}"
      when :pwsh
        "#{pwsh_quote("$env:#{variable} = #{pwsh_quote(value)}")} >> #{profile}"
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
        "echo 'export PATH=#{sh_quote(path)}:$PATH' >> #{profile}"
      when :pwsh
        "#{pwsh_quote("$env:PATH = #{pwsh_quote(path)} + \":$env:PATH\"")} >> #{profile}"
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
      str.gsub!(UNSAFE_SHELL_CHAR, '\\\\\\1')
      # Newlines have to be specially quoted in `csh`.
      str.gsub!("\n", "'\\\n'")
      str
    end

    # PowerShell single-quoted strings take a literal `'` as `''` and expand
    # nothing else, so one pass covers `$`, `"` and backticks too.
    sig { params(str: String).returns(String) }
    def pwsh_quote(str)
      "'#{str.gsub("'", "''")}'"
    end

    sig { params(str: String).returns(String) }
    def sh_quote(str)
      # Ruby's implementation of `shell_escape`.
      str = str.to_s
      return "''" if str.empty?

      str = str.dup
      # Anything that isn't a known safe character is padded.
      str.gsub!(UNSAFE_SHELL_CHAR, '\\\\\\1')
      str.gsub!("\n", "'\n'")
      str
    end

    sig { params(type: String, preferred_path: String, notice: T.nilable(String), home: String).returns(String) }
    def shell_with_prompt(type, preferred_path:, notice:, home: Dir.home)
      preferred = from_path(preferred_path)
      path = ENV.fetch("PATH")
      subshell = case preferred
      when :zsh
        zdotdir = Pathname.new(HOMEBREW_TEMP/"brew-zsh-prompt-#{Process.euid}")
        zdotdir.mkpath
        FileUtils.chmod_R(0700, zdotdir)
        FileUtils.cp(HOMEBREW_LIBRARY_PATH/"utils/zsh/brew-sh-prompt-zshrc.zsh", zdotdir/".zshrc")
        %w[.zshenv .zcompdump .zsh_history .zsh_sessions].each do |file|
          FileUtils.ln_sf("#{home}/#{file}", zdotdir/file)
        end
        <<~ZSH.strip
          BREW_PROMPT_PATH="#{path}" BREW_PROMPT_TYPE="#{type}" ZDOTDIR="#{zdotdir}" #{preferred_path}
        ZSH
      when :bash
        <<~BASH.strip
          BREW_PROMPT_PATH="#{path}" BREW_PROMPT_TYPE="#{type}" #{preferred_path} --rcfile "#{HOMEBREW_LIBRARY_PATH}/utils/bash/brew-sh-prompt-bashrc.bash"
        BASH
      else
        "PS1=\"\\[\\033[1;32m\\]#{type} \\[\\033[1;31m\\]\\w \\[\\033[1;34m\\]$\\[\\033[0m\\] \" #{preferred_path}"
      end

      puts notice if notice.present?
      $stdout.flush

      subshell
    end
  end
end
