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

    # Formulae or casks selected in a manual autobump run, including core aliases.
    sig { params(casks: T::Boolean).returns(T::Array[String]) }
    private_class_method def self.requested_packages(casks:)
      require "shellwords"

      type, tap = casks ? %w[casks cask] : %w[formulae core]
      input = JSON.parse(File.read(ENV.fetch("GITHUB_EVENT_PATH"))).dig("inputs", type).to_s
      Shellwords.split(input).map do |arg|
        name = arg.sub(%r{\Ahomebrew/#{tap}/}i, "")
        raise ArgumentError, "Expected a homebrew/#{tap} name." unless name.match?(/\A[a-z0-9][a-z0-9+._@-]*\z/)

        name
      end
    end

    # Collect completed bumps even when another formula or cask failed.
    sig { params(file: String, casks: T::Boolean).void }
    def self.prepare_prs(file, casks: false)
      names = requested_packages(casks:)
      type, tap, *options = casks ? %w[casks Homebrew/cask] : %w[formulae Homebrew/core --bump-synced]
      selection = names.empty? ? ["--auto", "--tap=#{tap}"] : ["--", *names]
      Dir.mktmpdir do |directory|
        success = system HOMEBREW_BREW_FILE, "bump", "--#{type}", *options, "--write-pr-to=#{directory}",
                         *selection
        Homebrew.failed = true unless success
        files = Pathname(directory).glob("*.json")
        next if files.empty?

        max_matrix_jobs = 256
        opoo "Remaining bumps will be retried on the next run." if files.size > max_matrix_jobs
        proposals = files.first(max_matrix_jobs).to_h { |path| [path.basename(".json").to_s, JSON.parse(path.read)] }
        Pathname(file).atomic_write(JSON.generate(proposals))
        File.open(ENV.fetch("GITHUB_OUTPUT"), "a") { |io| io.puts "#{type}=#{proposals.keys.to_json}" }
      end
    end

    # Apply a prepared bump using the checked-out formulae or casks and workflow inputs as the reference.
    sig { params(file: String, name: String, casks: T::Boolean).void }
    def self.commit_prepared_pr(file, name, casks: false)
      tap = casks ? CoreCaskTap.instance : CoreTap.instance
      type = casks ? "casks" : "formulae"
      requested = requested_packages(casks:)
      allowed = if requested.empty?
        tap.autobump
      else
        requested.map { |arg| tap.alias_table.fetch(arg, arg) }
      end
      odie "Unexpected #{type} in the prepared bump." unless allowed.include?(name)

      proposal = JSON.parse(File.read(file)).fetch(name)
      version, packages = proposal.fetch_values("version", type)
      # `brew bump-cask-pr` replaces the separators allowed in cask versions in branch names.
      version_separators = casks ? ",:" : ""
      branch = "bump-#{name}-#{version.tr(version_separators, "-")}"
      group = tap.synced_versions_formulae.find { |members| members.include?(name) } || [name]
      if proposal.fetch("base") != ENV.fetch("GITHUB_SHA") || tap.git_head != proposal.fetch("base") ||
         !version.match?(/\A[[:alnum:]][[:alnum:].+_#{version_separators}-]*\z/) ||
         !packages.key?(name) || (packages.keys - group).present?
        odie "Unexpected #{type}, version or base commit in the prepared bump."
      end
      if casks
        # `brew bump-cask-pr` shortens versions in commit titles and names single-architecture bumps.
        title = proposal.fetch("title")
        versions = Regexp.union(version, version.split(",").fetch(0))
        architecture = title.match(/\A#{Regexp.escape(name)} #{versions}(?: \((arm|intel) only\))?\z/)
        odie "Unexpected title in the prepared bump." unless architecture
        branch += "-#{architecture[1]}-only" if architecture[1]
      end
      SystemCommand.safe_system "git", "check-ref-format", "refs/heads/#{branch}"
      return if pull_request_for_branch?(tap, branch)

      require "utils/ast"

      destinations = Set.new
      changes = packages.map do |package_name, contents|
        path = (casks ? tap.cask_files_by_name : tap.formula_files_by_name).fetch(package_name)
        unless (casks ? Utils::AST::CaskAST : Utils::AST::FormulaAST).valid_bump?(path.read, contents, version:)
          odie "Unexpected changes in the prepared bump for #{package_name}."
        end
        aliases = tap.alias_reverse_table.fetch(package_name, [])
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
          commit_files([path, *aliases], title || "#{path.basename(".rb")} #{version}")
        end
      end
      pr = proposal.slice("title", "body")
      File.open(ENV.fetch("GITHUB_OUTPUT"), "a") { |io| io.puts "branch=#{branch}", "pr=#{pr.to_json}" }
    end

    # Reuse a matching signed push from an earlier attempt or replace a branch pushed without a pull request.
    sig { params(casks: T::Boolean).void }
    def self.sign_pr(casks: false)
      tap = casks ? CoreCaskTap.instance : CoreTap.instance
      tap.path.cd do
        branch = Utils.safe_popen_read("git", "branch", "--show-current").chomp
        odie "Expected a bump branch." unless branch.start_with?("bump-")
        base = ENV.fetch("GITHUB_SHA")
        ref = "refs/heads/#{branch}"
        outputs = ["push=true"]
        if Utils.safe_popen_read("git", "ls-remote", "--refs", "origin", ref).present?
          SystemCommand.safe_system "git", "fetch", "origin", ref
          local, remote = %w[HEAD FETCH_HEAD].map do |head|
            Utils.safe_popen_read("git", "log", "--format=%T %s", "#{base}..#{head}")
          end
          commits = Utils.safe_popen_read("git", "rev-list", "#{base}..FETCH_HEAD").lines(chomp: true)
          if SystemCommand.quiet_system("git", "merge-base", "--is-ancestor", base, "FETCH_HEAD") &&
             local.present? && remote == local && SystemCommand.quiet_system("git", "verify-commit", *commits)
            return
          end

          odie "A pull request already uses #{branch}." if pull_request_for_branch?(tap, branch)

          opoo "Replacing #{branch}, which was pushed without a pull request."
          outputs << "force=true"
        end
        Utils::Git.set_name_email!(author: false)
        SystemCommand.safe_system "git", "rebase", "--force-rebase", "--gpg-sign", base
        File.open(ENV.fetch("GITHUB_OUTPUT"), "a") { |io| io.puts(*outputs) }
      end
    end

    # Whether the tap has a pull request from this branch, open or closed.
    sig { params(tap: Tap, branch: String).returns(T::Boolean) }
    private_class_method def self.pull_request_for_branch?(tap, branch)
      odie "Cannot check pull requests as `$HOMEBREW_NO_GITHUB_API` is set!" if Homebrew::EnvConfig.no_github_api?

      url = GitHub.url_to("repos", tap.full_name, "pulls")
      url.query = URI.encode_www_form(head: "Homebrew:#{branch}", base: "main", state: "all")
      GitHub::API.open_rest(url).present?
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
