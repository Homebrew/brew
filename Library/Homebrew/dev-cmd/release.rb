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

          Without `--force`, this command will just output the release notes without creating
          the release or triggering the workflow.

          *Note:* Requires write access to the Homebrew/brew repository.
        EOS
        switch "--major",
               description: "Create a major release."
        switch "--minor",
               description: "Create a minor release."
        switch "--force",
               description: "Actually create the release and trigger the workflow. Without this, just show " \
                            "what would be done."

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

        ohai "Generating release notes for #{new_version}"
        release_notes = if args.major? || args.minor?
          "Release notes for this release can be found on the [Homebrew blog](https://brew.sh/blog/#{new_version}).\n"
        else
          ""
        end
        release_notes += GitHub.generate_release_notes("Homebrew", "brew", new_version,
                                                       previous_tag: latest_version)["body"]

        puts release_notes
        puts

        unless args.force?
          opoo "Use `brew release --force` to trigger the release workflow and create the draft release."
          return
        end

        # Not actually useless, needed for Sorbet.
        # rubocop:disable Lint/UselessAssignment
        e = T.let(nil, T.nilable(Exception))
        # rubocop:enable Lint/UselessAssignment

        existing_releases = begin
          matching_releases(new_version)
        rescue *GitHub::API::ERRORS => e
          odie "Unable to check existing releases: #{e.message}!"
        end

        if existing_releases.present?
          draft_releases, published_releases = existing_releases.partition { |release| release["draft"] }
          error_message = +""

          if draft_releases.present?
            error_message << "Draft releases already exist for #{new_version}. " \
                             "Delete them in the web interface first:\n"
            error_message << release_urls(draft_releases).join("\n")
          end

          if published_releases.present?
            error_message << "\n" if error_message.present?
            error_message << "Published releases already exist for #{new_version}. " \
                             "Run `brew update` instead:\n"
            error_message << release_urls(published_releases).join("\n")
          end

          odie error_message
        end

        # Get the current commit SHA
        current_sha = Utils.safe_popen_read("git", "-C", HOMEBREW_REPOSITORY, "rev-parse", "origin/main").strip
        release_workflow = "release.yml"

        dispatch_time = Time.now
        ohai "Triggering release workflow for #{new_version}..."
        begin
          GitHub.workflow_dispatch_event("Homebrew", "brew", release_workflow, "main", tag: new_version)
        # Cannot use `e` as Sorbet needs it used below instead.
        # rubocop:disable Naming/RescuedExceptionsVariableName
        rescue *GitHub::API::ERRORS => error
          odie "Unable to trigger workflow: #{error.message}!"
        end
        # rubocop:enable Naming/RescuedExceptionsVariableName

        # Poll for workflow completion
        initial_sleep_time = 15
        sleep_time = 5
        max_attempts = 180 # 15 minutes (5 seconds * 180 attempts)
        attempt = 0
        run_conclusion = T.let(nil, T.nilable(String))

        while attempt < max_attempts
          sleep attempt.zero? ? initial_sleep_time : sleep_time
          attempt += 1

          # Check workflow runs for the commit SHA
          begin
            runs_url = "#{GitHub::API_URL}/repos/Homebrew/brew/actions/workflows/#{release_workflow}/runs"
            response = GitHub::API.open_rest("#{runs_url}?event=workflow_dispatch&per_page=5")
            run = response["workflow_runs"]&.find do |r|
              r["head_sha"] == current_sha && Time.parse(r["created_at"]) >= dispatch_time
            end

            if run
              if run["status"] == "completed"
                run_conclusion = run["conclusion"]
                puts if attempt > 1
                break
              end

              if attempt == 1
                puts "This will take a few minutes. You can monitor progress at:"
                puts "  #{Formatter.url(run["html_url"])}"
                print "Waiting for workflow to complete..."
              else
                print "."
              end
            else
              puts
              odie "Unable to find workflow for commit: #{current_sha}!"
            end
          rescue *GitHub::API::ERRORS => e
            puts
            odie "Unable to check workflow status: #{e.message}!"
          end
        end

        odie "Workflow completed with status: #{run_conclusion}!" if run_conclusion != "success"

        puts
        ohai "Release created at:"
        releases_page_url = "https://github.com/Homebrew/brew/releases"
        release_url = begin
          latest_matching_release(new_version)&.fetch("html_url", nil) || releases_page_url
        rescue *GitHub::API::ERRORS => e
          opoo "Unable to locate created release: #{e.message}"
          releases_page_url
        end
        puts "  #{Formatter.url(release_url)}"
        exec_browser release_url
      end

      private

      sig { params(name: String).returns(T::Array[T::Hash[String, T.untyped]]) }
      def matching_releases(name)
        releases_url = "#{GitHub::API_URL}/repos/Homebrew/brew/releases?per_page=#{GitHub::MAX_PER_PAGE}"
        releases = T.cast(GitHub::API.open_rest(releases_url,
                                                request_method: :GET,
                                                scopes:         GitHub::CREATE_ISSUE_FORK_OR_PR_SCOPES),
                          T::Array[T::Hash[String, T.untyped]])
        releases.select do |release|
          release_name = release["name"].to_s
          release_name = release.fetch("tag_name", "").to_s if release_name.blank?
          release_name == name
        end
      end

      sig { params(name: String).returns(T.nilable(T::Hash[String, T.untyped])) }
      def latest_matching_release(name)
        matching_releases(name).max_by do |release|
          Time.parse(release.fetch("created_at", ""))
        rescue ArgumentError, TypeError
          Time.at(0)
        end
      end

      sig { params(releases: T::Array[T::Hash[String, T.untyped]]).returns(T::Array[String]) }
      def release_urls(releases)
        releases.filter_map do |release|
          url = release["html_url"].to_s
          next if url.blank?

          "  #{Formatter.url(url)}"
        end
      end
    end
  end
end
