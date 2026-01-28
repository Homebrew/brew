# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Homebrew
  module TestBot
    class TestFormulae < Test
      attr_accessor :skipped_or_failed_formulae
      attr_reader :artifact_cache

      def initialize(tap:, git:, dry_run:, fail_fast:, verbose:)
        super

        @skipped_or_failed_formulae = []
        @artifact_cache = Pathname.new("artifact-cache")
        # Let's keep track of the artifacts we've already downloaded
        # to avoid repeatedly trying to download the same thing.
        @downloaded_artifacts = Hash.new { |h, k| h[k] = [] }
      end

      protected

      def cached_event_json
        return unless (event_json = artifact_cache/"event.json").exist?

        event_json
      end

      def github_event_payload
        return if (github_event_path = ENV.fetch("GITHUB_EVENT_PATH", nil)).blank?

        JSON.parse(File.read(github_event_path))
      end

      def previous_github_sha
        return if tap.blank?
        return unless repository.directory?
        return unless GitHub::Actions.env_set?
        return if (payload = github_event_payload).blank?

        head_repo_owner = payload.dig("pull_request", "head", "repo", "owner", "login")
        head_from_fork = head_repo_owner != ENV.fetch("GITHUB_REPOSITORY_OWNER")
        return if head_from_fork && head_repo_owner != "BrewTestBot"

        # If we have a cached event payload, then we failed to get the artifact we wanted
        # from `GITHUB_EVENT_PATH`, so use the cached payload to check for a SHA1.
        event_payload = JSON.parse(cached_event_json.read) if cached_event_json.present?
        event_payload ||= payload

        event_payload.fetch("before", nil)
      end

      def artifact_metadata(check_suite_nodes, repo, event_name, workflow_name, check_run_name, artifact_pattern)
        candidate_nodes = check_suite_nodes.select do |node|
          next false if node.fetch("status") != "COMPLETED"

          workflow_run = node.fetch("workflowRun")
          next false if workflow_run.blank?
          next false if workflow_run.fetch("event") != event_name
          next false if workflow_run.dig("workflow", "name") != workflow_name

          check_run_nodes = node.dig("checkRuns", "nodes")
          next false if check_run_nodes.blank?

          check_run_nodes.any? do |check_run_node|
            check_run_node.fetch("name") == check_run_name && check_run_node.fetch("status") == "COMPLETED"
          end
        end
        return [] if candidate_nodes.blank?

        run_id = candidate_nodes.max_by { |node| Time.parse(node.fetch("updatedAt")) }
                                .dig("workflowRun", "databaseId")
        return [] if run_id.blank?

        url = GitHub.url_to("repos", repo, "actions", "runs", run_id, "artifacts")
        response = GitHub::API.open_rest(url)
        return [] if response.fetch("total_count").zero?

        artifacts = response.fetch("artifacts")
        artifacts.select do |artifact|
          File.fnmatch?(artifact_pattern, artifact.fetch("name"), File::FNM_EXTGLOB)
        end
      end

      GRAPHQL_QUERY = <<~GRAPHQL
        query ($owner: String!, $repo: String!, $commit: GitObjectID!) {
          repository(owner: $owner, name: $repo) {
            object(oid: $commit) {
              ... on Commit {
                checkSuites(last: 100) {
                  nodes {
                    status
                    updatedAt
                    workflowRun {
                      databaseId
                      event
                      workflow {
                        name
                      }
                    }
                    checkRuns(last: 100) {
                      nodes {
                        name
                        status
                      }
                    }
                  }
                }
              }
            }
          }
        }
      GRAPHQL

      def download_artifacts_from_previous_run!(artifact_pattern, dry_run:)
        return if dry_run
        return if GitHub::API.credentials_type == :none
        return if (sha = previous_github_sha).blank?

        pull_number = github_event_payload.dig("pull_request", "number")
        return if pull_number.blank?

        github_repository = ENV.fetch("GITHUB_REPOSITORY")
        owner, repo = *github_repository.split("/")
        pr_labels = GitHub.pull_request_labels(owner, repo, pull_number)
        # Also disable bottle cache for PRs modifying workflows to avoid cache poisoning.
        return if pr_labels.include?("CI-no-bottle-cache") || pr_labels.include?("workflows")

        variables = {
          owner:,
          repo:,
          commit: sha,
        }

        response = GitHub::API.open_graphql(GRAPHQL_QUERY, variables:)
        check_suite_nodes = response.dig("repository", "object", "checkSuites", "nodes")
        return if check_suite_nodes.blank?

        wanted_artifacts = artifact_metadata(check_suite_nodes, github_repository, "pull_request",
                                             "CI", "conclusion", artifact_pattern)
        wanted_artifacts_pattern = artifact_pattern
        if wanted_artifacts.empty?
          # If we didn't find the artifacts that we wanted, fall back to the `event_payload` artifact.
          wanted_artifacts = artifact_metadata(check_suite_nodes, github_repository, "pull_request_target",
                                               "Triage tasks", "upload-metadata", "event_payload")
          wanted_artifacts_pattern = "event_payload"
        end
        return if wanted_artifacts.empty?

        if (attempted_artifact = wanted_artifacts.find do |artifact|
              @downloaded_artifacts[sha].include?(artifact.fetch("name"))
            end)
          opoo "Already tried #{attempted_artifact.fetch("name")} from #{sha}, giving up"
          return
        end

        cached_event_json&.unlink if File.fnmatch?(wanted_artifacts_pattern, "event_payload", File::FNM_EXTGLOB)

        require "utils/github/artifacts"

        ohai "Downloading artifacts matching pattern #{wanted_artifacts_pattern} from #{sha}"
        artifact_cache.mkpath
        artifact_cache.cd do
          wanted_artifacts.each do |artifact|
            name = artifact.fetch("name")
            ohai "Downloading artifact #{name} from #{sha}"
            @downloaded_artifacts[sha] << name

            download_url = artifact.fetch("archive_download_url")
            artifact_id = artifact.fetch("id")
            GitHub.download_artifact(download_url, artifact_id.to_s)
          end
        end

        return if wanted_artifacts_pattern == artifact_pattern

        # If we made it here, then we downloaded an `event_payload` artifact.
        # We can now use this `event_payload` artifact to attempt to download the artifact we wanted.
        download_artifacts_from_previous_run!(artifact_pattern, dry_run:)
      rescue GitHub::API::AuthenticationFailedError => e
        opoo e
      end

      def no_diff?(formula, git_ref)
        return false unless repository.directory?

        @fetched_refs ||= []
        if @fetched_refs.exclude?(git_ref)
          test git, "-C", repository, "fetch", "origin", git_ref, ignore_failures: true
          @fetched_refs << git_ref if steps.last.passed?
        end

        relative_formula_path = formula.path.relative_path_from(repository)
        system(git, "-C", repository, "diff", "--no-ext-diff", "--quiet", git_ref, "--", relative_formula_path)
      end

      def local_bottle_hash(formula, bottle_dir:)
        return if (local_bottle_json = bottle_glob(formula, bottle_dir, ".json").first).blank?

        JSON.parse(local_bottle_json.read)
      end

      def artifact_cache_valid?(formula, formulae_dependents: false)
        sha = if formulae_dependents
          previous_github_sha
        else
          local_bottle_hash(formula, bottle_dir: artifact_cache)&.dig(formula.name, "formula", "tap_git_revision")
        end

        return false if sha.blank?
        return false unless no_diff?(formula, sha)

        recursive_dependencies = if formulae_dependents
          formula.recursive_dependencies
        else
          formula.recursive_dependencies do |_, dep|
            Dependency.prune if dep.build? || dep.test?
          end
        end

        recursive_dependencies.all? do |dep|
          no_diff?(dep.to_formula, sha)
        end
      end

      def bottle_glob(formula_name, bottle_dir = Pathname.pwd, ext = ".tar.gz", bottle_tag: Utils::Bottles.tag.to_s)
        bottle_dir.glob("#{formula_name}--*.#{bottle_tag}.bottle*#{ext}")
      end

      def install_formula_from_bottle!(formula_name, testing_formulae_dependents:, dry_run:,
                                       bottle_dir: Pathname.pwd)
        bottle_filename = bottle_glob(formula_name, bottle_dir).first
        if bottle_filename.blank?
          if testing_formulae_dependents && !dry_run
            raise "Failed to find bottle for '#{formula_name}'."
          elsif !dry_run
            return false
          end

          bottle_filename = "$BOTTLE_FILENAME"
        end

        install_args = []
        install_args += %w[--ignore-dependencies --skip-post-install] if testing_formulae_dependents
        test "brew", "install", *install_args, bottle_filename
        install_step = steps.last

        if !dry_run && !testing_formulae_dependents && install_step.passed?
          bottle_hash = local_bottle_hash(formula_name, bottle_dir:)
          bottle_revision = bottle_hash.dig(formula_name, "formula", "tap_git_revision")
          bottle_header = "Bottle cache hit"
          bottle_commit_details = if @fetched_refs&.include?(bottle_revision)
            Utils.safe_popen_read(git, "-C", repository, "show", "--format=reference", bottle_revision)
          else
            bottle_revision
          end
          bottle_message = "Bottle for #{formula_name} built at #{bottle_commit_details}".strip

          if GitHub::Actions.env_set?
            puts GitHub::Actions::Annotation.new(
              :notice,
              bottle_message,
              file:  bottle_hash.dig(formula_name, "formula", "tap_git_path"),
              title: bottle_header,
            )
          else
            ohai bottle_header, bottle_message
          end
        end
        return install_step.passed? if !testing_formulae_dependents || !install_step.passed?

        test "brew", "unlink", formula_name
        puts

        install_step.passed?
      end

      def bottled?(formula, no_older_versions: false)
        # If a formula has an `:all` bottle, then all its dependencies have
        # to be bottled too for us to use it. We only need to recurse
        # up the dep tree when we encounter an `:all` bottle because
        # a formula is not bottled unless its dependencies are.
        if formula.bottle_specification.tag?(Utils::Bottles.tag(:all))
          formula.deps.all? do |dep|
            bottle_no_older_versions = no_older_versions && (!dep.test? || dep.build?)
            bottled?(dep.to_formula, no_older_versions: bottle_no_older_versions)
          end
        else
          formula.bottle_specification.tag?(Utils::Bottles.tag, no_older_versions:)
        end
      end

      def bottled_or_built?(formula, built_formulae, no_older_versions: false)
        bottled?(formula, no_older_versions:) || built_formulae.include?(formula.full_name)
      end

      def downloads_using_homebrew_curl?(formula)
        [:stable, :head].any? do |spec_name|
          next false unless (spec = formula.send(spec_name))

          spec.using == :homebrew_curl || spec.resources.values.any? { |r| r.using == :homebrew_curl }
        end
      end

      def install_curl_if_needed(formula)
        return unless downloads_using_homebrew_curl?(formula)

        test "brew", "install", "curl",
             env: { "HOMEBREW_DEVELOPER" => nil }
      end

      def install_mercurial_if_needed(deps, reqs)
        return if (deps | reqs).none? { |d| d.name == "mercurial" && d.build? }

        test "brew", "install", "mercurial",
             env:  { "HOMEBREW_DEVELOPER" => nil }
      end

      def install_subversion_if_needed(deps, reqs)
        return if (deps | reqs).none? { |d| d.name == "subversion" && d.build? }

        test "brew", "install", "subversion",
             env:  { "HOMEBREW_DEVELOPER" => nil }
      end

      def skipped(formula_name, reason)
        @skipped_or_failed_formulae << formula_name

        puts Formatter.headline(
          "#{Formatter.warning("SKIPPED")} #{Formatter.identifier(formula_name)}",
          color: :yellow,
        )
        opoo reason
      end

      def failed(formula_name, reason)
        @skipped_or_failed_formulae << formula_name

        puts Formatter.headline(
          "#{Formatter.error("FAILED")} #{Formatter.identifier(formula_name)}",
          color: :red,
        )
        onoe reason
      end

      def unsatisfied_requirements_messages(formula)
        f = Formulary.factory(formula.full_name)
        fi = FormulaInstaller.new(f, build_bottle: true)

        unsatisfied_requirements, = fi.expand_requirements
        return if unsatisfied_requirements.blank?

        unsatisfied_requirements.values.flatten.map(&:message).join("\n").presence
      end

      def cleanup_during!(keep_formulae = [], args:)
        return unless cleanup?(args)
        return unless HOMEBREW_CACHE.exist?

        free_gb = Utils.safe_popen_read({ "BLOCKSIZE" => (1000 ** 3).to_s }, "df", HOMEBREW_CACHE.to_s)
                       .lines
                       .fetch(1) # HOMEBREW_CACHE
                       .split[3] # free GB
                       .to_i
        return if free_gb > 10

        test_header(:TestFormulae, method: :cleanup_during!)

        # HOMEBREW_LOGS can be a subdirectory of HOMEBREW_CACHE.
        # Preserve the logs in that case.
        logs_are_in_cache = HOMEBREW_LOGS.ascend { |path| break true if path == HOMEBREW_CACHE }
        should_save_logs = logs_are_in_cache && HOMEBREW_LOGS.exist?

        test "mv", HOMEBREW_LOGS.to_s, (tmpdir = Dir.mktmpdir) if should_save_logs
        FileUtils.chmod_R "u+rw", HOMEBREW_CACHE, force: true
        test "rm", "-rf", HOMEBREW_CACHE.to_s
        if should_save_logs
          FileUtils.mkdir_p HOMEBREW_LOGS.parent
          test "mv", "#{tmpdir}/#{HOMEBREW_LOGS.basename}", HOMEBREW_LOGS.to_s
        end

        if @cleaned_up_during.blank?
          @cleaned_up_during = true
          return
        end

        installed_formulae = Utils.safe_popen_read("brew", "list", "--full-name", "--formulae").split("\n")
        uninstallable_formulae = installed_formulae - keep_formulae

        @installed_formulae_deps ||= Hash.new do |h, formula|
          h[formula] = Utils.safe_popen_read("brew", "deps", "--full-name", formula).split("\n")
        end
        uninstallable_formulae.reject! do |name|
          keep_formulae.any? { |f| @installed_formulae_deps[f].include?(name) }
        end

        return if uninstallable_formulae.blank?

        test "brew", "uninstall", "--force", "--ignore-dependencies", *uninstallable_formulae
      end

      def sorted_formulae
        changed_formulae_dependents = {}

        @testing_formulae.each do |formula|
          begin
            formula_dependencies =
              Utils.popen_read("brew", "deps", "--full-name",
                               "--include-build",
                               "--include-test", formula)
                   .split("\n")
            # deps can fail if deps are not tapped
            unless $CHILD_STATUS.success?
              Formulary.factory(formula).recursive_dependencies
              # If we haven't got a TapFormulaUnavailableError, then something else is broken
              raise "Failed to determine dependencies for '#{formula}'."
            end
          rescue TapFormulaUnavailableError => e
            raise if e.tap.installed?

            e.tap.clear_cache
            safe_system "brew", "tap", e.tap.name
            retry
          end

          unchanged_dependencies = formula_dependencies - @testing_formulae
          changed_dependencies = formula_dependencies - unchanged_dependencies
          changed_dependencies.each do |changed_formula|
            changed_formulae_dependents[changed_formula] ||= 0
            changed_formulae_dependents[changed_formula] += 1
          end
        end

        changed_formulae = changed_formulae_dependents.sort do |a1, a2|
          a2[1].to_i <=> a1[1].to_i
        end
        changed_formulae.map!(&:first)
        unchanged_formulae = @testing_formulae - changed_formulae
        changed_formulae + unchanged_formulae
      end
    end
  end
end
