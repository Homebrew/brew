# typed: false
# frozen_string_literal: true

require "timeout"
require "cask/download"
require "cask/installer"
require "cask/cask_loader"
require "cli/parser"
require "tap"
require "unversioned_cask_checker"

module Homebrew
  extend T::Sig

  extend SystemCommand::Mixin

  sig { returns(CLI::Parser) }
  def self.bump_unversioned_casks_args
    Homebrew::CLI::Parser.new do
      description <<~EOS
        Check all casks with unversioned URLs in a given <tap> for updates.
      EOS
      switch "-n", "--dry-run",
             description: "Do everything except caching state and opening pull requests."
      flag   "--limit=",
             description: "Maximum runtime in minutes."
      flag   "--state-file=",
             description: "File for caching state."

      named_args [:cask, :tap], min: 1
    end
  end

  sig { void }
  def self.bump_unversioned_casks
    args = bump_unversioned_casks_args.parse

    state_file = if args.state_file.present?
      Pathname(args.state_file).expand_path
    else
      HOMEBREW_CACHE/"bump_unversioned_casks.json"
    end
    state_file.dirname.mkpath

    state = state_file.exist? ? JSON.parse(state_file.read) : {}

    casks = args.named.to_paths(only: :cask, recurse_tap: true).map { |path| Cask::CaskLoader.load(path) }

    unversioned_casks = casks.select { |cask| cask.url&.unversioned? }

    ohai "Unversioned Casks: #{unversioned_casks.count} (#{state.size} cached)"

    checked, unchecked = unversioned_casks.partition { |c| state.key?(c.full_name) }

    queue = Queue.new

    # Start with random casks which have not been checked.
    unchecked.shuffle.each do |c|
      queue.enq c
    end

    # Continue with previously checked casks, ordered by when they were last checked.
    checked.sort_by { |c| state.dig(c.full_name, "check_time") }.each do |c|
      queue.enq c
    end

    limit = args.limit.presence&.to_i
    end_time = Time.now + limit.minutes if limit

    until queue.empty? || (end_time && end_time < Time.now)
      cask = queue.deq

      key = cask.full_name

      new_state = bump_unversioned_cask(cask, state: state.fetch(key, {}), dry_run: args.dry_run?)

      next unless new_state

      state[key] = new_state

      state_file.atomic_write JSON.pretty_generate(state) unless args.dry_run?
    end
  end

  sig {
    params(cask: Cask::Cask, state: T::Hash[String, T.untyped], dry_run: T.nilable(T::Boolean))
      .returns(T.nilable(T::Hash[String, T.untyped]))
  }
  def self.bump_unversioned_cask(cask, state:, dry_run:)
    ohai "Checking #{cask.full_name}"

    unversioned_cask_checker = UnversionedCaskChecker.new(cask)

    if !unversioned_cask_checker.single_app_cask? &&
       !unversioned_cask_checker.single_pkg_cask? &&
       !unversioned_cask_checker.single_qlplugin_cask?
      opoo "Skipping, not a single-app or PKG cask."
      return
    end

    last_check_time = state["check_time"]&.yield_self { |t| Time.parse(t) }

    check_time = Time.now
    if last_check_time && check_time < (last_check_time + 1.day)
      opoo "Skipping, already checked within the last 24 hours."
      return
    end

    last_sha256 = state["sha256"]
    last_time = state["time"]&.yield_self { |t| Time.parse(t) }
    last_file_size = state["file_size"]

    download = Cask::Download.new(cask)
    time, file_size = begin
      download.time_file_size
    rescue
      [nil, nil]
    end

    if last_time != time || last_file_size != file_size
      sha256 = begin
        Timeout.timeout(5.minutes) do
          unversioned_cask_checker.installer.download.sha256
        end
      rescue => e
        onoe e
      end

      if sha256.present? && last_sha256 != sha256
        version = begin
          Timeout.timeout(1.minute) do
            unversioned_cask_checker.guess_cask_version
          end
        rescue Timeout::Error
          onoe "Timed out guessing version for cask '#{cask}'."
        end

        if version
          if cask.version == version
            oh1 "Cask #{cask} is up-to-date at #{version}"
          else
            bump_cask_pr_args = [
              "bump-cask-pr",
              "--version", version.to_s,
              "--sha256", ":no_check",
              "--message", "Automatic update via `brew bump-unversioned-casks`.",
              cask.sourcefile_path
            ]

            if dry_run
              bump_cask_pr_args << "--dry-run"
              oh1 "Would bump #{cask} from #{cask.version} to #{version}"
            else
              oh1 "Bumping #{cask} from #{cask.version} to #{version}"
            end

            begin
              system_command! HOMEBREW_BREW_FILE, args: bump_cask_pr_args
            rescue ErrorDuringExecution => e
              onoe e
            end
          end
        end
      end
    end

    {
      "sha256"     => sha256,
      "check_time" => check_time.iso8601,
      "time"       => time&.iso8601,
      "file_size"  => file_size,
    }
  end
end
