# typed: strict
# frozen_string_literal: true

require "system_command"
require "tap"
require "utils/formatter"
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
        SystemCommand.safe_system "git", "fetch", "--unshallow", "origin" if !commit && shallow
        unless commit
          SystemCommand.safe_system "git", "checkout", "--no-track", "-b", branch,
                                    "origin/#{remote_branch}"
        end
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
            ohai "git push --set-upstream #{redacted_url(remote_url)} #{branch}:#{branch}"
            ohai "git checkout --quiet -"
            ohai "create pull request with GitHub API (base branch: #{remote_branch})"
          else
            commit_files(changed_files, commit_message)
          end
        end
      end

      return if commit || dry_run
      return unless remote_url

      tap.path.cd do
        system_command!("git", args:         ["push", "--set-upstream", remote_url, "#{branch}:#{branch}"],
                               print_stdout: true)
        SystemCommand.safe_system "git", "checkout", "--quiet", "-"

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

    sig { params(paths: T::Array[Pathname], message: String).void }
    def self.commit_files(paths, message)
      SystemCommand.safe_system "git", "add", args: paths
      Utils::Git.set_name_email!
      SystemCommand.safe_system "git", "commit", "--no-edit", "--verbose", "--message=#{message}", "--", args: paths
    end

    # Formulae selected in a manual autobump run, including core aliases.
    sig { returns(T::Array[String]) }
    private_class_method def self.requested_formulae
      require "shellwords"

      input = JSON.parse(File.read(ENV.fetch("GITHUB_EVENT_PATH"))).dig("inputs", "formulae").to_s
      Shellwords.split(input).map do |arg|
        name = arg.sub(%r{\Ahomebrew/core/}i, "")
        raise ArgumentError, "Expected a core formula name." unless name.match?(/\A[a-z0-9][a-z0-9+._@-]*\z/)

        name
      end
    end

    # Collect completed bumps even when another formula failed.
    sig { params(file: String).void }
    def self.prepare_prs(file)
      names = requested_formulae
      selection = names.empty? ? ["--auto", "--tap=Homebrew/core"] : ["--", *names]
      Dir.mktmpdir do |directory|
        success = system HOMEBREW_BREW_FILE, "bump", "--formulae", "--bump-synced", "--write-pr-to=#{directory}",
                         *selection
        Homebrew.failed = true unless success
        files = Pathname(directory).glob("*.json")
        next if files.empty?

        max_matrix_jobs = 256
        opoo "Remaining bumps will be retried on the next run." if files.size > max_matrix_jobs
        proposals = files.first(max_matrix_jobs).to_h { |path| [path.basename(".json").to_s, JSON.parse(path.read)] }
        Pathname(file).atomic_write(JSON.generate(proposals))
        File.open(ENV.fetch("GITHUB_OUTPUT"), "a") { |io| io.puts "formulae=#{proposals.keys.to_json}" }
      end
    end

    # Apply a prepared bump using the checked-out formulae and workflow inputs as the reference.
    sig { params(file: String, name: String).void }
    def self.commit_prepared_pr(file, name)
      tap = CoreTap.instance
      requested = requested_formulae
      allowed = if requested.empty?
        tap.autobump
      else
        requested.map { |arg| tap.alias_table.fetch(arg, arg) }
      end
      odie "Unexpected formula in the prepared bump." unless allowed.include?(name)

      proposal = JSON.parse(File.read(file)).fetch(name)
      version, formulae = proposal.fetch_values("version", "formulae")
      branch = "bump-#{name}-#{version}"
      group = tap.synced_versions_formulae.find { |members| members.include?(name) } || [name]
      if proposal.fetch("base") != ENV.fetch("GITHUB_SHA") || tap.git_head != proposal.fetch("base") ||
         !version.match?(/\A[[:alnum:]][[:alnum:].+_-]*\z/) ||
         !formulae.key?(name) || (formulae.keys - group).present?
        odie "Unexpected formulae, version or base commit in the prepared bump."
      end
      SystemCommand.safe_system "git", "check-ref-format", "refs/heads/#{branch}"
      url = GitHub.url_to("repos", "Homebrew/homebrew-core", "pulls")
      url.query = URI.encode_www_form(head: "Homebrew:#{branch}", base: "main", state: "all")
      return if GitHub::API.open_rest(url).present?

      require "utils/ast"

      destinations = Set.new
      changes = formulae.map do |formula_name, contents|
        path = tap.formula_files_by_name.fetch(formula_name)
        unless Utils::AST::FormulaAST.valid_bump?(path.read, contents, version:)
          odie "Unexpected changes in the prepared bump for #{formula_name}."
        end
        aliases = tap.alias_reverse_table.fetch(formula_name, [])
        rename = Array(alias_update_pair(aliases, Version.new(version))).map { |a| tap.alias_dir/a }
        destination = rename.last
        if destination && (destination.exist? || destination.symlink? || !destinations.add?(destination))
          odie "Alias #{destination.basename} already exists or is proposed twice."
        end

        [path, contents, rename]
      end
      tap.path.cd do
        SystemCommand.safe_system "git", "switch", "-c", branch
        changes.each do |path, contents, aliases|
          path.atomic_write(contents)
          source, destination = aliases
          FileUtils.mv source, destination if source && destination
          commit_files([path, *aliases], "#{path.basename(".rb")} #{version}")
        end
      end
      pr = proposal.slice("title", "body")
      File.open(ENV.fetch("GITHUB_OUTPUT"), "a") { |io| io.puts "branch=#{branch}", "pr=#{pr.to_json}" }
    end

    # A rerun can open the PR for a previous push after checking its commits.
    sig { void }
    def self.sign_pr
      CoreTap.instance.path.cd do
        branch = Utils.safe_popen_read("git", "branch", "--show-current").chomp
        odie "Expected a bump branch." unless branch.start_with?("bump-")
        base = ENV.fetch("GITHUB_SHA")
        ref = "refs/heads/#{branch}"
        if Utils.safe_popen_read("git", "ls-remote", "--refs", "origin", ref).empty?
          Utils::Git.set_name_email!(author: false)
          SystemCommand.safe_system "git", "rebase", "--force-rebase", "--gpg-sign", base
          File.open(ENV.fetch("GITHUB_OUTPUT"), "a") { |io| io.puts "push=true" }
        else
          SystemCommand.safe_system "git", "fetch", "origin", ref
          SystemCommand.safe_system "git", "merge-base", "--is-ancestor", base, "FETCH_HEAD"
          local, remote = %w[HEAD FETCH_HEAD].map do |head|
            Utils.safe_popen_read("git", "log", "--format=%T %s", "#{base}..#{head}")
          end
          odie "The remote branch differs from the prepared bump." if local.blank? || remote != local

          commits = Utils.safe_popen_read("git", "rev-list", "#{base}..FETCH_HEAD").lines(chomp: true)
          SystemCommand.safe_system "git", "verify-commit", *commits
        end
      end
    end

    sig { params(aliases: T::Array[String], new_formula_version: Version).returns(T.nilable(T::Array[String])) }
    def self.alias_update_pair(aliases, new_formula_version)
      versioned_alias = aliases.grep(/^.*@\d+(\.\d+)?$/).first
      return if versioned_alias.nil?

      name, old_alias_version = versioned_alias.split("@")
      return if old_alias_version.blank?

      new_alias_regex = if old_alias_version.split(".").length == 1
        /^\d+/
      else
        /^\d+\.\d+/
      end
      new_alias_version, = *new_formula_version.to_s.match(new_alias_regex)
      return if new_alias_version.blank?
      return if Version.new(new_alias_version) <= Version.new(old_alias_version)

      [versioned_alias, "#{name}@#{new_alias_version}"]
    end

    sig { params(url: String).returns(String) }
    private_class_method def self.add_auth_token_to_url!(url)
      if GitHub::API.credentials_type == :env_token
        url.sub!(%r{^https://github\.com/}, "https://x-access-token:#{GitHub::API.credentials}@github.com/")
      end
      url
    end

    # Redact any token `add_auth_token_to_url!` embedded, so dry-run output doesn't leak it.
    sig { params(url: T.nilable(String)).returns(String) }
    def self.redacted_url(url)
      Formatter.redact_secrets(url.to_s, [GitHub::API.credentials].compact)
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
