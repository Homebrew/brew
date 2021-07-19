# typed: true
# frozen_string_literal: true

require "cli/parser"
require "livecheck/livecheck"

module Homebrew
  extend T::Sig

  module_function

  sig { returns(CLI::Parser) }
  def bump_args
    Homebrew::CLI::Parser.new do
      description <<~EOS
        Display out-of-date brew formulae and the latest version available.
        Also displays whether a pull request has been opened with the URL.
      EOS
      switch "--full-name",
             description: "Print formulae/casks with fully-qualified names."
      switch "--no-pull-requests",
             description: "Do not retrieve pull requests from GitHub."
      switch "--formula", "--formulae",
             description: "Check only formulae."
      switch "--cask", "--casks",
             description: "Check only casks."
      flag   "--limit=",
             description: "Limit number of package results returned."

      conflicts "--cask", "--formula"

      named_args [:formula, :cask]
    end
  end

  def bump
    args = bump_args.parse

    if args.limit.present? && !args.formula? && !args.cask?
      raise UsageError, "`--limit` must be used with either `--formula` or `--cask`."
    end

    formulae_and_casks = if args.formula?
      args.named.to_formulae
    elsif args.cask?
      args.named.to_casks
    else
      args.named.to_formulae_and_casks
    end
    formulae_and_casks = formulae_and_casks&.sort_by do |formula_or_cask|
      formula_or_cask.respond_to?(:token) ? formula_or_cask.token : formula_or_cask.name
    end

    limit = args.limit.to_i if args.limit.present?

    if formulae_and_casks.present?
      Livecheck.load_other_tap_strategies(formulae_and_casks)

      ambiguous_casks = []
      if !args.formula? && !args.cask?
        ambiguous_casks = formulae_and_casks.group_by { |item| Livecheck.formula_or_cask_name(item, full_name: true) }
                                            .values
                                            .select { |items| items.length > 1 }
                                            .flatten
                                            .select { |item| item.is_a?(Cask::Cask) }
      end

      ambiguous_names = []
      unless args.full_name?
        ambiguous_names =
          (formulae_and_casks - ambiguous_casks).group_by { |item| Livecheck.formula_or_cask_name(item) }
                                                .values
                                                .select { |items| items.length > 1 }
                                                .flatten
      end

      formulae_and_casks.each_with_index do |formula_or_cask, i|
        puts if i.positive?

        use_full_name = args.full_name? || ambiguous_names.include?(formula_or_cask)
        name = Livecheck.formula_or_cask_name(formula_or_cask, full_name: use_full_name)
        repository = if formula_or_cask.is_a?(Formula)
          if formula_or_cask.head_only?
            ohai name
            puts "Formula is HEAD-only."
            next
          end

          Repology::HOMEBREW_CORE
        else
          Repology::HOMEBREW_CASK
        end

        package_data = Repology.single_package_query(name, repository: repository)
        retrieve_and_display_info(
          formula_or_cask,
          name,
          package_data&.values&.first,
          args:           args,
          ambiguous_cask: ambiguous_casks.include?(formula_or_cask),
        )
      end
    else
      api_response = {}
      unless args.cask?
        api_response[:formulae] =
          Repology.parse_api_response(limit, repository: Repology::HOMEBREW_CORE)
      end
      unless args.formula?
        api_response[:casks] =
          Repology.parse_api_response(limit, repository: Repology::HOMEBREW_CASK)
      end

      api_response.each do |package_type, outdated_packages|
        repository = if package_type == :formulae
          Repology::HOMEBREW_CORE
        else
          Repology::HOMEBREW_CASK
        end

        outdated_packages.each_with_index do |(_name, repositories), i|
          homebrew_repo = repositories.find do |repo|
            repo["repo"] == repository
          end

          next if homebrew_repo.blank?

          formula_or_cask = begin
            if repository == Repology::HOMEBREW_CORE
              Formula[homebrew_repo["srcname"]]
            else
              Cask::CaskLoader.load(homebrew_repo["srcname"])
            end
          rescue
            next
          end
          name = Livecheck.formula_or_cask_name(formula_or_cask)
          ambiguous_cask = begin
            formula_or_cask.is_a?(Cask::Cask) && !args.cask? && Formula[name]
          rescue FormulaUnavailableError
            false
          end

          puts if i.positive?
          retrieve_and_display_info(formula_or_cask, name, repositories, args: args, ambiguous_cask: ambiguous_cask)

          break if limit && i >= limit
        end
      end
    end
  end

  def livecheck_result(formula_or_cask)
    name = Livecheck.formula_or_cask_name(formula_or_cask)

    livecheck_formula_or_cask, =
      Livecheck.resolve_livecheck_reference(formula_or_cask, full_name: false, debug: false)

    # Check skip conditions for a referenced formula/cask
    if livecheck_formula_or_cask
      skip_info = Livecheck::SkipConditions.referenced_skip_information(
        livecheck_formula_or_cask,
        name,
        full_name: false,
        verbose:   false,
      )
    end

    skip_info ||= Livecheck::SkipConditions.skip_information(formula_or_cask, full_name: false, verbose: false)
    if skip_info.present?
      return "#{skip_info[:status]}#{" - #{skip_info[:messages].join(", ")}" if skip_info[:messages].present?}"
    end

    version_info = Livecheck.latest_version(
      formula_or_cask,
      livecheck_formula_or_cask: livecheck_formula_or_cask,
      json: true, full_name: false, verbose: false, debug: false
    )
    latest = version_info[:latest] if version_info.present?

    return "unable to get versions" if latest.blank?

    latest.to_s
  rescue => e
    "error: #{e}"
  end

  def retrieve_pull_requests(formula_or_cask, name)
    tap_remote_repo = formula_or_cask.tap&.remote_repo || formula_or_cask.tap&.full_name
    pull_requests = GitHub.fetch_pull_requests(name, tap_remote_repo, state: "open")
    if pull_requests.try(:any?)
      pull_requests = pull_requests.map { |pr| "#{pr["title"]} (#{Formatter.url(pr["html_url"])})" }.join(", ")
    end

    return "none" if pull_requests.blank?

    pull_requests
  end

  def retrieve_and_display_info(formula_or_cask, name, repositories, args:, ambiguous_cask: false)
    current_version = if formula_or_cask.is_a?(Formula)
      formula_or_cask.stable.version
    else
      Version.new(formula_or_cask.version)
    end

    repology_latest = if repositories.present?
      Repology.latest_version(repositories)
    else
      "not found"
    end

    livecheck_latest = livecheck_result(formula_or_cask)
    pull_requests = retrieve_pull_requests(formula_or_cask, name) unless args.no_pull_requests?

    name += " (cask)" if ambiguous_cask
    title = if current_version == repology_latest &&
               current_version == livecheck_latest
      "#{name} is up to date!"
    else
      name
    end

    ohai title
    puts <<~EOS
      Current formula version:  #{current_version}
      Latest Repology version:  #{repology_latest}
      Latest livecheck version: #{livecheck_latest}
    EOS
    puts "Open pull requests:       #{pull_requests}" unless args.no_pull_requests?
  end
end
