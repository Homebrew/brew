# frozen_string_literal: true

module Gem
  module CIDetector
    # NOTE: Any changes made here will need to be made to both lib/rubygems/ci_detector.rb and
    # bundler/lib/bundler/ci_detector.rb (which are enforced duplicates).
    # TODO: Drop that duplication once bundler drops support for RubyGems 3.4
    #
    # ## Recognized CI providers, their signifiers, and the relevant docs ##
    #
    # Travis CI   - CI, TRAVIS            https://docs.travis-ci.com/user/environment-variables/#default-environment-variables
    # Cirrus CI   - CI, CIRRUS_CI         https://cirrus-ci.org/guide/writing-tasks/#environment-variables
    # Circle CI   - CI, CIRCLECI          https://circleci.com/docs/variables/#built-in-environment-variables
    # Gitlab CI   - CI, GITLAB_CI         https://docs.gitlab.com/ee/ci/variables/
    # AppVeyor    - CI, APPVEYOR          https://www.appveyor.com/docs/environment-variables/
    # CodeShip    - CI_NAME               https://docs.cloudbees.com/docs/cloudbees-codeship/latest/pro-builds-and-configuration/environment-variables#_default_environment_variables
    # dsari       - CI, DSARI             https://github.com/rfinnie/dsari#running
    # Jenkins     - BUILD_NUMBER          https://www.jenkins.io/doc/book/pipeline/jenkinsfile/#using-environment-variables
    # TeamCity    - TEAMCITY_VERSION      https://www.jetbrains.com/help/teamcity/predefined-build-parameters.html#Predefined+Server+Build+Parameters
    # Appflow     - CI_BUILD_ID           https://ionic.io/docs/appflow/automation/environments#predefined-environments
    # TaskCluster - TASKCLUSTER_ROOT_URL  https://docs.taskcluster.net/docs/manual/design/env-vars
    # Semaphore   - CI, SEMAPHORE         https://docs.semaphoreci.com/ci-cd-environment/environment-variables/
    # BuildKite   - CI, BUILDKITE         https://buildkite.com/docs/pipelines/environment-variables
    # GoCD        - GO_SERVER_URL         https://docs.gocd.org/current/faq/dev_use_current_revision_in_build.html
    # GH Actions  - CI, GITHUB_ACTIONS    https://docs.github.com/en/actions/learn-github-actions/variables#default-environment-variables
    #
    # ### Some "standard" ENVs that multiple providers may set ###
    #
    # * CI - this is set by _most_ (but not all) CI providers now; it's approaching a standard.
    # * CI_NAME - Not as frequently used, but some providers set this to specify their own name

    # Any of these being set is a reasonably reliable indicator that we are
    # executing in a CI environment.
    ENV_INDICATORS = [
      "CI",
      "CI_NAME",
      "CONTINUOUS_INTEGRATION",
      "BUILD_NUMBER",
      "CI_APP_ID",
      "CI_BUILD_ID",
      "CI_BUILD_NUMBER",
      "RUN_ID",
      "TASKCLUSTER_ROOT_URL",
    ].freeze

    # For each CI, this env suffices to indicate that we're on _that_ CI's
    # containers. (A few of them only supply a CI_NAME variable, which is also
    # nice). And if they set "CI" but we can't tell which one they are, we also
    # want to know that - a bare "ci" without another token tells us as much.
    ENV_DESCRIPTORS = {
      "TRAVIS" => "travis",
      "CIRCLECI" => "circle",
      "CIRRUS_CI" => "cirrus",
      "DSARI" => "dsari",
      "SEMAPHORE" => "semaphore",
      "JENKINS_URL" => "jenkins",
      "BUILDKITE" => "buildkite",
      "GO_SERVER_URL" => "go",
      "GITLAB_CI" => "gitlab",
      "GITHUB_ACTIONS" => "github",
      "TASKCLUSTER_ROOT_URL" => "taskcluster",
      "CI" => "ci",
    }.freeze

    def self.ci?
      ENV_INDICATORS.any? {|var| ENV.include?(var) }
    end

    def self.ci_strings
      matching_names = ENV_DESCRIPTORS.select {|env, _| ENV[env] }.values
      matching_names << ENV["CI_NAME"].downcase if ENV["CI_NAME"]
      matching_names.reject(&:empty?).sort.uniq
    end
  end
end
