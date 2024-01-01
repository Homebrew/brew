# typed: true
# frozen_string_literal: true

require "extend/ENV"
require "formula"
require "cli/parser"

module Homebrew
  module_function

  sig { returns(CLI::Parser) }
  def sh_args
    Homebrew::CLI::Parser.new do
      description <<~EOS
        Enter an interactive shell for Homebrew's build environment. Use years-battle-hardened
        build logic to help your `./configure && make && make install`
        and even your `gem install` succeed. Especially handy if you run Homebrew
        in an Xcode-only configuration since it adds tools like `make` to your `PATH`
        which build systems would not find otherwise.
      EOS
      flag   "--env=",
             description: "Use the standard `PATH` instead of superenv's when `std` is passed."
      flag   "-c=", "--cmd=",
             description: "Execute commands in a non-interactive shell."

      named_args :file, max: 1
    end
  end

  def sh
    args = sh_args.parse

    ENV.activate_extensions!(env: args.env)

    ENV.deps = Formula.installed.select { |f| f.keg_only? && f.opt_prefix.directory? } if superenv?(args.env)
    ENV.setup_build_environment
    if superenv?(args.env)
      # superenv stopped adding brew's bin but generally users will want it
      ENV["PATH"] = PATH.new(ENV.fetch("PATH")).insert(1, HOMEBREW_PREFIX/"bin").to_s
    end

    ENV["VERBOSE"] = "1" if args.verbose?

    preferred_shell = Utils::Shell.preferred_path(default: "/bin/bash")

    if args.cmd.present?
      safe_system(preferred_shell, "-c", args.cmd)
    elsif args.named.present?
      safe_system(preferred_shell, args.named.first)
    else
      shell_type = Utils::Shell.preferred
      subshell = case shell_type
      when :zsh
        "PS1='brew %B%F{green}%~%f%b$ ' #{preferred_shell} -d -f"
      when :bash
        "PS1=\"brew \\[\\033[1;32m\\]\\w\\[\\033[0m\\]$ \" #{preferred_shell} --noprofile --norc"
      else
        "PS1=\"brew \\[\\033[1;32m\\]\\w\\[\\033[0m\\]$ \" #{preferred_shell}"
      end
      puts <<~EOS
        Your shell has been configured to use Homebrew's build environment;
        this should help you build stuff. Notably though, the system versions of
        gem and pip will ignore our configuration and insist on using the
        environment they were built under (mostly). Sadly, scons will also
        ignore our configuration.
        When done, type `exit`.
      EOS
      $stdout.flush
      safe_system subshell
    end
  end
end
