# typed: true
# frozen_string_literal: true

require "cli/parser"
module Homebrew
  sig { returns(CLI::Parser) }
  def self.update_test_args
    Homebrew::CLI::Parser.new do
      description <<~EOS
        Run a test of `brew update` with a new repository clone.
        If no options are passed, use `origin/master` as the start commit.
      EOS
      switch "--to-tag",
             description: "Set `HOMEBREW_UPDATE_TO_TAG` to test updating between tags."
      switch "--keep-tmp",
             description: "Retain the temporary directory containing the new repository clone."
      flag   "--commit=",
             description: "Use the specified <commit> as the start commit."
      flag   "--before=",
             description: "Use the commit at the specified <date> as the start commit."

      named_args :none
    end
  end

  def self.update_test
    args = update_test_args.parse

    # Avoid `update-report.rb` tapping Homebrew/homebrew-core
    ENV["HOMEBREW_UPDATE_TEST"] = "1"

    # Avoid accidentally updating when we don't expect it.
    ENV["HOMEBREW_NO_AUTO_UPDATE"] = "1"

    # Use default behaviours
    ENV["HOMEBREW_AUTO_UPDATE_SECS"] = nil
    ENV["HOMEBREW_DEVELOPER"] = nil
    ENV["HOMEBREW_DEV_CMD_RUN"] = nil
    ENV["HOMEBREW_MERGE"] = nil
    ENV["HOMEBREW_NO_UPDATE_CLEANUP"] = nil

    branch = if args.to_tag?
      ENV["HOMEBREW_UPDATE_TO_TAG"] = "1"
      "stable"
    else
      ENV["HOMEBREW_UPDATE_TO_TAG"] = nil
      "master"
    end

    # Utils.popen_read returns a String without a block argument, but that isn't easily typed. We thus label this
    # as untyped for now.
    start_commit = T.let("", T.untyped)
    end_commit = "HEAD"
    cd HOMEBREW_REPOSITORY do
      start_commit = if (commit = args.commit)
        commit
      elsif (date = args.before)
        Utils.popen_read("git", "rev-list", "-n1", "--before=#{date}", "origin/master").chomp
      elsif args.to_tag?
        tags = git_tags
        current_tag, previous_tag, = tags.lines
        current_tag = current_tag.to_s.chomp
        odie "Could not find current tag in:\n#{tags}" if current_tag.empty?
        # ^0 ensures this points to the commit rather than the tag object.
        end_commit = "#{current_tag}^0"

        previous_tag = previous_tag.to_s.chomp
        odie "Could not find previous tag in:\n#{tags}" if previous_tag.empty?
        # ^0 ensures this points to the commit rather than the tag object.
        "#{previous_tag}^0"
      else
        Utils.popen_read("git", "merge-base", "origin/master", end_commit).chomp
      end
      odie "Could not find start commit!" if start_commit.empty?

      start_commit = Utils.popen_read("git", "rev-parse", start_commit).chomp
      odie "Could not find start commit!" if start_commit.empty?

      end_commit = T.cast(Utils.popen_read("git", "rev-parse", end_commit).chomp, String)
      odie "Could not find end commit!" if end_commit.empty?

      if Utils.popen_read("git", "branch", "--list", "master").blank?
        safe_system "git", "branch", "master", "origin/master"
      end
    end

    puts <<~EOS
      Start commit: #{start_commit}
        End commit: #{end_commit}
    EOS

    mkdir "update-test"
    chdir "update-test" do
      curdir = Pathname.new(Dir.pwd)

      oh1 "Preparing test environment..."
      # copy Homebrew installation
      safe_system "git", "clone", "#{HOMEBREW_REPOSITORY}/.git", ".",
                  "--branch", "master", "--single-branch"

      # set git origin to another copy
      safe_system "git", "clone", "#{HOMEBREW_REPOSITORY}/.git", "remote.git",
                  "--bare", "--branch", "master", "--single-branch"
      safe_system "git", "config", "remote.origin.url", "#{curdir}/remote.git"
      ENV["HOMEBREW_BREW_GIT_REMOTE"] = "#{curdir}/remote.git"

      # force push origin to end_commit
      safe_system "git", "checkout", "-B", "master", end_commit
      safe_system "git", "push", "--force", "origin", "master"

      # set test copy to start_commit
      safe_system "git", "reset", "--hard", start_commit

      # update ENV["PATH"]
      ENV["PATH"] = PATH.new(ENV.fetch("PATH")).prepend(curdir/"bin").to_s

      # run brew help to install portable-ruby (if needed)
      quiet_system "brew", "help"

      # run brew update
      oh1 "Running `brew update`..."
      safe_system "brew", "update", "--verbose", "--debug"
      actual_end_commit = Utils.popen_read("git", "rev-parse", branch).chomp
      if actual_end_commit != end_commit
        start_log = Utils.popen_read("git", "log", "-1", "--decorate", "--oneline", start_commit).chomp
        end_log = Utils.popen_read("git", "log", "-1", "--decorate", "--oneline", end_commit).chomp
        actual_log = Utils.popen_read("git", "log", "-1", "--decorate", "--oneline", actual_end_commit).chomp
        odie <<~EOS
          `brew update` didn't update #{branch}!
          Start commit:        #{start_log}
          Expected end commit: #{end_log}
          Actual end commit:   #{actual_log}
        EOS
      end
    end
  ensure
    FileUtils.rm_rf "update-test" unless args.keep_tmp?
  end

  def self.git_tags
    tags = Utils.popen_read("git", "tag", "--list", "--sort=-version:refname")
    if tags.blank?
      tags = if (HOMEBREW_REPOSITORY/".git/shallow").exist?
        safe_system "git", "fetch", "--tags", "--depth=1"
        Utils.popen_read("git", "tag", "--list", "--sort=-version:refname")
      end
    end
    tags
  end
end

require "extend/os/dev-cmd/update-test"
