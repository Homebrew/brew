# typed: strict
# frozen_string_literal: true

require "system_command"
require "tap"
require "utils/git"
require "utils/github"
require "utils/output"
require "utils/popen"

module Homebrew
  # @api internal
  module Bump
    extend SystemCommand::Mixin
    extend Utils::Output::Mixin

    class Commit < T::Struct
      const :sourcefile_path, Pathname
      const :old_contents, String
      const :commit_message, String
      const :additional_files, T::Array[Pathname], default: []
    end

    class BumpInfo < T::Struct
      const :package_tap, Tap
      const :branch_name, String
      const :pr_title, String
      const :pr_message, String
      const :commits, T::Array[Commit]
    end

    sig { params(command: String, user_message: T.nilable(String)).returns(String) }
    def self.pr_message(command, user_message:)
      pr_message = ""
      if user_message.present?
        pr_message += <<~EOS
          #{user_message}

          ---

        EOS
      end
      pr_message += "Created with `brew #{command}`."
      pr_message
    end

    sig { params(info: BumpInfo, dry_run: T::Boolean, no_fork: T::Boolean, fork_org: T.nilable(String), commit: T::Boolean).returns(T.nilable(String)) }
    def self.create_pr(info, dry_run: false, no_fork: false, fork_org: nil, commit: false)
      tap = info.package_tap
      branch = info.branch_name
      pr_message = info.pr_message
      pr_title = info.pr_title
      commits = info.commits

      tap_remote_repo = tap.remote_repository
      raise ArgumentError, "The tap #{tap.name} does not have a remote repository!" unless tap_remote_repo

      remote_branch = tap.git_repository.origin_branch_name
      raise "The tap #{tap.name} does not have a default branch!" if remote_branch.blank?

      remote_url = T.let(nil, T.nilable(String))
      username = T.let(nil, T.nilable(String))

      tap.path.cd do
        if no_fork
          remote_url = Utils.popen_read("git", "remote", "get-url", "--push", "origin").chomp
          username = tap.user
          add_auth_token_to_url!(remote_url)
        else
          begin
            remote_url, username = forked_repo_info!(tap_remote_repo, org: fork_org)
          rescue *GitHub::API::ERRORS => e
            commits.each do |commit|
              commit.sourcefile_path.atomic_write(commit.old_contents)
            end
            odie "Unable to fork: #{e.message}!"
          end
        end

        next if dry_run

        git_dir = Utils.popen_read("git", "rev-parse", "--git-dir").chomp
        shallow = !git_dir.empty? && File.exist?("#{git_dir}/shallow")
        safe_system "git", "fetch", "--unshallow", "origin" if !commit && shallow
        safe_system "git", "checkout", "--no-track", "-b", branch, "origin/#{remote_branch}" unless commit
        Utils::Git.set_name_email!
      end

      commits.each do |commit|
        sourcefile_path = commit.sourcefile_path
        commit_message = commit.commit_message
        additional_files = commit.additional_files

        sourcefile_path.parent.cd do
          git_dir = Utils.popen_read("git", "rev-parse", "--git-dir").chomp
          shallow = !git_dir.empty? && File.exist?("#{git_dir}/shallow")
          changed_files = [sourcefile_path]
          changed_files += additional_files if additional_files.present?

          if dry_run
            ohai "git checkout --no-track -b #{branch} origin/#{remote_branch}"
            ohai "git fetch --unshallow origin" if shallow
            ohai "git add #{changed_files.join(" ")}"
            ohai "git commit --no-edit --verbose --message='#{commit_message}' " \
                 "-- #{changed_files.join(" ")}"
            ohai "git push --set-upstream #{remote_url} #{branch}:#{branch}"
            ohai "git checkout --quiet -"
            ohai "create pull request with GitHub API (base branch: #{remote_branch})"
          else
            safe_system "git", "add", *changed_files
            Utils::Git.set_name_email!
            safe_system "git", "commit", "--no-edit", "--verbose",
                        "--message=#{commit_message}",
                        "--", *changed_files
          end
        end
      end

      return if commit || dry_run
      return unless remote_url

      tap.path.cd do
        system_command!("git", args:         ["push", "--set-upstream", remote_url, "#{branch}:#{branch}"],
                               print_stdout: true)
        safe_system "git", "checkout", "--quiet", "-"

        begin
          return GitHub.create_pull_request(tap_remote_repo, pr_title,
                                            "#{username}:#{branch}", remote_branch, pr_message)["html_url"]
        rescue *GitHub::API::ERRORS => e
          commits.each do |commit|
            commit.sourcefile_path.atomic_write(commit.old_contents)
          end
          odie "Unable to open pull request for #{tap_remote_repo}: #{e.message}!"
        end
      end
    end

    sig { params(url: String).returns(String) }
    private_class_method def self.add_auth_token_to_url!(url)
      if GitHub::API.credentials_type == :env_token
        url.sub!(%r{^https://github\.com/}, "https://x-access-token:#{GitHub::API.credentials}@github.com/")
      end
      url
    end

    sig { params(tap_remote_repo: String, org: T.nilable(String)).returns([String, String]) }
    private_class_method def self.forked_repo_info!(tap_remote_repo, org: nil)
      response = GitHub.create_fork(tap_remote_repo, org:)
      # GitHub API responds immediately but fork takes a few seconds to be ready.
      sleep 1 until GitHub.fork_exists?(tap_remote_repo, org:)
      remote_url = if system("git", "config", "--local", "--get-regexp", "remote..*.url", "git@github.com:.*")
        response.fetch("ssh_url")
      else
        add_auth_token_to_url!(response.fetch("clone_url"))
      end
      username = response.fetch("owner").fetch("login")
      [remote_url, username]
    end
  end
end
