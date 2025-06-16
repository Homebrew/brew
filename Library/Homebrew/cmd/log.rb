# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "fileutils"

module Homebrew
  module Cmd
    class Log < AbstractCommand
      include FileUtils

      cmd_args do
        description <<~EOS
          Show the `git log` for <formula> or <cask>, or show the log for the Homebrew repository
          if no formula or cask is provided.
        EOS
        switch "-p", "-u", "--patch",
               description: "Also print patch from commit."
        switch "--stat",
               description: "Also print diffstat from commit."
        switch "--oneline",
               description: "Print only one line per commit."
        switch "-1",
               description: "Print only one commit."
        flag   "-n", "--max-count=",
               description: "Print only a specified number of commits."
        switch "--formula", "--formulae",
               description: "Treat all named arguments as formulae."
        switch "--cask", "--casks",
               description: "Treat all named arguments as casks."

        conflicts "-1", "--max-count"
        conflicts "--formula", "--cask"

        named_args [:formula, :cask], max: 1, without_api: true
      end

      sig { override.void }
      def run
        # As this command is simplifying user-run commands then let's just use a
        # user path, too.
        ENV["PATH"] = PATH.new(ORIGINAL_PATHS).to_s

        if args.no_named?
          git_log(HOMEBREW_REPOSITORY)
        else
          path = T.must(args.named.to_paths.first)
          tap = Tap.from_path(path)
          git_log path.dirname, path, tap
        end
      end

      private

      sig { params(cd_dir: Pathname, path: T.nilable(Pathname), tap: T.nilable(Tap)).void }
      def git_log(cd_dir, path = nil, tap = nil)
        cd cd_dir do
          repo = Utils.popen_read("git", "rev-parse", "--show-toplevel").chomp
          if tap
            name = tap.to_s
            git_cd = "$(brew --repo #{tap})"
          elsif cd_dir == HOMEBREW_REPOSITORY
            name = "Homebrew/brew"
            git_cd = "$(brew --repo)"
          else
            name, git_cd = cd_dir
          end

          if File.exist? "#{repo}/.git/shallow"
            opoo <<~EOS
              #{name} is a shallow clone so only partial output will be shown.
              To get a full clone, run:
                git -C "#{git_cd}" fetch --unshallow
            EOS
          end

          git_args = []
          git_args << "--patch" if args.patch?
          git_args << "--stat" if args.stat?
          git_args << "--oneline" if args.oneline?
          git_args << "-1" if args.public_send(:"1?")
          git_args << "--max-count" << args.max_count if args.max_count
          git_args += ["--follow", "--", path] if path&.file?
          system "git", "log", *git_args
        end
      end
    end
  end
end
