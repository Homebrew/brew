# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "tap"

module Homebrew
  module Cmd
    class TapCmd < AbstractCommand
      cmd_args do
        usage_banner "`tap` [<options>] [<protocol>`:`][<host>`@`][<user>`/`<repo>] [<URL>]"
        description <<~EOS
          Tap a repository containing formulae, casks, or external commands.
          If no arguments are provided, list all installed taps.

          With <host>`@`, <protocol>`:`, and <URL> unspecified, tap a repository from
          GitHub using HTTPS. Since so many taps are hosted on GitHub, this command is
          a shortcut for:

          `brew tap` <user>`/`<repo> `https://github.com/`<user>`/homebrew-`<repo>

          With <host>`@` or <protocol>`:` specified, tap a repository from anywhere
          using any transport protocol that `git`(1) handles (e.g. SSH, git, HTTP(S),
          FTP(S), rsync). Using them is a shortcut for:

          `brew tap` <user>`/`<repo> <protocol>`://`<host>`/`<user>`/homebrew-`<repo>

          When SSH is the specified <protocol>`:`, this is instead a shortcut for:

          `brew tap` <user>`/`<repo> `git@`<host>`:`<user>`/homebrew-`<repo>

          With <URL> specified, tap a repository from anywhere, using any transport
          protocol that `git`(1) handles. Unlike the one-argument form of `tap` which
          simplifies things, the two-argument form makes no assumptions.
        EOS
        switch "--custom-remote",
               description: "Install or change a tap with a custom remote. Useful for mirrors."
        switch "--repair",
               description: "Add missing symlinks to tap manpages and shell completions. Correct git remote " \
                            "refs for any taps where upstream HEAD branch has been renamed."
        switch "--eval-all",
               description: "Evaluate all available formulae, casks and aliases in the new tap to check their " \
                            "validity.",
               env:         :eval_all,
               odeprecated: true
        switch "-f", "--force",
               description: "Force install core taps even under API mode."

        named_args :tap, max: 2
      end

      sig { override.void }
      def run
        if args.repair?
          Tap.installed.each do |tap|
            tap.link_completions_and_manpages
            tap.fix_remote_configuration
          end
        elsif args.no_named?
          puts Tap.installed.sort_by(&:name)
        else
          begin
            tap = Tap.fetch(args.named.fetch(0))
            tap.install clone_target:  args.named.second,
                        custom_remote: args.custom_remote?,
                        quiet:         args.quiet?,
                        verify:        args.eval_all?,
                        force:         args.force?
          rescue Tap::InvalidNameError, Tap::InvalidShorthandError, TapRemoteMismatchError,
                 TapNoCustomRemoteError => e
            odie e
          rescue TapAlreadyTappedError
            nil
          end
        end
      end
    end
  end
end
