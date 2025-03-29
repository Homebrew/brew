# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "extend/ENV"
require "formula"

module Homebrew
  module DevCmd
    class Sh < AbstractCommand
      cmd_args do
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

      sig { override.void }
      def run
        ENV.activate_extensions!(env: args.env)

        if superenv?(args.env)
          T.cast(ENV, Superenv).deps = Formula.installed.select { |f| f.keg_only? && f.opt_prefix.directory? }
        end
        ENV.setup_build_environment
        if superenv?(args.env)
          # superenv stopped adding brew's bin but generally users will want it
          ENV["PATH"] = PATH.new(ENV.fetch("PATH")).insert(1, HOMEBREW_PREFIX/"bin").to_s
        end

        ENV["VERBOSE"] = "1" if args.verbose?

        preferred_path = Utils::Shell.preferred_path(default: "/bin/bash")

        if args.cmd.present?
          safe_system(preferred_path, "-c", args.cmd)
        elsif args.named.present?
          safe_system(preferred_path, args.named.first)
        else
          notice = unless Homebrew::EnvConfig.no_env_hints?
            <<~EOS
              Your shell has been configured to use Homebrew's build environment;
              this should help you build stuff. Notably though, the system versions of
              gem and pip will ignore our configuration and insist on using the
              environment they were built under (mostly). Sadly, scons will also
              ignore our configuration.
              Hide these hints with HOMEBREW_NO_ENV_HINTS (see `man brew`).
              When done, type `exit`.
            EOS
          end
          system Utils::Shell.shell_with_prompt("brew", preferred_path:, notice:)
        end
      end
    end
  end
end
