# typed: strict
# frozen_string_literal: true

require "abstract_command"

module Homebrew
  module DevCmd
    class Release < AbstractCommand
      cmd_args do
        description <<~EOS
          Create a new draft Homebrew/brew release with the appropriate version number and release notes.

          By default, `brew release` will bump the patch version number. Pass
          `--major` or `--minor` to bump the major or minor version numbers, respectively.
          The command will fail if the previous major or minor release was made less than
          one month ago.

          *Note:* Requires write access to the Homebrew/brew repository.
        EOS
        switch "--major",
               description: "Create a major release."
        switch "--minor",
               description: "Create a minor release."

        conflicts "--major", "--minor"

        named_args :none
      end

      sig { override.void }
      def run
        safe_system "git", "-C", HOMEBREW_REPOSITORY, "fetch", "origin" if Homebrew::EnvConfig.no_auto_update?

        require "utils/github"

        begin
          latest_release = GitHub.get_latest_release "Homebrew", "brew"
        rescue GitHub::API::HTTPNotFoundError
          odie "No existing releases found!"
        end
        latest_version = Version.new latest_release["tag_name"]

        if args.major? || args.minor?
          one_month_ago = Date.today << 1
          latest_major_minor_release = begin
            GitHub.get_release "Homebrew", "brew", "#{latest_version.major_minor}.0"
          rescue GitHub::API::HTTPNotFoundError
            nil
          end

          if latest_major_minor_release.blank?
            opoo "Unable to determine the release date of the latest major/minor release."
          elsif Date.parse(latest_major_minor_release["published_at"]) > one_month_ago
            odie "The latest major/minor release was less than one month ago."
          end
        end

        new_version = if args.major?
          Version.new "#{latest_version.major.to_i + 1}.0.0"
        elsif args.minor?
          Version.new "#{latest_version.major}.#{latest_version.minor.to_i + 1}.0"
        else
          Version.new "#{latest_version.major}.#{latest_version.minor}.#{latest_version.patch.to_i + 1}"
        end.to_s

        if args.major? || args.minor?
          latest_major_minor_version = "#{latest_version.major}.#{latest_version.minor.to_i}.0"
          ohai "Release notes since #{latest_major_minor_version} for #{new_version} blog post:"
          # release notes without usernames, new contributors, or extra lines
          blog_post_notes = GitHub.generate_release_notes("Homebrew", "brew", new_version,
                                                          previous_tag: latest_major_minor_version)["body"]
          blog_post_notes = blog_post_notes.lines.filter_map do |line|
            next unless (match = line.match(/^\* (.*) by @[\w-]+ in (.*)$/))

            "- [#{match[1]}](#{match[2]})"
          end.sort
          puts blog_post_notes
        end

        release_notes = if args.major? || args.minor?
          "Release notes for this release can be found on the [Homebrew blog](https://brew.sh/blog/#{new_version}).\n"
        else
          ""
        end
        release_notes += GitHub.generate_release_notes("Homebrew", "brew", new_version,
                                                       previous_tag: latest_version)["body"]

        # Get the current commit SHA
        current_sha = Utils.safe_popen_read("git", "-C", HOMEBREW_REPOSITORY, "rev-parse", "HEAD").strip

        ohai "Triggering pkg-installer workflow for #{new_version}"
        begin
          GitHub.workflow_dispatch_event("Homebrew", "brew", "pkg-installer.yml", "master",
                                         tag: new_version, release_notes:)
        rescue *GitHub::API::ERRORS => e
          odie "Unable to trigger workflow: #{e.message}!"
        end

        ohai "Waiting for pkg-installer workflow to complete..."
        opoo "This may take several minutes. You can monitor progress at:"
        puts "https://github.com/Homebrew/brew/actions/workflows/pkg-installer.yml"

        # Poll for workflow completion
        max_attempts = 60 # 30 minutes (30 seconds * 60)
        attempt = 0
        workflow_completed = T.let(false, T::Boolean)
        workflow_run_url = nil

        while attempt < max_attempts
          sleep 30
          attempt += 1

          # Check workflow runs for the commit SHA
          begin
            runs_url = "#{GitHub::API_URL}/repos/Homebrew/brew/actions/workflows/pkg-installer.yml/runs"
            response = GitHub::API.open_rest("#{runs_url}?event=workflow_dispatch&per_page=5")

            if response["workflow_runs"]&.any?
              # Find the most recent workflow_dispatch run for our commit
              run = response["workflow_runs"].find { |r| r["head_sha"] == current_sha }

              if run
                workflow_run_url = run["html_url"]
                status = run["status"]
                conclusion = run["conclusion"]

                if status == "completed"
                  if conclusion == "success"
                    ohai "Workflow completed successfully!"
                    workflow_completed = true
                  else
                    opoo "Workflow completed with status: #{conclusion}"
                    opoo "Check the workflow run at: #{workflow_run_url}"
                  end
                  break
                elsif (attempt % 4).zero?
                  print "."
                end
              end
            end
          rescue *GitHub::API::ERRORS => e
            opoo "Error checking workflow status: #{e.message}" if attempt == 1
          end
        end

        unless workflow_completed
          opoo "Workflow did not complete in time or failed."
          opoo "Please check the workflow status before publishing the release."
          puts workflow_run_url if workflow_run_url
        end

        # Open the release page
        release_url = "https://github.com/Homebrew/brew/releases/tag/#{new_version}"
        puts release_url
        exec_browser release_url
      end
    end
  end
end
