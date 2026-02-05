# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "extend/ENV"
require "formula"
require "utils/gems"
require "utils/shell"

module Homebrew
  module DevCmd
    class Sh < AbstractCommand
      cmd_args do
        description <<~EOS
          Enter an interactive shell for Homebrew's build environment. Use years-battle-hardened
          build logic to help your `./configure && make && make install`
          and even your `gem install` succeed. Especially handy if you run Homebrew
          in an Xcode-only configuration since it adds tools like `make` to your `$PATH`
          which build systems would not find otherwise.

          With `--ruby`, enter an interactive shell for Homebrew's Ruby environment.
          This sets up the correct Ruby paths, `$GEM_HOME` and bundle
          configuration used by Homebrew's development tools.
          The environment includes gems from the installed groups,
          making tools like RuboCop, Sorbet and RSpec available via `bundle exec`.
        EOS
        switch "-r", "--ruby",
               description: "Set up Homebrew's Ruby environment."
        flag   "--env=",
               description: "Use the standard `$PATH` instead of superenv's when `std` is passed."
        flag   "-c=", "--cmd=",
               description: "Execute commands in a non-interactive shell."

        conflicts "--ruby", "--env="

        named_args :file, max: 1
      end

      sig { override.void }
      def run
        prompt, notice = if args.ruby?
          setup_ruby_environment!
        else
          setup_build_environment!
        end

        preferred_path = Utils::Shell.preferred_path(default: "/bin/bash")

        if args.cmd.present?
          safe_system(preferred_path, "-c", args.cmd)
        elsif args.named.present?
          safe_system(preferred_path, args.named.first)
        else
          system Utils::Shell.shell_with_prompt(prompt, preferred_path:, notice:)
        end
      end

      private

      sig { returns([String, T.nilable(String)]) }
      def setup_ruby_environment!
        Homebrew.install_bundler_gems!(setup_path: true)

        notice = unless Homebrew::EnvConfig.no_env_hints?
          <<~EOS
            Your shell has been configured to use Homebrew's Ruby environment.
            This includes the correct Ruby version, GEM_HOME, and bundle configuration.
            Tools like RuboCop, Sorbet, and RSpec are available via `bundle exec`.
            Hide these hints with `HOMEBREW_NO_ENV_HINTS=1` (see `man brew`).
            When done, type `exit`.
          EOS
        end

        ["brew ruby", notice]
      end

      sig { returns([String, T.nilable(String)]) }
      def setup_build_environment!
        ENV.activate_extensions!(env: args.env)

        if superenv?(args.env)
          ENV.deps = Formula.installed.select do |f|
            f.keg_only? && f.opt_prefix.directory?
          end
        end
        ENV.setup_build_environment
        if superenv?(args.env)
          # superenv stopped adding brew's bin but generally users will want it
          ENV["PATH"] = PATH.new(ENV.fetch("PATH")).insert(1, HOMEBREW_PREFIX/"bin").to_s
        end

        ENV["VERBOSE"] = "1" if args.verbose?

        notice = unless Homebrew::EnvConfig.no_env_hints?
          <<~EOS
            Your shell has been configured to use Homebrew's build environment;
            this should help you build stuff. Notably though, the system versions of
            gem and pip will ignore our configuration and insist on using the
            environment they were built under (mostly). Sadly, scons will also
            ignore our configuration.
            Hide these hints with `HOMEBREW_NO_ENV_HINTS=1` (see `man brew`).
            When done, type `exit`.
          EOS
        end

        ["brew", notice]
      end
    end
  end
end
