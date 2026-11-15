# typed: strict
# frozen_string_literal: true

module GitHub
  # Locate workflow runs and downloadable build artifacts.
  module Workflows
    extend T::Helpers

    requires_ancestor { T.class_of(GitHub) }

    sig {
      params(
        user:             String,
        repo:             String,
        pull_request:     String,
        workflow_id:      String,
        artifact_pattern: String,
        head_sha:         T.nilable(String),
      ).returns(WorkflowArray)
    }
    def get_workflow_run(user, repo, pull_request, workflow_id: "tests.yml", artifact_pattern: "bottles{,_*}",
                         head_sha: nil)
      scopes = CREATE_ISSUE_FORK_OR_PR_SCOPES

      # GraphQL unfortunately has no way to get the workflow yml name, so we need an extra REST call.
      workflow_api_url = "#{API_URL}/repos/#{user}/#{repo}/actions/workflows/#{workflow_id}"
      workflow_payload = API.open_rest(workflow_api_url, scopes:)
      workflow_id_num = workflow_payload["id"]

      query = <<~EOS
        query ($user: String!, $repo: String!, $pr: Int!) {
          repository(owner: $user, name: $repo) {
            pullRequest(number: $pr) {
              commits(last: 1) {
                nodes {
                  commit {
                    oid
                    checkSuites(first: 100) {
                      nodes {
                        status,
                        workflowRun {
                          databaseId,
                          url,
                          workflow {
                            databaseId
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      EOS
      variables = {
        user:,
        repo:,
        pr:   pull_request.to_i,
      }
      result = API.open_graphql(query, variables:, scopes:)

      commit_node = result["repository"]["pullRequest"]["commits"]["nodes"].first
      check_suite = if commit_node.present?
        commit = commit_node["commit"]
        if head_sha.present? && commit["oid"].downcase != head_sha.downcase
          raise API::Error, "Pull request ##{pull_request} is at #{commit["oid"]} but expected #{head_sha}."
        end

        commit["checkSuites"]["nodes"].select do |suite|
          suite.dig("workflowRun", "workflow", "databaseId") == workflow_id_num
        end
      else
        []
      end

      [check_suite, user, repo, pull_request, workflow_id, scopes, artifact_pattern]
    end

    sig { params(workflow_array: WorkflowArray).returns(T::Array[String]) }
    def get_artifact_urls(workflow_array)
      check_suite, user, repo, pr, workflow_id, scopes, artifact_pattern = *workflow_array
      if check_suite.empty?
        raise API::Error, <<~EOS
          No matching check suite found for these criteria!
            Pull request: #{pr}
            Workflow:     #{workflow_id}
        EOS
      end

      last_check = check_suite.fetch(-1)
      status = last_check["status"].sub("_", " ").downcase
      if status != "completed"
        raise API::Error, <<~EOS
          The newest workflow run for ##{pr} is still #{status}!
            #{Formatter.url last_check["workflowRun"]["url"]}
        EOS
      end

      run_id = last_check["workflowRun"]["databaseId"]
      artifacts = []
      per_page = 50
      API.paginate_rest("#{API_URL}/repos/#{user}/#{repo}/actions/runs/#{run_id}/artifacts",
                        per_page:, scopes:) do |result|
        result = result["artifacts"]
        artifacts.concat(result)
        break if result.length < per_page
      end

      matching_artifacts =
        artifacts
        .group_by { |art| art["name"] }
        .select { |name| File.fnmatch?(artifact_pattern, name, File::FNM_EXTGLOB) }
        .map { |_, arts| arts.max_by { |art| art["created_at"] } }

      if matching_artifacts.empty?
        raise API::Error, <<~EOS
          No artifacts with the pattern `#{artifact_pattern}` were found!
            #{Formatter.url last_check["workflowRun"]["url"]}
        EOS
      end

      matching_artifacts.map { |art| art["archive_download_url"] }
    end
  end
end
