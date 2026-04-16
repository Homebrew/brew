# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "bump_version_parser"
require "livecheck/livecheck"
require "utils/curl"
require "utils/repology"

module Homebrew
  module DevCmd
    class Bump < AbstractCommand
      MIN_RELEASE_AGE_DAYS = 1
      DEFAULT_CURL_ARGS = T.let([
        "--compressed",
        "--fail-with-body",
        "--location",
        "--max-redirs",
        "5",
        "--silent",
      ].freeze, T::Array[String])
      DEFAULT_CURL_OPTIONS = T.let({
        connect_timeout: 15,
        max_time:        55,
        timeout:         60,
        retries:         0,
      }.freeze, T::Hash[Symbol, T.untyped])
      PYPI_UNSTABLE_VERSION_REGEX = /^(?:\d+!)?\d+(?:\.\d+)*(?:a|b|rc)\d+|\.dev\d+$/i

      LIVECHECK_MESSAGE_REGEX = /^(?:error:|skipped|unable to get(?: throttled)? versions)/i
      NEWER_THAN_UPSTREAM_MSG = " (newer than upstream)"

      class ResourceVersionInfo < T::Struct
        const :name, String
        const :current_version, String
        const :latest_version, T.nilable(String)
        const :outdated, T::Boolean
        const :newer_than_upstream, T::Boolean
      end

      class VersionBumpInfo < T::Struct
        const :type, Symbol
        const :deprecated, T::Hash[Symbol, T::Boolean], default: {}
        const :multiple_versions, T::Hash[Symbol, T::Boolean], default: {}
        const :version_name, String
        const :current_version, BumpVersionParser
        const :new_version, BumpVersionParser
        const :resource_versions, T::Array[ResourceVersionInfo], default: []
        const :repology_latest, T.any(String, Version)
        const :newer_than_upstream, T::Hash[Symbol, T::Boolean], default: {}
        const :duplicate_pull_requests, T.nilable(T.any(T::Array[String], String))
        const :maybe_duplicate_pull_requests, T.nilable(T.any(T::Array[String], String))
      end

      cmd_args do
        description <<~EOS
          Displays out-of-date packages and the latest version available. If the
          returned current and livecheck versions differ or when querying specific
          packages, also displays whether a pull request has been opened with the URL.
        EOS
        switch "--full-name",
               description: "Print formulae/casks with fully-qualified names."
        switch "--no-pull-requests",
               description: "Do not retrieve pull requests from GitHub."
        switch "--auto",
               description: "Read the list of formulae/casks from the tap autobump list.",
               hidden:      true
        switch "--no-autobump",
               description: "Ignore formulae/casks in autobump list (official repositories only)."
        switch "--formula", "--formulae",
               description: "Check only formulae."
        switch "--cask", "--casks",
               description: "Check only casks."
        switch "--eval-all",
               description: "Evaluate all formulae and casks.",
               env:         :eval_all
        switch "--repology",
               description: "Use Repology to check for outdated packages."
        flag   "--tap=",
               description: "Check formulae and casks within the given tap, specified as <user>`/`<repo>."
        switch "--installed",
               description: "Check formulae and casks that are currently installed."
        switch "--no-fork",
               description: "Don't try to fork the repository."
        switch "--open-pr",
               description: "Open a pull request for the new version if none have been opened yet."
        flag   "--start-with=",
               description: "Letter or word that the list of package results should alphabetically follow."
        switch "--bump-synced",
               description: "Bump additional formulae marked as synced with the given formulae."

        conflicts "--formula", "--cask"
        conflicts "--tap", "--installed"
        conflicts "--tap", "--no-autobump"
        conflicts "--installed", "--eval-all"
        conflicts "--installed", "--auto"
        conflicts "--no-pull-requests", "--open-pr"

        named_args [:formula, :cask], without_api: true
      end

      sig { override.void }
      def run
        Homebrew.install_bundler_gems!(groups: ["livecheck"])

        Homebrew.with_no_api_env do
          eval_all = args.eval_all?

          excluded_autobump = []
          if args.no_autobump? && eval_all
            excluded_autobump.concat(autobumped_formulae_or_casks(CoreTap.instance)) if args.formula?
            excluded_autobump.concat(autobumped_formulae_or_casks(CoreCaskTap.instance, casks: true)) if args.cask?
          end

          formulae_and_casks = if args.auto?
            raise UsageError, "`--formula` or `--cask` must be passed with `--auto`." if !args.formula? && !args.cask?

            tap_arg = args.tap
            raise UsageError, "`--tap=` must be passed with `--auto`." if tap_arg.blank?

            tap = Tap.fetch(tap_arg)
            autobump_list = tap.autobump
            what = args.cask? ? "casks" : "formulae"
            raise UsageError, "No autobumped #{what} found." if autobump_list.blank?

            # Only run bump on the first formula in each synced group
            if args.bump_synced? && args.formula?
              synced_formulae = Set.new(tap.synced_versions_formulae.flat_map { it.drop(1) })
            end

            autobump_list.filter_map do |name|
              qualified_name = "#{tap.name}/#{name}"
              next Cask::CaskLoader.load(qualified_name) if args.cask?
              next if synced_formulae&.include?(name)

              Formulary.factory(qualified_name)
            end
          elsif args.tap
            tap = Tap.fetch(args.tap)
            raise UsageError, "`--tap` requires `--auto` for official taps." if tap.official?

            formulae = args.cask? ? [] : tap.formula_files.map { |path| Formulary.factory(path) }
            casks = args.formula? ? [] : tap.cask_files.map { |path| Cask::CaskLoader.load(path) }
            formulae + casks
          elsif args.installed?
            formulae = args.cask? ? [] : Formula.installed
            casks = args.formula? ? [] : Cask::Caskroom.casks
            formulae + casks
          elsif args.named.present?
            T.cast(args.named.to_formulae_and_casks_with_taps, T::Array[T.any(Formula, Cask::Cask)])
          elsif eval_all
            formulae = args.cask? ? [] : Formula.all(eval_all:)
            casks = args.formula? ? [] : Cask::Cask.all(eval_all:)
            formulae + casks
          else
            raise UsageError,
                  "`brew bump` without named arguments needs `--installed` or `--eval-all` passed or " \
                  "`HOMEBREW_EVAL_ALL=1` set!"
          end

          if (start_with = args.start_with)
            formulae_and_casks.select! do |formula_or_cask|
              name = formula_or_cask.is_a?(Cask::Cask) ? formula_or_cask.token : formula_or_cask.name
              name.start_with?(start_with)
            end
          end

          formulae_and_casks = formulae_and_casks.sort_by do |formula_or_cask|
            formula_or_cask.is_a?(Cask::Cask) ? formula_or_cask.token : formula_or_cask.name
          end

          formulae_and_casks -= excluded_autobump

          if args.repology? && !Utils::Curl.curl_supports_tls13?
            begin
              Formula["curl"].ensure_installed!(reason: "Repology queries") unless HOMEBREW_BREWED_CURL_PATH.exist?
            rescue FormulaUnavailableError
              opoo "A newer `curl` is required for Repology queries."
            end
          end

          handle_formulae_and_casks(formulae_and_casks)
        end
      end

      private

      sig { params(formula_or_cask: T.any(Formula, Cask::Cask)).returns(T::Boolean) }
      def skip_repology?(formula_or_cask)
        return true unless args.repology?

        (ENV["CI"].present? && args.open_pr? && formula_or_cask.livecheck_defined?) ||
          (formula_or_cask.is_a?(Formula) && formula_or_cask.versioned_formula?)
      end

      sig { params(formulae_and_casks: T::Array[T.any(Formula, Cask::Cask)]).void }
      def handle_formulae_and_casks(formulae_and_casks)
        Livecheck.load_other_tap_strategies(formulae_and_casks)

        ambiguous_casks = []
        if !args.formula? && !args.cask?
          ambiguous_casks = formulae_and_casks
                            .group_by { |item| Livecheck.package_or_resource_name(item, full_name: true) }
                            .values
                            .select { |items| items.length > 1 }
                            .flatten
                            .grep(Cask::Cask)
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
          next if skip_ineligible_formulae!(formula_or_cask)

          use_full_name = args.full_name? || ambiguous_names.include?(formula_or_cask)
          name = Livecheck.package_or_resource_name(formula_or_cask, full_name: use_full_name)
          repository = if formula_or_cask.is_a?(Formula)
            Repology::HOMEBREW_CORE
          else
            Repology::HOMEBREW_CASK
          end

          package_data = Repology.single_package_query(name, repository:) unless skip_repology?(formula_or_cask)

          retrieve_and_display_info_and_open_pr(
            formula_or_cask,
            name,
            package_data&.values&.first || [],
            ambiguous_cask: ambiguous_casks.include?(formula_or_cask),
          )
        end
      end

      sig {
        params(formula_or_cask: T.any(Formula, Cask::Cask)).returns(T::Boolean)
      }
      def skip_ineligible_formulae!(formula_or_cask)
        if formula_or_cask.is_a?(Formula)
          skip = formula_or_cask.disabled? || formula_or_cask.head_only?
          name = formula_or_cask.name
          text = "Formula is #{formula_or_cask.disabled? ? "disabled" : "HEAD-only"} so not accepting updates.\n"
        else
          skip = formula_or_cask.disabled? || formula_or_cask.version.latest?
          name = formula_or_cask.token
          text = if formula_or_cask.disabled?
            "Cask is disabled so not accepting updates.\n"
          else
            "Cask uses `version :latest` so `brew bump` cannot check it.\n"
          end
        end
        if (tap = formula_or_cask.tap) && !tap.allow_bump?(name)
          skip = true
          text = "#{text.split.first} is autobumped so will have bump PRs opened by BrewTestBot every ~3 hours.\n"
        end
        return false unless skip

        ohai name
        puts text
        true
      end

      sig {
        params(
          formula_or_cask: T.any(Formula, Cask::Cask),
          current:         T.nilable(T.any(Version, Cask::DSL::Version)),
        ).returns(T.any(Version, String))
      }
      def livecheck_result(formula_or_cask, current)
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
          skip_status = skip_info[:status]
          skip_messages = skip_info[:messages]
          skip_message = skip_messages.join("; ") if skip_messages.present?
          return "error: #{skip_message}" if skip_status == "error" && skip_message

          return "skipped - #{skip_message || skip_status}"
        end

        version_info = Livecheck.latest_version(
          formula_or_cask,
          referenced_formula_or_cask:,
          json: true, full_name: false, verbose: true, debug: false
        )
        return "unable to get versions" if version_info.blank?

        if !version_info.key?(:latest_throttled)
          version_with_cooldown(version_info, current) || Version.new(version_info[:latest])
        elsif version_info[:latest_throttled].nil?
          "unable to get throttled versions"
        else
          Version.new(version_info[:latest_throttled])
        end
      rescue => e
        "error: #{e}"
      end

      sig {
        params(
          formula_or_cask: T.any(Formula, Cask::Cask),
          name:            String,
          version:         T.nilable(String),
        ).returns T.nilable(T.any(T::Array[String], String))
      }
      def retrieve_pull_requests(formula_or_cask, name, version: nil)
        tap_remote_repo = formula_or_cask.tap&.remote_repository || formula_or_cask.tap&.full_name
        odie "unexpected nil tap remote repository" if tap_remote_repo.nil?

        pull_requests = begin
          GitHub.fetch_pull_requests(name, tap_remote_repo, version:)
        rescue GitHub::API::ValidationFailedError => e
          odebug "Error fetching pull requests for #{formula_or_cask} #{name}: #{e}"
          nil
        end
        return if pull_requests.blank?

        pull_requests.map { |pr| "#{pr["title"]} (#{Formatter.url(pr["html_url"])})" }.join(", ")
      end

      sig {
        params(
          formula_or_cask: T.any(Formula, Cask::Cask),
          repositories:    T::Array[String],
          name:            String,
        ).returns(VersionBumpInfo)
      }
      def retrieve_versions_by_arch(formula_or_cask:, repositories:, name:)
        is_cask_with_blocks = formula_or_cask.is_a?(Cask::Cask) && formula_or_cask.on_system_blocks_exist?
        type, version_name = if formula_or_cask.is_a?(Formula)
          [:formula, "formula version:"]
        else
          [:cask, "cask version:   "]
        end

        deprecated = {}
        current_versions = {}
        new_versions = {}

        repology_latest = repositories.present? ? Repology.latest_version(repositories) : "not found"
        repology_latest_is_a_version = repology_latest.is_a?(Version)

        # When blocks are absent, arch is not relevant. For consistency, we
        # simulate the arm architecture.
        arch_options = is_cask_with_blocks ? OnSystem::ARCH_OPTIONS : [:arm]

        arch_options.each do |arch|
          SimulateSystem.with(arch:) do
            version_key = is_cask_with_blocks ? arch : :general

            # We reload the formula/cask here to ensure we're getting the
            # correct version for the current arch
            if formula_or_cask.is_a?(Formula)
              loaded_formula_or_cask = formula_or_cask
              stable = loaded_formula_or_cask.stable
              raise "unexpected nil stable" unless stable

              current_version_value = stable.version
            else
              sourcefile_path = formula_or_cask.sourcefile_path
              raise "unexpected nil sourcefile_path" unless sourcefile_path

              loaded_formula_or_cask = Cask::CaskLoader.load(sourcefile_path)
              current_version_value = Version.new(loaded_formula_or_cask.version)
            end

            deprecated[version_key] = loaded_formula_or_cask.deprecated?
            formula_or_cask_has_livecheck = loaded_formula_or_cask.livecheck_defined?

            livecheck_latest = livecheck_result(loaded_formula_or_cask, current_version_value)
            livecheck_latest_is_a_version = livecheck_latest.is_a?(Version)

            new_version_value = if (livecheck_latest_is_a_version &&
                                    Livecheck::LivecheckVersion.create(formula_or_cask, livecheck_latest) >=
                                    Livecheck::LivecheckVersion.create(formula_or_cask, current_version_value)) ||
                                   current_version_value == "latest" ||
                                   message?(livecheck_latest)
              livecheck_latest
            elsif repology_latest_is_a_version &&
                  !formula_or_cask_has_livecheck &&
                  repology_latest > current_version_value &&
                  current_version_value != "latest"
              repology_latest
            end.presence

            # Fall back to the upstream version if there isn't a new version
            # value at this point, as this will allow us to surface an upstream
            # version that's lower than the current version.
            new_version_value ||= livecheck_latest if livecheck_latest_is_a_version
            new_version_value ||= repology_latest if repology_latest_is_a_version && !formula_or_cask_has_livecheck

            # Store old and new versions
            current_versions[version_key] = current_version_value
            new_versions[version_key] = new_version_value
          end
        end

        # If arm and intel versions are identical, as it happens with casks
        # where only the checksums differ, we consolidate them into a single
        # version.
        if current_versions[:arm].present? && current_versions[:arm] == current_versions[:intel]
          current_versions = { general: current_versions[:arm] }
        end
        if new_versions[:arm].present? && new_versions[:arm] == new_versions[:intel]
          new_versions = { general: new_versions[:arm] }
        end

        current_version = BumpVersionParser.new(general: current_versions[:general],
                                                arm:     current_versions[:arm],
                                                intel:   current_versions[:intel])

        begin
          new_version = BumpVersionParser.new(general: new_versions[:general],
                                              arm:     new_versions[:arm],
                                              intel:   new_versions[:intel])
        rescue
          # When livecheck fails, we fail gracefully. Otherwise VersionParser
          # will raise a usage error
          new_version = BumpVersionParser.new(general: "unable to get versions")
        end

        compare_versions(current_version, new_version, formula_or_cask) =>
          { multiple_versions:, newer_than_upstream: }
        if !multiple_versions[:current] && deprecated[:general].nil?
          deprecated = { general: deprecated[:arm] || deprecated[:intel] || false }
        end

        # Collect resource version info for formulae with resources that have explicit livecheck blocks
        resource_versions = if formula_or_cask.is_a?(Formula) && new_version.general.is_a?(Version)
          collect_resource_versions(formula_or_cask, new_version.general.to_s)
        else
          []
        end

        if !args.no_pull_requests? &&
           !newer_than_upstream.all? { |_k, v| v == true }
          pull_request_version = nil
          if (new_version_arm = new_version.arm) &&
             !message?(new_version_arm) &&
             (new_version_arm != current_version.arm)
            # We use the ARM version for the pull request version even if there
            # are multiple arch versions to be consistent with the behavior of
            # bump-cask-pr.
            pull_request_version = new_version_arm.to_s
          elsif (new_version_intel = new_version.intel) &&
                !message?(new_version_intel) &&
                (new_version_intel != current_version.intel)
            pull_request_version = new_version_intel.to_s
          elsif (new_version_general = new_version.general) &&
                !message?(new_version_general) &&
                (new_version_general != current_version.general)
            pull_request_version = new_version_general.to_s
          end

          if pull_request_version
            duplicate_pull_requests = retrieve_pull_requests(
              formula_or_cask,
              name,
              version: pull_request_version,
            )

            maybe_duplicate_pull_requests = if duplicate_pull_requests.nil?
              retrieve_pull_requests(formula_or_cask, name)
            end
          end
        end

        VersionBumpInfo.new(
          type:,
          deprecated:,
          multiple_versions:,
          version_name:,
          current_version:,
          new_version:,
          resource_versions:,
          repology_latest:,
          newer_than_upstream:,
          duplicate_pull_requests:,
          maybe_duplicate_pull_requests:,
        )
      end

      sig {
        params(
          formula:                Formula,
          formula_latest_version: String,
        ).returns(T::Array[ResourceVersionInfo])
      }
      def collect_resource_versions(formula, formula_latest_version)
        resource_versions = []

        formula.resources.each do |resource|
          next unless resource.livecheck_defined?
          next if resource.livecheck.skip?

          # Resources that reference :parent track the formula version directly
          if resource.livecheck.formula == :parent
            current = resource.version.to_s
            resource_versions << ResourceVersionInfo.new(
              name:                resource.name,
              current_version:     current,
              latest_version:      formula_latest_version,
              outdated:            Version.new(current) < Version.new(formula_latest_version),
              newer_than_upstream: Version.new(current) > Version.new(formula_latest_version),
            )
            next
          end

          resource_info = Livecheck.resource_version(
            resource,
            formula_latest_version,
            json:      true,
            full_name: false,
            debug:     false,
            quiet:     true,
            verbose:   false,
          )

          if resource_info.empty? || resource_info[:status] == "error"
            resource_versions << ResourceVersionInfo.new(
              name:                resource.name,
              current_version:     resource.version.to_s,
              latest_version:      nil,
              outdated:            false,
              newer_than_upstream: false,
            )
            next
          end

          version_info = resource_info[:version]
          next if version_info.blank?

          resource_versions << ResourceVersionInfo.new(
            name:                resource.name,
            current_version:     version_info[:current],
            latest_version:      version_info[:latest],
            outdated:            version_info[:outdated] == true,
            newer_than_upstream: version_info[:newer_than_upstream] == true,
          )
        end

        resource_versions
      end

      sig {
        params(
          formula_or_cask: T.any(Formula, Cask::Cask),
          name:            String,
          repositories:    T::Array[String],
          ambiguous_cask:  T::Boolean,
        ).void
      }
      def retrieve_and_display_info_and_open_pr(formula_or_cask, name, repositories, ambiguous_cask: false)
        version_info = retrieve_versions_by_arch(formula_or_cask:,
                                                 repositories:,
                                                 name:)

        deprecated = version_info.deprecated
        multiple_versions = version_info.multiple_versions
        current_version = version_info.current_version
        new_version = version_info.new_version
        repology_latest = version_info.repology_latest
        newer_than_upstream = version_info.newer_than_upstream
        duplicate_pull_requests = version_info.duplicate_pull_requests
        maybe_duplicate_pull_requests = version_info.maybe_duplicate_pull_requests

        versions_equal = (new_version == current_version)
        all_newer_than_upstream = newer_than_upstream.all? { |_k, v| v == true }

        title_name = ambiguous_cask ? "#{name} (cask)" : name
        title = if (repology_latest == current_version.general || !repology_latest.is_a?(Version)) && versions_equal
          "#{title_name} #{Tty.green}is up to date!#{Tty.reset}"
        else
          title_name
        end

        # Conditionally format output based on type of formula_or_cask
        current_versions = if multiple_versions[:current]
          "arm:   #{current_version.arm || current_version.general}" \
            "#{NEWER_THAN_UPSTREAM_MSG if newer_than_upstream[:arm]}" \
            "#{" (deprecated)" if deprecated[:arm]}" \
            "\n                          " \
            "intel: #{current_version.intel || current_version.general}" \
            "#{NEWER_THAN_UPSTREAM_MSG if newer_than_upstream[:intel]}" \
            "#{" (deprecated)" if deprecated[:intel]}"
        else
          "#{current_version.general}" \
            "#{NEWER_THAN_UPSTREAM_MSG if newer_than_upstream[:general]}" \
            "#{" (deprecated)" if deprecated[:general]}"
        end

        new_versions = if multiple_versions[:new] && new_version.arm && new_version.intel
          "arm:   #{new_version.arm}
                          intel: #{new_version.intel}"
        else
          new_version.general
        end

        ohai title
        puts <<~EOS
          Current #{version_info.version_name}  #{current_versions}
          Latest livecheck version: #{new_versions}#{" (throttled)" if formula_or_cask.livecheck.throttle}
        EOS
        puts <<~EOS unless skip_repology?(formula_or_cask)
          Latest Repology version:  #{repology_latest}
        EOS
        if formula_or_cask.is_a?(Formula) && formula_or_cask.synced_with_other_formulae?
          outdated_synced_formulae = synced_with(formula_or_cask, new_version.general)
          if !args.bump_synced? && outdated_synced_formulae.present?
            puts <<~EOS
              Version syncing:          #{title_name} version should be kept in sync with
                                        #{outdated_synced_formulae.join(", ")}.
            EOS
          end
        end

        # Display resource version info for formulae
        resource_versions = version_info.resource_versions
        puts "Resources with livecheck:" unless resource_versions.empty?
        resource_versions.each do |rv|
          status = if rv.latest_version.nil?
            "#{Tty.red}unable to get versions#{Tty.reset}"
          elsif rv.newer_than_upstream
            "#{Tty.red}#{rv.current_version}#{Tty.reset} -> #{rv.latest_version}#{NEWER_THAN_UPSTREAM_MSG}"
          elsif rv.outdated
            "#{rv.current_version} -> #{Tty.green}#{rv.latest_version}#{Tty.reset}"
          else
            "#{rv.current_version} -> #{rv.latest_version}"
          end
          puts "  #{rv.name}: #{status}"
        end

        if !args.no_pull_requests? &&
           !message?(new_version.general) &&
           !versions_equal &&
           !all_newer_than_upstream
          if duplicate_pull_requests
            duplicate_pull_requests_text = duplicate_pull_requests
          elsif maybe_duplicate_pull_requests
            duplicate_pull_requests_text = "none"
            maybe_duplicate_pull_requests_text = maybe_duplicate_pull_requests
          else
            duplicate_pull_requests_text = "none"
            maybe_duplicate_pull_requests_text = "none"
          end

          puts "Duplicate pull requests:  #{duplicate_pull_requests_text}"
          if maybe_duplicate_pull_requests_text
            puts "Maybe duplicate pull requests: #{maybe_duplicate_pull_requests_text}"
          end
        end

        if !args.open_pr? ||
           message?(new_version.general) ||
           all_newer_than_upstream
          return
        end

        if GitHub.too_many_open_prs?(formula_or_cask.tap)
          odie "You have too many PRs open: close or merge some first!"
        end

        if repology_latest.is_a?(Version) &&
           repology_latest > current_version.general &&
           repology_latest > new_version.general &&
           formula_or_cask.livecheck_defined?
          puts "#{title_name} was not bumped to the Repology version because it has a `livecheck` block."
        end
        if new_version.blank? || versions_equal ||
           (!new_version.general.is_a?(Version) && !multiple_versions[:new])
          return
        end

        return if duplicate_pull_requests.present?

        version_args = []
        if multiple_versions[:current] && multiple_versions[:new]
          if (new_version_arm = new_version.arm) &&
             !message?(new_version_arm) &&
             current_version.arm &&
             new_version_arm > current_version.arm
            version_args << "--version-arm=#{new_version_arm}"
          end
          if (new_version_intel = new_version.intel) &&
             !message?(new_version_intel) &&
             current_version.intel &&
             new_version_intel > current_version.intel
            version_args << "--version-intel=#{new_version_intel}"
          end
        elsif multiple_versions[:current]
          opoo "`#{name}` needs to be manually updated using one version"
        elsif multiple_versions[:new]
          opoo "`#{name}` needs to be manually updated using arch-specific versions"
        elsif new_version.general
          version_args << "--version=#{new_version.general}"
        end
        return if version_args.blank?

        bump_pr_args = [
          "bump-#{version_info.type}-pr",
          name,
          *version_args,
          "--no-browse",
          "--message=Created by `brew bump`",
        ]

        bump_pr_args << "--no-fork" if args.no_fork?

        if args.bump_synced? && outdated_synced_formulae.present?
          bump_pr_args << "--bump-synced=#{outdated_synced_formulae.join(",")}"
        end

        # Pass all livecheck-checked resources to bump-formula-pr, including
        # up-to-date and failed ones, so it can track what was checked
        if version_info.type == :formula && !resource_versions.empty?
          require "json"
          resource_data = resource_versions.map do |rv|
            { name: rv.name, current_version: rv.current_version, latest_version: rv.latest_version }
          end
          bump_pr_args << "--resource-versions=#{resource_data.to_json}"
        end

        result = system HOMEBREW_BREW_FILE, *bump_pr_args
        Homebrew.failed = true unless result
      end

      sig {
        params(
          current_version: BumpVersionParser,
          new_version:     BumpVersionParser,
          formula_or_cask: T.any(Formula, Cask::Cask),
        ).returns(T::Hash[Symbol, T::Hash[Symbol, T::Boolean]])
      }
      def compare_versions(current_version, new_version, formula_or_cask)
        current_versions = {}
        new_versions = {}
        BumpVersionParser::VERSION_SYMBOLS.each do |type|
          current_version_value = current_version.send(type)
          if current_version_value
            current_versions[type] = Livecheck::LivecheckVersion.create(formula_or_cask, current_version_value)
          end

          new_version_value = new_version.send(type)
          if message?(new_version_value)
            # Store a string, so we can easily tell when a value is a message
            # rather than a version
            new_versions[type] = new_version_value.to_s
          elsif new_version_value
            new_versions[type] = Livecheck::LivecheckVersion.create(formula_or_cask, new_version_value)
          end
        end

        multiple_versions = {
          current: current_versions.length > 1,
          new:     new_versions.length > 1,
        }

        current_version_types = current_versions.keys
        new_version_types = new_versions.keys
        comparison_pairs = {}

        # Compare the same version types when shared by current/new versions
        (current_version_types & new_version_types).each do |type|
          comparison_pairs[type] = [current_versions[type], new_versions[type]]
        end

        # Compare current versions to `new_version.general` when the current
        # version differs by arch but the new version does not
        if multiple_versions[:current] && new_versions.key?(:general)
          (current_version_types - new_version_types).each do |type|
            comparison_pairs[type] ||= [current_versions[type], new_versions[:general]]
          end
        end

        # Compare `current_version.general` to the highest new version when the
        # current version does not differ by arch but the new version does
        if !comparison_pairs.key?(:general) &&
           current_versions.key?(:general) &&
           multiple_versions[:new]
          highest_new_version = (new_version_types - current_version_types).filter_map do |type|
            version = new_versions[type]
            next unless version.is_a?(Livecheck::LivecheckVersion)

            version
          end.max
          comparison_pairs[:general] = [current_versions[:general], highest_new_version]
        end

        newer_than_upstream = {}
        comparison_pairs.each do |version_type, (current_value, new_value)|
          newer_than_upstream[version_type] = if new_value.is_a?(Livecheck::LivecheckVersion)
            (current_value > new_value)
          else
            false
          end
        end

        { multiple_versions:, newer_than_upstream: }
      end

      sig { params(value: T.nilable(T.any(Version, Cask::DSL::Version, String))).returns(T::Boolean) }
      def message?(value)
        return false if !value.is_a?(Cask::DSL::Version) && !value.is_a?(String)

        value.match?(LIVECHECK_MESSAGE_REGEX)
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

      sig { params(tap: Tap, casks: T::Boolean).returns(T::Array[T.any(Formula, Cask::Cask)]) }
      def autobumped_formulae_or_casks(tap, casks: false)
        autobump_list = tap.autobump
        autobump_list.map do |name|
          qualified_name = "#{tap.name}/#{name}"
          if casks
            Cask::CaskLoader.load(qualified_name)
          else
            Formulary.factory(qualified_name)
          end
        end
      end

      # Identifies the highest upstream version that has been released before
      # the cooldown interval.
      #
      # @param version_info the return hash from `Livecheck.latest_version`
      # @param current the current version
      sig {
        params(
          version_info: T::Hash[Symbol, T.untyped],
          current:      T.nilable(T.any(Version, Cask::DSL::Version)),
        ).returns(T.nilable(Version))
      }
      def version_with_cooldown(version_info, current = nil)
        return unless current

        latest = Version.new(version_info[:latest]) if version_info[:latest]
        return unless latest
        return if latest <= current

        strategy = T.cast(version_info.dig(:meta, :strategy), T.nilable(String))
        case strategy
        when "Npm"
          url = version_info.dig(:meta, :url, :strategy)&.delete_suffix("/latest")
          return unless url

          stdout, _stderr, status = Utils::Curl.curl_output(*DEFAULT_CURL_ARGS, url, **DEFAULT_CURL_OPTIONS)
          return unless status.success?
          return if (content = stdout.scrub).blank?

          json = Homebrew::Livecheck::Strategy::Json.parse_json(content)
          release_dates = json["time"]&.except("created", "modified")
                                      &.transform_values { |v| DateTime.parse(v) }
          return unless release_dates.present?

          current_str = current.to_s
          current_is_prerelease = current_str.include?("-")
          cooldown_interval = (DateTime.now - MIN_RELEASE_AGE_DAYS)
          release_dates.sort_by { |_, date| date }.reverse_each do |version_str, date|
            version = Version.new(version_str)
            return version if version_str == current_str
            next if (version > latest) || (version < current)

            # TODO: Properly handle prerelease version comparison
            next if !current_is_prerelease && version_str.include?("-")

            return version if date < cooldown_interval
          end
        when "Pypi"
          url = version_info.dig(:meta, :url, :strategy)
          original_url = version_info.dig(:meta, :url, :original)
          return if !url || !original_url

          suffix = Homebrew::Livecheck::Strategy::Pypi::URL_MATCH_REGEX.match(original_url)&.[](:suffix)
          return unless suffix

          content = version_info[:content]
          unless content
            stdout, _stderr, status = Utils::Curl.curl_output(*DEFAULT_CURL_ARGS, url, **DEFAULT_CURL_OPTIONS)
            return unless status.success?

            content = stdout.scrub
          end
          return if content.blank?

          json = Homebrew::Livecheck::Strategy::Json.parse_json(content)
          return unless (releases = json["releases"])

          current_str = current.to_s
          current_is_prerelease = current_str.match?(PYPI_UNSTABLE_VERSION_REGEX)
          cooldown_interval = (DateTime.now - MIN_RELEASE_AGE_DAYS)
          releases.sort_by { |k, _| Version.new(k) }.reverse_each do |version_str, assets|
            version = Version.new(version_str)
            return version if version_str == current_str
            next if (version > latest) || (version < current)
            next if !current_is_prerelease && version_str.match?(PYPI_UNSTABLE_VERSION_REGEX)

            assets.each do |asset|
              next if asset["yanked"]
              next unless asset["url"]&.end_with?(suffix)
              next unless (date_str = asset["upload_time_iso_8601"])

              date = DateTime.parse(date_str)
              return version if date < cooldown_interval
            end
          end
        end
      end
    end
  end
end
