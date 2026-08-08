# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "fileutils"
require "system_command"
require "tap"
require "utils/uid"

module Homebrew
  module DevCmd
    class TapNew < AbstractCommand
      include FileUtils
      include SystemCommand::Mixin

      cmd_args do
        usage_banner "`tap-new` [<options>] <user>`/`<repo>"
        description <<~EOS
          Generate the template files for a new tap.
        EOS
        switch "--no-git",
               description: "Don't initialise a Git repository for the tap."
        flag   "--pull-label=",
               description: "Ignored; publishing pull requests is now manually dispatched.",
               odeprecated: true
        flag   "--branch=",
               description: "Initialise a Git repository and set up GitHub Actions workflows with the " \
                            "specified branch name (default: `main`)."
        switch "--github-packages",
               description: "Upload bottles to GitHub Packages."

        named_args :tap, number: 1
      end

      sig { override.void }
      def run
        branch = args.branch || "main"

        tap = args.named.to_taps.fetch(0)
        odie "Invalid tap name '#{tap}'" unless tap.path.to_s.match?(HOMEBREW_TAP_PATH_REGEX)
        odie "Tap is already installed!" if tap.installed?

        titleized_user = tap.user.dup
        titleized_repository = tap.repository.dup
        titleized_user[0] = T.must(titleized_user[0]).upcase
        titleized_repository[0] = T.must(titleized_repository[0]).upcase
        root_url = GitHubPackages.root_url(tap.user, "homebrew-#{tap.repository}") if args.github_packages?

        (tap.path/"Formula").mkpath

        readme = <<~MARKDOWN
          # #{titleized_user} #{titleized_repository}

          ## How do I install these formulae?

          `brew install #{tap}/<formula>`

          Or `brew tap #{tap}` and then `brew install <formula>`.

          Or, in a `brew bundle` `Brewfile`:

          ```ruby
          tap "#{tap}"
          brew "<formula>"
          ```

          ## Documentation

          `brew help`, `man brew` or check [Homebrew's documentation](https://docs.brew.sh).
        MARKDOWN
        write_path(tap, "README.md", readme)

        dependabot_yml = <<~YAML
          version: 2
          updates:
            - package-ecosystem: github-actions
              directory: "/"
              schedule:
                interval: weekly
              groups:
                github-actions:
                  patterns:
                    - "*"
        YAML

        tests_yml = render_workflow_template(
          "tap-new-tests.yml", branch:, github_packages: args.github_packages?, root_url:
        )
        publish_yml = render_workflow_template(
          "tap-new-publish.yml", branch:, github_packages: args.github_packages?
        )
        autobump_yml = render_workflow_template(
          "tap-new-autobump.yml", branch:, github_packages: args.github_packages?
        )
        (tap.path/".github/workflows").mkpath
        write_path(tap, ".github/dependabot.yml", dependabot_yml)
        write_path(tap, ".github/workflows/tests.yml", tests_yml)
        write_path(tap, ".github/workflows/publish.yml", publish_yml)
        write_path(tap, ".github/workflows/autobump.yml", autobump_yml)

        unless args.no_git?
          cd tap.path do |path|
            Utils::Git.set_name_email!
            Utils::Git.setup_gpg!

            safe_system "git", "init", "--initial-branch=#{branch}"

            args = []
            git_owner = File.stat(File.join(path, ".git")).uid
            if git_owner != Process.uid && git_owner == Process.euid
              # Under Homebrew user model, EUID is permitted to execute commands under the UID.
              # Root users are never allowed (see brew.sh).
              args << "-c" << "safe.directory=#{path}"
            end

            # Use the configuration of the original user, which will have author information and signing keys.
            env = { "HOME" => Utils::UID.uid_home }.compact
            env["TMPDIR"] = nil if (tmpdir = ENV.fetch("TMPDIR", nil)) && !File.writable_real?(tmpdir)
            system_command!("git", args: [*args, "add", "--all"], env:,
                            print_stdout: true, run_as_real_uid: true)
            system_command!("git", args: [*args, "commit", "-m", "Create #{tap} tap"], env:,
                            print_stdout: true, run_as_real_uid: true)
            system_command!("git", args: [*args, "branch", "-m", branch], env:,
                            print_stdout: true, run_as_real_uid: true)
          end
        end

        ohai "Created #{tap}"
        puts <<~EOS
          #{tap.path}

          When a pull request making changes to a formula (or formulae) becomes green
          (all checks passed), then you can publish the built bottles.
          To do so, run `brew pr-pull` locally or run the `brew pr-pull`
          workflow with the pull request number and, optionally, the pull
          request's expected head commit SHA.
        EOS
      end

      private

      sig {
        params(
          filename:        String,
          branch:          String,
          github_packages: T::Boolean,
          root_url:        T.nilable(String),
        ).returns(String)
      }
      def render_workflow_template(filename, branch:, github_packages:, root_url: nil)
        workflow = (HOMEBREW_LIBRARY_PATH.parent.parent/".github/workflows"/filename).read
        workflow.sub!("name: tap-new tests template", "name: brew test-bot")
        workflow.sub!("name: tap-new publish template", "name: brew pr-pull")
        workflow.sub!("name: tap-new autobump template", "name: brew bump")
        if filename == "tap-new-tests.yml"
          workflow.sub!("on:\n  workflow_dispatch:\n", <<~YAML)
            on:
              push:
                branches:
                  - #{branch}
              pull_request:
          YAML
        end
        # Pick a random 5 minute block in which to execute the autobump action to avoid peak GitHub loads
        hour = Random.rand(24)
        minute = Random.rand(12) * 5
        workflow.gsub!("this will be changed later and randomised by brew tap-new") do
          "Every day at #{hour}:#{minute} UTC"
        end
        workflow.gsub!("\"1 1 1 1 1\"") { "#{minute} #{hour} * * *" }

        workflow.sub!("    if: github.repository == ''\n", "")
        workflow.gsub!("TAP_NEW_BRANCH") { branch }
        workflow.gsub!("TAP_NEW_ROOT_URL_ARGUMENT") { root_url ? " --root-url=#{root_url}" : "" }
        unless github_packages
          workflow.gsub!(
            /^[ \t]*# tap-new-github-packages-start\n.*?^[ \t]*# tap-new-github-packages-end\n/m,
            "",
          )
        end
        workflow.gsub!(/^[ \t]*# tap-new-github-packages-(?:start|end)\n/, "")
        workflow
      end

      sig { params(tap: Tap, filename: T.any(String, Pathname), content: String).void }
      def write_path(tap, filename, content)
        path = tap.path/filename
        tap.path.mkpath
        odie "#{path} already exists" if path.exist?

        path.write content
      end
    end
  end
end
