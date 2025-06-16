# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "tap"
require "utils/github"

module Homebrew
  module DevCmd
    class PrPublish < AbstractCommand
      cmd_args do
        description <<~EOS
          Publish bottles for a pull request with GitHub Actions.
          Requires write access to the repository.
        EOS
        switch "--autosquash",
               description: "If supported on the target tap, automatically reformat and reword commits " \
                            "to our preferred format."
        switch "--large-runner",
               description: "Run the upload job on a large runner."
        flag   "--branch=",
               description: "Branch to use the workflow from (default: `master`)."
        flag   "--message=",
               depends_on:  "--autosquash",
               description: "Message to include when autosquashing revision bumps, deletions and rebuilds."
        flag   "--tap=",
               description: "Target tap repository (default: `homebrew/core`)."
        flag   "--workflow=",
               description: "Target workflow filename (default: `publish-commit-bottles.yml`)."

        named_args :pull_request, min: 1
      end

      sig { override.void }
      def run
        tap = Tap.fetch(args.tap || CoreTap.instance.name)
        workflow = args.workflow || "publish-commit-bottles.yml"
        ref = args.branch || "master"

        inputs = {
          autosquash:   args.autosquash?,
          large_runner: args.large_runner?,
        }
        inputs[:message] = args.message if args.message.presence

        args.named.uniq.each do |arg|
          arg = "#{tap.default_remote}/pull/#{arg}" if arg.to_i.positive?
          url_match = arg.match HOMEBREW_PULL_OR_COMMIT_URL_REGEX
          _, user, repo, issue = *url_match
          odie "Not a GitHub pull request: #{arg}" unless issue

          inputs[:pull_request] = issue

          pr_labels = GitHub.pull_request_labels(user, repo, issue)
          if pr_labels.include?("autosquash")
            oh1 "Found `autosquash` label on ##{issue}. Requesting autosquash."
            inputs[:autosquash] = true
          end
          if pr_labels.include?("large-bottle-upload")
            oh1 "Found `large-bottle-upload` label on ##{issue}. Requesting upload on large runner."
            inputs[:large_runner] = true
          end

          if args.tap.present? && !T.must("#{user}/#{repo}".casecmp(tap.full_name)).zero?
            odie "Pull request URL is for #{user}/#{repo} but `--tap=#{tap.full_name}` was specified!"
          end

          ohai "Dispatching #{tap} pull request ##{issue}"
          GitHub.workflow_dispatch_event(user, repo, workflow, ref, **inputs)
        end
      end
    end
  end
end
