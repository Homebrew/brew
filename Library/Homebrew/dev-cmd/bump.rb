# typed: strict
# frozen_string_literal: true

require "bump_version_parser"
require "cli/parser"
require "livecheck/livecheck"

module Homebrew
  module_function

  class VersionBumpInfo < T::Struct
    const :type, Symbol
    const :multiple_versions, T::Boolean
    const :version_name, String
    const :current_version, BumpVersionParser
    const :repology_latest, T.any(String, Version)
    const :new_version, BumpVersionParser
    const :open_pull_requests, T.nilable(T.any(T::Array[String], String))
    const :closed_pull_requests, T.nilable(T.any(T::Array[String], String))
  end

  sig { returns(CLI::Parser) }
  def bump_args
    CLI::Parser.new do
      description <<~EOS
        Display out-of-date brew formulae and the latest version available. If the
        returned current and livecheck versions differ or when querying specific
        formulae, also displays whether a pull request has been opened with the URL.
      EOS
      switch "--full-name",
             description: "Print formulae/casks with fully-qualified names."
      switch "--no-pull-requests",
             description: "Do not retrieve pull requests from GitHub."
      switch "--formula", "--formulae",
             description: "Check only formulae."
      switch "--cask", "--casks",
             description: "Check only casks."
      flag   "--tap=",
             description: "Check formulae and casks within the given tap, specified as <user>`/`<repo>."
      switch "--installed",
             description: "Check formulae and casks that are currently installed."
      switch "--no-fork",
             description: "Don't try to fork the repository."
      switch "--open-pr",
             description: "Open a pull request for the new version if none have been opened yet."
      flag   "--limit=",
             description: "Limit number of package results returned."
      flag   "--start-with=",
             description: "Letter or word that the list of package results should alphabetically follow."
      switch "-f", "--force",
             hidden:      true

      conflicts "--cask", "--formula"
      conflicts "--tap=", "--installed"
      conflicts "--no-pull-requests", "--open-pr"

      named_args [:formula, :cask], without_api: true
    end
  end

  sig { void }
  def bump
    args = bump_args.parse

    Homebrew.install_bundler_gems!(groups: ["livecheck"])

    if args.limit.present? && !args.formula? && !args.cask?
      raise UsageError, "`--limit` must be used with either `--formula` or `--cask`."
    end

    odisabled "brew bump --force" if args.force?

    Homebrew.with_no_api_env do
      formulae_and_casks = if args.tap
        tap = Tap.fetch(args.tap)
        raise UsageError, "`--tap` cannot be used with official taps." if tap.official?

        formulae = args.cask? ? [] : tap.formula_files.map { |path| Formulary.factory(path) }
        casks = args.formula? ? [] : tap.cask_files.map { |path| Cask::CaskLoader.load(path) }
        formulae + casks
      elsif args.installed?
        formulae = args.cask? ? [] : Formula.installed
        casks = args.formula? ? [] : Cask::Caskroom.casks
        formulae + casks
      elsif args.named.present?
        if args.formula?
          args.named.to_formulae
        elsif args.cask?
          args.named.to_casks
        else
          args.named.to_formulae_and_casks
        end
      end

      formulae_and_casks = formulae_and_casks&.sort_by do |formula_or_cask|
        formula_or_cask.respond_to?(:token) ? formula_or_cask.token : formula_or_cask.name
      end

      unless Utils::Curl.curl_supports_tls13?
        begin
          ensure_formula_installed!("curl", reason: "Repology queries") unless HOMEBREW_BREWED_CURL_PATH.exist?
        rescue FormulaUnavailableError
          opoo "A newer `curl` is required for Repology queries."
        end
      end

      if formulae_and_casks.present?
        handle_formula_and_casks(formulae_and_casks, args)
      else
        handle_api_response(args)
      end
    end
  end

  sig { params(formula_or_cask: T.any(Formula, Cask::Cask), args: CLI::Args).returns(T::Boolean) }
  def skip_repology?(formula_or_cask, args:)
    (ENV["CI"].present? && args.open_pr? && formula_or_cask.livecheckable?) ||
      (formula_or_cask.is_a?(Formula) && formula_or_cask.versioned_formula?)
  end

  sig { params(formulae_and_casks: T::Array[T.any(Formula, Cask::Cask)], args: CLI::Args).void }
  def handle_formula_and_casks(formulae_and_casks, args)
    Livecheck.load_other_tap_strategies(formulae_and_casks)

    ambiguous_casks = []
    if !args.formula? && !args.cask?
      ambiguous_casks = formulae_and_casks
                        .group_by { |item| Livecheck.package_or_resource_name(item, full_name: true) }
                        .values
                        .select { |items| items.length > 1 }
                        .flatten
                        .select { |item| item.is_a?(Cask::Cask) }
    end

    ambiguous_names = []
    unless args.full_name?
      ambiguous_names = (formulae_and_casks - ambiguous_casks)
                        .group_by { |item| Livecheck.package_or_resource_name(item) }
                        .values
                        .select { |items| items.length > 1 }
                        .flatten
    end

    formulae_and_casks.each_with_index do |formula_or_cask, i|
      puts if i.positive?
      next if skip_ineligible_formulae(formula_or_cask)

      use_full_name = args.full_name? || ambiguous_names.include?(formula_or_cask)
      name = Livecheck.package_or_resource_name(formula_or_cask, full_name: use_full_name)
      repository = if formula_or_cask.is_a?(Formula)
        Repology::HOMEBREW_CORE
      else
        Repology::HOMEBREW_CASK
      end

      package_data = Repology.single_package_query(name, repository:) unless skip_repology?(formula_or_cask, args:)

      retrieve_and_display_info_and_open_pr(
        formula_or_cask,
        name,
        package_data&.values&.first,
        args:,
        ambiguous_cask: ambiguous_casks.include?(formula_or_cask),
      )
    end
  end

  sig { params(args: CLI::Args).void }
  def handle_api_response(args)
    limit = args.limit.to_i if args.limit.present?

    api_response = {}
    unless args.cask?
      api_response[:formulae] =
        Repology.parse_api_response(limit, args.start_with, repository: Repology::HOMEBREW_CORE)
    end
    unless args.formula?
      api_response[:casks] =
        Repology.parse_api_response(limit, args.start_with, repository: Repology::HOMEBREW_CASK)
    end

    api_response.each_with_index do |(package_type, outdated_packages), idx|
      repository = if package_type == :formulae
        Repology::HOMEBREW_CORE
      else
        Repology::HOMEBREW_CASK
      end
      puts if idx.positive?
      oh1 package_type.capitalize if api_response.size > 1

      outdated_packages.each_with_index do |(_name, repositories), i|
        break if limit && i >= limit

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
        name = Livecheck.package_or_resource_name(formula_or_cask)
        ambiguous_cask = begin
          formula_or_cask.is_a?(Cask::Cask) && !args.cask? && Formula[name]
        rescue FormulaUnavailableError
          false
        end

        puts if i.positive?
        next if skip_ineligible_formulae(formula_or_cask)

        retrieve_and_display_info_and_open_pr(
          formula_or_cask,
          name,
          repositories,
          args:,
          ambiguous_cask:,
        )
      end
    end
  end

  sig {
    params(formula_or_cask: T.any(Formula, Cask::Cask)).returns(T::Boolean)
  }
  def skip_ineligible_formulae(formula_or_cask)
    if formula_or_cask.is_a?(Formula)
      skip = formula_or_cask.disabled? || formula_or_cask.head_only?
      name = formula_or_cask.name
      text = "Formula is #{formula_or_cask.disabled? ? "disabled" : "HEAD-only"}.\n"
    else
      skip = formula_or_cask.disabled?
      name = formula_or_cask.token
      text = "Cask is disabled.\n"
    end
    unless formula_or_cask.tap.allow_bump?(name)
      skip = true
      text = "#{text.split.first} is on autobump list.\n"
    end
    return false unless skip

    ohai name
    puts text
    true
  end

  sig {
    params(formula_or_cask: T.any(Formula, Cask::Cask)).returns(T.any(Version, String))
  }
  def livecheck_result(formula_or_cask)
    name = Livecheck.package_or_resource_name(formula_or_cask)

    referenced_formula_or_cask, = Livecheck.resolve_livecheck_reference(
      formula_or_cask,
      full_name: false,
      debug:     false,
    )

    # Check skip conditions for a referenced formula/cask
    if referenced_formula_or_cask
      skip_info = Livecheck::SkipConditions.referenced_skip_information(
        referenced_formula_or_cask,
        name,
        full_name: false,
        verbose:   false,
      )
    end

    skip_info ||= Livecheck::SkipConditions.skip_information(
      formula_or_cask,
      full_name: false,
      verbose:   false,
    )

    if skip_info.present?
      return "#{skip_info[:status]}#{" - #{skip_info[:messages].join(", ")}" if skip_info[:messages].present?}"
    end

    version_info = Livecheck.latest_version(
      formula_or_cask,
      referenced_formula_or_cask:,
      json: true, full_name: false, verbose: true, debug: false
    )
    return "unable to get versions" if version_info.blank?

    latest = version_info[:latest]

    Version.new(latest)
  rescue => e
    "error: #{e}"
  end

  sig {
    params(
      formula_or_cask: T.any(Formula, Cask::Cask),
      name:            String,
      state:           String,
      version:         T.nilable(String),
    ).returns T.nilable(T.any(T::Array[String], String))
  }
  def retrieve_pull_requests(formula_or_cask, name, state:, version: nil)
    tap_remote_repo = formula_or_cask.tap&.remote_repo || formula_or_cask.tap&.full_name
    pull_requests = begin
      GitHub.fetch_pull_requests(name, tap_remote_repo, state:, version:)
    rescue GitHub::API::ValidationFailedError => e
      odebug "Error fetching pull requests for #{formula_or_cask} #{name}: #{e}"
      nil
    end

    pull_requests&.map { |pr| "#{pr["title"]} (#{Formatter.url(pr["html_url"])})" }&.join(", ")
  end

  sig {
    params(
      formula_or_cask: T.any(Formula, Cask::Cask),
      repositories:    T::Array[T.untyped],
      args:            CLI::Args,
      name:            String,
    ).returns(VersionBumpInfo)
  }
  def retrieve_versions_by_arch(formula_or_cask:, repositories:, args:, name:)
    is_cask_with_blocks = formula_or_cask.is_a?(Cask::Cask) && formula_or_cask.on_system_blocks_exist?
    type, version_name = formula_or_cask.is_a?(Formula) ? [:formula, "formula version:"] : [:cask, "cask version:   "]

    old_versions = {}
    new_versions = {}

    repology_latest = repositories.present? ? Repology.latest_version(repositories) : "not found"

    # When blocks are absent, arch is not relevant. For consistency, we simulate the arm architecture.
    arch_options = is_cask_with_blocks ? OnSystem::ARCH_OPTIONS : [:arm]

    arch_options.each do |arch|
      SimulateSystem.with(arch:) do
        version_key = is_cask_with_blocks ? arch : :general

        # We reload the formula/cask here to ensure we're getting the correct version for the current arch
        if formula_or_cask.is_a?(Formula)
          loaded_formula_or_cask = formula_or_cask
          current_version_value = T.must(loaded_formula_or_cask.stable).version
        else
          loaded_formula_or_cask = Cask::CaskLoader.load(formula_or_cask.sourcefile_path)
          current_version_value = Version.new(loaded_formula_or_cask.version)
        end

        livecheck_latest = livecheck_result(loaded_formula_or_cask)

        new_version_value = if (livecheck_latest.is_a?(Version) && livecheck_latest >= current_version_value) ||
                               current_version_value == "latest"
          livecheck_latest
        elsif livecheck_latest.is_a?(String) && livecheck_latest.start_with?("skipped")
          "skipped"
        elsif repology_latest.is_a?(Version) &&
              repology_latest > current_version_value &&
              !loaded_formula_or_cask.livecheckable? &&
              current_version_value != "latest"
          repology_latest
        end.presence

        # Store old and new versions
        old_versions[version_key] = current_version_value
        new_versions[version_key] = new_version_value
      end
    end

    # If arm and intel versions are identical, as it happens with casks where only the checksums differ,
    # we consolidate them into a single version.
    if old_versions[:arm].present? && old_versions[:arm] == old_versions[:intel]
      old_versions = { general: old_versions[:arm] }
    end
    if new_versions[:arm].present? && new_versions[:arm] == new_versions[:intel]
      new_versions = { general: new_versions[:arm] }
    end

    multiple_versions = old_versions.values_at(:arm, :intel).all?(&:present?) ||
                        new_versions.values_at(:arm, :intel).all?(&:present?)

    current_version = BumpVersionParser.new(general: old_versions[:general],
                                            arm:     old_versions[:arm],
                                            intel:   old_versions[:intel])

    begin
      new_version = BumpVersionParser.new(general: new_versions[:general],
                                          arm:     new_versions[:arm],
                                          intel:   new_versions[:intel])
    rescue
      # When livecheck fails, we fail gracefully. Otherwise VersionParser will
      # raise a usage error
      new_version = BumpVersionParser.new(general: "unable to get versions")
    end

    # We use the arm version for the pull request version. This is consistent
    # with the behavior of bump-cask-pr.
    pull_request_version = if multiple_versions && new_version.general != "unable to get versions"
      new_version.arm.to_s
    else
      new_version.general.to_s
    end

    open_pull_requests = if !args.no_pull_requests? && (args.named.present? || new_version.present?)
      retrieve_pull_requests(formula_or_cask, name, state: "open")
    end.presence

    closed_pull_requests = if !args.no_pull_requests? && open_pull_requests.blank? && new_version.present?
      retrieve_pull_requests(formula_or_cask, name, state: "closed", version: pull_request_version)
    end.presence

    VersionBumpInfo.new(
      type:,
      multiple_versions:,
      version_name:,
      current_version:,
      repology_latest:,
      new_version:,
      open_pull_requests:,
      closed_pull_requests:,
    )
  end

  sig {
    params(
      formula_or_cask: T.any(Formula, Cask::Cask),
      name:            String,
      repositories:    T::Array[T.untyped],
      args:            CLI::Args,
      ambiguous_cask:  T::Boolean,
    ).void
  }
  def retrieve_and_display_info_and_open_pr(formula_or_cask, name, repositories, args:, ambiguous_cask: false)
    version_info = retrieve_versions_by_arch(formula_or_cask:,
                                             repositories:,
                                             args:,
                                             name:)

    current_version = version_info.current_version
    new_version = version_info.new_version
    repology_latest = version_info.repology_latest

    # Check if all versions are equal
    versions_equal = [:arm, :intel, :general].all? do |key|
      current_version.send(key) == new_version.send(key)
    end

    title_name = ambiguous_cask ? "#{name} (cask)" : name
    title = if (repology_latest == current_version.general || !repology_latest.is_a?(Version)) && versions_equal
      "#{title_name} #{Tty.green}is up to date!#{Tty.reset}"
    else
      title_name
    end

    # Conditionally format output based on type of formula_or_cask
    current_versions = if version_info.multiple_versions
      "arm:   #{current_version.arm}
                          intel: #{current_version.intel}"
    else
      current_version.general.to_s
    end
    current_versions << " (deprecated)" if formula_or_cask.deprecated?

    new_versions = if version_info.multiple_versions && new_version.arm && new_version.intel
      "arm:   #{new_version.arm}
                          intel: #{new_version.intel}"
    else
      new_version.general
    end

    version_label = version_info.version_name
    open_pull_requests = version_info.open_pull_requests.presence
    closed_pull_requests = version_info.closed_pull_requests.presence

    ohai title
    puts <<~EOS
      Current #{version_label}  #{current_versions}
      Latest livecheck version: #{new_versions}
    EOS
    puts <<~EOS unless skip_repology?(formula_or_cask, args:)
      Latest Repology version:  #{repology_latest}
    EOS
    if formula_or_cask.is_a?(Formula) && formula_or_cask.synced_with_other_formulae?
      outdated_synced_formulae = synced_with(formula_or_cask, new_version.general)
      puts <<~EOS if outdated_synced_formulae.present?
        Version syncing:          #{title_name} version should be kept in sync with
                                  #{outdated_synced_formulae.join(", ")}.
      EOS
    end
    puts <<~EOS unless args.no_pull_requests?
      Open pull requests:       #{open_pull_requests || "none"}
      Closed pull requests:     #{closed_pull_requests || "none"}
    EOS

    return unless args.open_pr?

    if repology_latest.is_a?(Version) &&
       repology_latest > current_version.general &&
       repology_latest > new_version.general &&
       formula_or_cask.livecheckable?
      puts "#{title_name} was not bumped to the Repology version because it's livecheckable."
    end
    if new_version.blank? || versions_equal ||
       (!new_version.general.is_a?(Version) && !version_info.multiple_versions)
      return
    end

    return if open_pull_requests.present? || closed_pull_requests.present?

    version_args = if version_info.multiple_versions
      %W[--version-arm=#{new_version.arm} --version-intel=#{new_version.intel}]
    else
      "--version=#{new_version.general}"
    end

    bump_cask_pr_args = [
      "bump-#{version_info.type}-pr",
      name,
      *version_args,
      "--no-browse",
      "--message=Created by `brew bump`",
    ]

    bump_cask_pr_args << "--no-fork" if args.no_fork?

    system HOMEBREW_BREW_FILE, *bump_cask_pr_args
  end

  sig {
    params(
      formula:     Formula,
      new_version: T.nilable(T.any(Version, Cask::DSL::Version)),
    ).returns(T::Array[String])
  }
  def synced_with(formula, new_version)
    synced_with = []

    formula.tap&.synced_versions_formulae&.each do |synced_formulae|
      next unless synced_formulae.include?(formula.name)

      synced_formulae.each do |synced_formula|
        synced_formula = Formulary.factory(synced_formula)
        next if synced_formula == formula.name

        synced_with << synced_formula.name if synced_formula.version != new_version
      end
    end

    synced_with
  end
end
