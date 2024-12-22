# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "deprecate_disable"
require "formula_versions"
require "formula_name_cask_token_auditor"
require "resource_auditor"
require "utils/shared_audits"

module Homebrew
  # Auditor for checking common violations in {Formula}e.
  class FormulaAuditor
    include FormulaCellarChecks
    include Utils::Curl

    attr_reader :formula, :text, :problems, :new_formula_problems

    def initialize(formula, options = {})
      @formula = formula
      @versioned_formula = formula.versioned_formula?
      @new_formula_inclusive = options[:new_formula]
      @new_formula = options[:new_formula] && !@versioned_formula
      @strict = options[:strict]
      @online = options[:online]
      @git = options[:git]
      @display_cop_names = options[:display_cop_names]
      @only = options[:only]
      @except = options[:except]
      # Accept precomputed style offense results, for efficiency
      @style_offenses = options[:style_offenses]
      # Allow the formula tap to be set as homebrew/core, for testing purposes
      @core_tap = formula.tap&.core_tap? || options[:core_tap]
      @problems = []
      @new_formula_problems = []
      @text = formula.path.open("rb", &:read)
      @specs = %w[stable head].filter_map { |s| formula.send(s) }
      @spdx_license_data = options[:spdx_license_data]
      @spdx_exception_data = options[:spdx_exception_data]
      @tap_audit = options[:tap_audit]
      @previous_committed = {}
      @newest_committed = {}
    end

    def audit_style
      return unless @style_offenses

      @style_offenses.each do |offense|
        cop_name = "#{offense.cop_name}: " if @display_cop_names
        message = "#{cop_name}#{offense.message}"

        problem message, location: offense.location, corrected: offense.corrected?
      end
    end

    def audit_file
      if formula.core_formula? && @versioned_formula
        unversioned_name = formula.name.gsub(/@.*$/, "")

        # ignore when an unversioned formula doesn't exist after an explicit rename
        return if formula.tap.formula_renames.key?(unversioned_name)

        # build this ourselves as we want e.g. homebrew/core to be present
        full_name = "#{formula.tap}/#{unversioned_name}"

        unversioned_formula = begin
          Formulary.factory(full_name).path
        rescue FormulaUnavailableError, TapFormulaAmbiguityError
          Pathname.new formula.path.to_s.gsub(/@.*\.rb$/, ".rb")
        end
        unless unversioned_formula.exist?
          unversioned_name = unversioned_formula.basename(".rb")
          problem "#{formula} is versioned but no #{unversioned_name} formula exists"
        end
      elsif formula.stable? &&
            !@versioned_formula &&
            (versioned_formulae = formula.versioned_formulae - [formula]) &&
            versioned_formulae.present?
        versioned_aliases, unversioned_aliases = formula.aliases.partition { |a| /.@\d/.match?(a) }
        _, last_alias_version = versioned_formulae.map(&:name).last.split("@")

        alias_name_major = "#{formula.name}@#{formula.version.major}"
        alias_name_major_minor = "#{formula.name}@#{formula.version.major_minor}"
        alias_name = if last_alias_version.split(".").length == 1
          alias_name_major
        else
          alias_name_major_minor
        end
        valid_main_alias_names = [alias_name_major, alias_name_major_minor].uniq

        # Also accept versioned aliases with names of other aliases, but do not require them.
        valid_other_alias_names = unversioned_aliases.flat_map do |name|
          %W[
            #{name}@#{formula.version.major}
            #{name}@#{formula.version.major_minor}
          ].uniq
        end

        unless @core_tap
          [versioned_aliases, valid_main_alias_names, valid_other_alias_names].each do |array|
            array.map! { |a| "#{formula.tap}/#{a}" }
          end
        end

        valid_versioned_aliases = versioned_aliases & valid_main_alias_names
        invalid_versioned_aliases = versioned_aliases - valid_main_alias_names - valid_other_alias_names

        latest_versioned_formula = versioned_formulae.map(&:name).first

        if valid_versioned_aliases.empty? && alias_name != latest_versioned_formula
          if formula.tap
            problem <<~EOS
              Formula has other versions so create a versioned alias:
                cd #{formula.tap.alias_dir}
                ln -s #{formula.path.to_s.gsub(formula.tap.path, "..")} #{alias_name}
            EOS
          else
            problem "Formula has other versions so create an alias named #{alias_name}."
          end
        end

        if invalid_versioned_aliases.present?
          problem <<~EOS
            Formula has invalid versioned aliases:
              #{invalid_versioned_aliases.join("\n  ")}
          EOS
        end
      end

      return if !formula.core_formula? || formula.path == formula.tap.new_formula_path(formula.name)

      problem <<~EOS
        Formula is in wrong path:
          Expected: #{formula.tap.new_formula_path(formula.name)}
            Actual: #{formula.path}
      EOS
    end

    def self.aliases
      # core aliases + tap alias names + tap alias full name
      @aliases ||= Formula.aliases + Formula.tap_aliases
    end

    def audit_synced_versions_formulae
      return unless formula.synced_with_other_formulae?

      name = formula.name
      version = formula.version

      formula.tap.synced_versions_formulae.each do |synced_version_formulae|
        next unless synced_version_formulae.include?(name)

        synced_version_formulae.each do |synced_formula|
          next if synced_formula == name

          if (synced_version = Formulary.factory(synced_formula).version) != version
            problem "Version of `#{synced_formula}` (#{synced_version}) should match version of `#{name}` (#{version})"
          end
        end

        break
      end
    end

    def audit_name
      name = formula.name

      name_auditor = Homebrew::FormulaNameCaskTokenAuditor.new(name)
      if (errors = name_auditor.errors).any?
        problem "Formula name '#{name}' must not contain #{errors.to_sentence(two_words_connector: " or ",
                                                                              last_word_connector: " or ")}."
      end

      return unless @strict
      return unless @core_tap

      problem "'#{name}' is not allowed in homebrew/core." if MissingFormula.disallowed_reason(name)

      if Formula.aliases.include? name
        problem "Formula name conflicts with existing aliases in homebrew/core."
        return
      end

      if (oldname = CoreTap.instance.formula_renames[name])
        problem "'#{name}' is reserved as the old name of #{oldname} in homebrew/core."
        return
      end

      return if formula.core_formula?
      return unless Formula.core_names.include?(name)

      problem "Formula name conflicts with existing core formula."
    end

    PERMITTED_LICENSE_MISMATCHES = {
      "AGPL-3.0" => ["AGPL-3.0-only", "AGPL-3.0-or-later"],
      "GPL-2.0"  => ["GPL-2.0-only",  "GPL-2.0-or-later"],
      "GPL-3.0"  => ["GPL-3.0-only",  "GPL-3.0-or-later"],
      "LGPL-2.1" => ["LGPL-2.1-only", "LGPL-2.1-or-later"],
      "LGPL-3.0" => ["LGPL-3.0-only", "LGPL-3.0-or-later"],
    }.freeze

    # The following licenses are non-free/open based on multiple sources (e.g. Debian, Fedora, FSF, OSI, ...)
    INCOMPATIBLE_LICENSES = [
      "Aladdin",    # https://www.gnu.org/licenses/license-list.html#Aladdin
      "CPOL-1.02",  # https://www.gnu.org/licenses/license-list.html#cpol
      "gSOAP-1.3b", # https://salsa.debian.org/ellert/gsoap/-/blob/master/debian/copyright
      "JSON",       # https://wiki.debian.org/DFSGLicenses#JSON_evil_license
      "MS-LPL",     # https://github.com/spdx/license-list-XML/issues/1432#issuecomment-1077680709
      "OPL-1.0",    # https://wiki.debian.org/DFSGLicenses#Open_Publication_License_.28OPL.29_v1.0
    ].freeze
    INCOMPATIBLE_LICENSE_PREFIXES = [
      "BUSL",     # https://spdx.org/licenses/BUSL-1.1.html#notes
      "CC-BY-NC", # https://people.debian.org/~bap/dfsg-faq.html#no_commercial
      "Elastic",  # https://www.elastic.co/licensing/elastic-license#Limitations
      "SSPL",     # https://fedoraproject.org/wiki/Licensing/SSPL#License_Notes
    ].freeze

    def audit_license
      if formula.license.present?
        licenses, exceptions = SPDX.parse_license_expression formula.license

        incompatible_licenses = licenses.select do |license|
          license.to_s.start_with?(*INCOMPATIBLE_LICENSE_PREFIXES) || INCOMPATIBLE_LICENSES.include?(license.to_s)
        end
        if incompatible_licenses.present? && @core_tap
          problem <<~EOS
            Formula #{formula.name} contains incompatible licenses: #{incompatible_licenses}.
            Formulae in homebrew/core must either use a Debian Free Software Guidelines license
            or be released into the public domain. See #{Formatter.url("https://docs.brew.sh/License-Guidelines")}
          EOS
        end

        non_standard_licenses = licenses.reject { |license| SPDX.valid_license? license }
        if non_standard_licenses.present?
          problem <<~EOS
            Formula #{formula.name} contains non-standard SPDX licenses: #{non_standard_licenses}.
            For a list of valid licenses check: #{Formatter.url("https://spdx.org/licenses/")}
          EOS
        end

        if @strict || @core_tap
          deprecated_licenses = licenses.select do |license|
            SPDX.deprecated_license? license
          end
          if deprecated_licenses.present?
            problem <<~EOS
              Formula #{formula.name} contains deprecated SPDX licenses: #{deprecated_licenses}.
              You may need to add `-only` or `-or-later` for GNU licenses (e.g. `GPL`, `LGPL`, `AGPL`, `GFDL`).
              For a list of valid licenses check: #{Formatter.url("https://spdx.org/licenses/")}
            EOS
          end
        end

        invalid_exceptions = exceptions.reject { |exception| SPDX.valid_license_exception? exception }
        if invalid_exceptions.present?
          problem <<~EOS
            Formula #{formula.name} contains invalid or deprecated SPDX license exceptions: #{invalid_exceptions}.
            For a list of valid license exceptions check:
              #{Formatter.url("https://spdx.org/licenses/exceptions-index.html")}
          EOS
        end

        return unless @online

        user, repo = get_repo_data(%r{https?://github\.com/([^/]+)/([^/]+)/?.*})
        return if user.blank?

        tag = SharedAudits.github_tag_from_url(formula.stable.url)
        tag ||= formula.stable.specs[:tag]
        github_license = GitHub.get_repo_license(user, repo, ref: tag)
        return unless github_license
        return if (licenses + ["NOASSERTION"]).include?(github_license)
        return if PERMITTED_LICENSE_MISMATCHES[github_license]&.any? { |license| licenses.include? license }
        return if formula.tap&.audit_exception :permitted_formula_license_mismatches, formula.name

        problem "Formula license #{licenses} does not match GitHub license #{Array(github_license)}."

      elsif @core_tap && !formula.disabled?
        problem "Formulae in homebrew/core must specify a license."
      end
    end

    def audit_deps
      @specs.each do |spec|
        # Check for things we don't like to depend on.
        # We allow non-Homebrew installs whenever possible.
        spec.declared_deps.each do |dep|
          begin
            dep_f = dep.to_formula
          rescue TapFormulaUnavailableError
            # Don't complain about missing cross-tap dependencies
            next
          rescue FormulaUnavailableError
            problem "Can't find dependency '#{dep.name}'."
            next
          rescue TapFormulaAmbiguityError
            problem "Ambiguous dependency '#{dep.name}'."
            next
          end

          if dep_f.oldnames.include?(dep.name.split("/").last)
            problem "Dependency '#{dep.name}' was renamed; use new name '#{dep_f.name}'."
          end

          if @core_tap &&
             @new_formula &&
             !dep.uses_from_macos? &&
             dep_f.keg_only? &&
             dep_f.keg_only_reason.provided_by_macos? &&
             dep_f.keg_only_reason.applicable? &&
             formula.requirements.none?(LinuxRequirement) &&
             !formula.tap&.audit_exception(:provided_by_macos_depends_on_allowlist, dep.name)
            new_formula_problem(
              "Dependency '#{dep.name}' is provided by macOS; " \
              "please replace 'depends_on' with 'uses_from_macos'.",
            )
          end

          dep.options.each do |opt|
            next if @core_tap
            next if dep_f.option_defined?(opt)
            next if dep_f.requirements.find do |r|
              if r.recommended?
                opt.name == "with-#{r.name}"
              elsif r.optional?
                opt.name == "without-#{r.name}"
              end
            end

            problem "Dependency '#{dep}' does not define option #{opt.name.inspect}"
          end

          problem "Don't use 'git' as a dependency (it's always available)" if @new_formula && dep.name == "git"

          problem "Dependency '#{dep.name}' is marked as :run. Remove :run; it is a no-op." if dep.tags.include?(:run)

          next unless @core_tap

          if dep_f.tap.nil?
            problem <<~EOS
              Dependency '#{dep.name}' does not exist in any tap.
            EOS
          elsif !dep_f.tap.core_tap?
            problem <<~EOS
              Dependency '#{dep.name}' is not in homebrew/core. Formulae in homebrew/core
              should not have dependencies in external taps.
            EOS
          end

          if dep_f.deprecated? && !formula.deprecated? && !formula.disabled?
            problem <<~EOS
              Dependency '#{dep.name}' is deprecated but has un-deprecated dependents. Either
              un-deprecate '#{dep.name}' or deprecate it and all of its dependents.
            EOS
          end

          if dep_f.disabled? && !formula.disabled?
            problem <<~EOS
              Dependency '#{dep.name}' is disabled but has un-disabled dependents. Either
              un-disable '#{dep.name}' or disable it and all of its dependents.
            EOS
          end

          # we want to allow uses_from_macos for aliases but not bare dependencies.
          # we also allow `pkg-config` for backwards compatibility in external taps.
          if self.class.aliases.include?(dep.name) && !dep.uses_from_macos? && (dep.name != "pkg-config" || @core_tap)
            problem "Dependency '#{dep.name}' is an alias; use the canonical name '#{dep.to_formula.full_name}'."
          end

          if dep.tags.include?(:recommended) || dep.tags.include?(:optional)
            problem "Formulae in homebrew/core should not have optional or recommended dependencies"
          end
        end

        next unless @core_tap

        if spec.requirements.map(&:recommended?).any? || spec.requirements.map(&:optional?).any?
          problem "Formulae in homebrew/core should not have optional or recommended requirements"
        end
      end

      return unless @core_tap
      return if formula.tap&.audit_exception :versioned_dependencies_conflicts_allowlist, formula.name

      # The number of conflicts on Linux is absurd.
      # TODO: remove this and check these there too.
      return if Homebrew::SimulateSystem.simulating_or_running_on_linux?

      # Skip the versioned dependencies conflict audit for *-staging branches.
      # This will allow us to migrate dependents of formulae like Python or OpenSSL
      # gradually over separate PRs which target a *-staging branch. See:
      #   https://github.com/Homebrew/homebrew-core/pull/134260
      ignore_formula_conflict, staging_formula =
        if @tap_audit && (github_event_path = ENV.fetch("GITHUB_EVENT_PATH", nil)).present?
          event_payload = JSON.parse(File.read(github_event_path))
          base_info = event_payload.dig("pull_request", "base").to_h # handle `nil`

          # We need to read the head ref from `GITHUB_EVENT_PATH` because
          # `git branch --show-current` returns `master` on PR branches.
          staging_branch = base_info["ref"]&.end_with?("-staging")
          homebrew_owned_repo = base_info.dig("repo", "owner", "login") == "Homebrew"
          homebrew_core_pr = base_info.dig("repo", "name") == "homebrew-core"
          # Support staging branches named `formula-staging` or `formula@version-staging`.
          base_formula = base_info["ref"]&.split(/-|@/, 2)&.first

          [staging_branch && homebrew_owned_repo && homebrew_core_pr, base_formula]
        end

      recursive_runtime_formulae = formula.runtime_formula_dependencies(undeclared: false)
      version_hash = {}
      version_conflicts = Set.new
      recursive_runtime_formulae.each do |f|
        name = f.name
        unversioned_name, = name.split("@")
        next if ignore_formula_conflict && unversioned_name == staging_formula
        # Allow use of the full versioned name (e.g. `python@3.99`) or an unversioned alias (`python`).
        next if formula.tap&.audit_exception :versioned_formula_dependent_conflicts_allowlist, name
        next if formula.tap&.audit_exception :versioned_formula_dependent_conflicts_allowlist, unversioned_name

        version_hash[unversioned_name] ||= Set.new
        version_hash[unversioned_name] << name
        next if version_hash[unversioned_name].length < 2

        version_conflicts += version_hash[unversioned_name]
      end

      return if version_conflicts.empty?

      return if formula.disabled?

      return if formula.deprecated? &&
                formula.deprecation_reason != DeprecateDisable::FORMULA_DEPRECATE_DISABLE_REASONS[:versioned_formula]

      problem <<~EOS
        #{formula.full_name} contains conflicting version recursive dependencies:
          #{version_conflicts.to_a.join ", "}
        View these with `brew deps --tree #{formula.full_name}`.
      EOS
    end

    def audit_conflicts
      tap = formula.tap
      formula.conflicts.each do |conflict|
        conflicting_formula = Formulary.factory(conflict.name)
        next if tap != conflicting_formula.tap

        problem "Formula should not conflict with itself" if formula == conflicting_formula

        if T.must(tap).formula_renames.key?(conflict.name) || T.must(tap).aliases.include?(conflict.name)
          problem "Formula conflict should be declared using " \
                  "canonical name (#{conflicting_formula.name}) instead of #{conflict.name}"
        end

        reverse_conflict_found = T.let(false, T::Boolean)
        conflicting_formula.conflicts.each do |reverse_conflict|
          reverse_conflict_formula = Formulary.factory(reverse_conflict.name)
          if T.must(tap).formula_renames.key?(reverse_conflict.name) ||
             T.must(tap).aliases.include?(reverse_conflict.name)
            problem "Formula #{conflicting_formula.name} conflict should be declared using " \
                    "canonical name (#{reverse_conflict_formula.name}) instead of #{reverse_conflict.name}"
          end

          reverse_conflict_found ||= reverse_conflict_formula == formula
        end
        unless reverse_conflict_found
          problem "Formula #{conflicting_formula.name} should also have a conflict declared with #{formula.name}"
        end
      rescue TapFormulaUnavailableError
        # Don't complain about missing cross-tap conflicts.
        next
      rescue FormulaUnavailableError
        problem "Can't find conflicting formula #{conflict.name.inspect}."
      rescue TapFormulaAmbiguityError
        problem "Ambiguous conflicting formula #{conflict.name.inspect}."
      end
    end

    def audit_gcc_dependency
      return unless @core_tap
      return unless Homebrew::SimulateSystem.simulating_or_running_on_linux?
      return unless linux_only_gcc_dep?(formula)
      # https://github.com/Homebrew/homebrew-core/pull/171634
      # https://github.com/nghttp2/nghttp2/issues/2194
      return if formula.tap&.audit_exception(:linux_only_gcc_dependency_allowlist, formula.name)

      problem "Formulae in homebrew/core should not have a Linux-only dependency on GCC."
    end

    def audit_postgresql
      return if formula.name != "postgresql"
      return unless @core_tap

      major_version = formula.version.major.to_i
      previous_major_version = major_version - 1
      previous_formula_name = "postgresql@#{previous_major_version}"
      begin
        Formula[previous_formula_name]
      rescue FormulaUnavailableError
        problem "Versioned #{previous_formula_name} in homebrew/core must be created for " \
                "`brew postgresql-upgrade-database` and `pg_upgrade` to work."
      end
    end

    def audit_glibc
      return unless @core_tap
      return if formula.name != "glibc"
      # Also allow LINUX_GLIBC_NEXT_CI_VERSION for when we're upgrading.
      return if [OS::LINUX_GLIBC_CI_VERSION, OS::LINUX_GLIBC_NEXT_CI_VERSION].include?(formula.version.to_s)

      problem "The glibc version must be #{OS::LINUX_GLIBC_CI_VERSION}, as needed by our CI on Linux. " \
              "The glibc formula is for users who have a system glibc with a lower version, " \
              "which allows them to use our Linux bottles, which were compiled against system glibc on CI."
    end

    RELICENSED_FORMULAE_VERSIONS = {
      "boundary"           => "0.14",
      "consul"             => "1.17",
      "elasticsearch"      => "7.11",
      "kibana"             => "7.11",
      "nomad"              => "1.7",
      "packer"             => "1.10",
      "redis"              => "7.4",
      "terraform"          => "1.6",
      "vagrant"            => "2.4",
      "vagrant-completion" => "2.4",
      "vault"              => "1.15",
      "waypoint"           => "0.12",
    }.freeze

    def audit_relicensed_formulae
      return unless RELICENSED_FORMULAE_VERSIONS.key? formula.name
      return unless @core_tap

      relicensed_version = Version.new(RELICENSED_FORMULAE_VERSIONS[formula.name])
      return if formula.version < relicensed_version

      problem "#{formula.name} was relicensed to a non-open-source license from version #{relicensed_version}. " \
              "It must not be upgraded to version #{relicensed_version} or newer."
    end

    def audit_versioned_keg_only
      return unless @versioned_formula
      return unless @core_tap

      if formula.keg_only?
        return if formula.keg_only_reason.versioned_formula?
        return if formula.name.start_with?("openssl", "libressl") && formula.keg_only_reason.by_macos?
      end

      return if formula.tap&.audit_exception :versioned_keg_only_allowlist, formula.name

      problem "Versioned formulae in homebrew/core should use `keg_only :versioned_formula`"
    end

    def audit_homepage
      homepage = formula.homepage

      return if homepage.blank?

      return unless @online

      return if formula.tap&.audit_exception :cert_error_allowlist, formula.name, homepage

      return unless DevelopmentTools.curl_handles_most_https_certificates?

      use_homebrew_curl = [:stable, :head].any? do |spec_name|
        next false unless (spec = formula.send(spec_name))

        spec.using == :homebrew_curl
      end

      if (http_content_problem = curl_check_http_content(
        homepage,
        SharedAudits::URL_TYPE_HOMEPAGE,
        user_agents:       [:browser, :default],
        check_content:     true,
        strict:            @strict,
        use_homebrew_curl:,
      ))
        problem http_content_problem
      end
    end

    def audit_bottle_spec
      # special case: new versioned formulae should be audited
      return unless @new_formula_inclusive
      return unless @core_tap

      return unless formula.bottle_defined?

      new_formula_problem "New formulae in homebrew/core should not have a `bottle do` block"
    end

    def audit_eol
      return unless @online
      return unless @core_tap

      return if formula.deprecated? || formula.disabled?

      name = if formula.versioned_formula?
        formula.name.split("@").first
      else
        formula.name
      end

      return if formula.tap&.audit_exception :eol_date_blocklist, name

      metadata = SharedAudits.eol_data(name, formula.version.major.to_s)
      metadata ||= SharedAudits.eol_data(name, formula.version.major_minor.to_s)

      return if metadata.blank? || (eol = metadata["eol"]).blank?

      is_eol = eol == true
      is_eol ||= eol.is_a?(String) && (eol_date = Date.parse(eol)) <= Date.today
      return unless is_eol

      message = "Product is EOL"
      message += " since #{eol_date}" if eol_date.present?
      message += ", see #{Formatter.url("https://endoflife.date/#{name}")}"

      problem message
    end

    def audit_wayback_url
      return unless @core_tap
      return if formula.deprecated? || formula.disabled?

      regex = %r{^https?://web\.archive\.org}
      problem_prefix = "Formula with a Internet Archive Wayback Machine"

      problem "#{problem_prefix} `url` should be deprecated with `:repo_removed`" if regex.match?(formula.stable.url)

      if regex.match?(formula.homepage)
        problem "#{problem_prefix} `homepage` should find an alternative `homepage` or be deprecated."
      end

      return unless formula.head

      return unless regex.match?(formula.head.url)

      problem "Remove Internet Archive Wayback Machine `head` URL"
    end

    def audit_github_repository_archived
      return if formula.deprecated? || formula.disabled?

      user, repo = get_repo_data(%r{https?://github\.com/([^/]+)/([^/]+)/?.*}) if @online
      return if user.blank?

      metadata = SharedAudits.github_repo_data(user, repo)
      return if metadata.nil?

      problem "GitHub repo is archived" if metadata["archived"]
    end

    def audit_gitlab_repository_archived
      return if formula.deprecated? || formula.disabled?

      user, repo = get_repo_data(%r{https?://gitlab\.com/([^/]+)/([^/]+)/?.*}) if @online
      return if user.blank?

      metadata = SharedAudits.gitlab_repo_data(user, repo)
      return if metadata.nil?

      problem "GitLab repo is archived" if metadata["archived"]
    end

    def audit_github_repository
      user, repo = get_repo_data(%r{https?://github\.com/([^/]+)/([^/]+)/?.*}) if @new_formula

      return if user.blank?

      warning = SharedAudits.github(user, repo)
      return if warning.nil?

      new_formula_problem warning
    end

    def audit_gitlab_repository
      user, repo = get_repo_data(%r{https?://gitlab\.com/([^/]+)/([^/]+)/?.*}) if @new_formula
      return if user.blank?

      warning = SharedAudits.gitlab(user, repo)
      return if warning.nil?

      new_formula_problem warning
    end

    def audit_bitbucket_repository
      user, repo = get_repo_data(%r{https?://bitbucket\.org/([^/]+)/([^/]+)/?.*}) if @new_formula
      return if user.blank?

      warning = SharedAudits.bitbucket(user, repo)
      return if warning.nil?

      new_formula_problem warning
    end

    def get_repo_data(regex)
      return unless @core_tap
      return unless @online

      _, user, repo = *regex.match(formula.stable.url) if formula.stable
      _, user, repo = *regex.match(formula.homepage) unless user
      _, user, repo = *regex.match(formula.head.url) if !user && formula.head
      return if !user || !repo

      repo.delete_suffix!(".git")

      [user, repo]
    end

    def audit_specs
      problem "Head-only (no stable download)" if head_only?(formula)

      %w[Stable HEAD].each do |name|
        spec_name = name.downcase.to_sym
        next unless (spec = formula.send(spec_name))

        except = @except.to_a
        if spec_name == :head &&
           formula.tap&.audit_exception(:head_non_default_branch_allowlist, formula.name, spec.specs[:branch])
          except << "head_branch"
        end

        ra = ResourceAuditor.new(
          spec, spec_name,
          online: @online, strict: @strict, only: @only, except:,
          use_homebrew_curl: spec.using == :homebrew_curl
        ).audit
        ra.problems.each do |message|
          problem "#{name}: #{message}"
        end

        spec.resources.each_value do |resource|
          problem "Resource name should be different from the formula name" if resource.name == formula.name

          ra = ResourceAuditor.new(
            resource, spec_name,
            online: @online, strict: @strict, only: @only, except: @except,
            use_homebrew_curl: resource.using == :homebrew_curl
          ).audit
          ra.problems.each do |message|
            problem "#{name} resource #{resource.name.inspect}: #{message}"
          end
        end

        next if spec.patches.empty?
        next if !@new_formula || !@core_tap

        new_formula_problem(
          "Formulae should not require patches to build. " \
          "Patches should be submitted and accepted upstream first.",
        )
      end

      return unless @core_tap

      if formula.head && @versioned_formula &&
         !formula.tap&.audit_exception(:versioned_head_spec_allowlist, formula.name)
        problem "Versioned formulae should not have a `HEAD` spec"
      end

      stable = formula.stable
      return unless stable
      return unless stable.url

      version = stable.version
      problem "Stable: version (#{version}) is set to a string without a digit" unless /\d/.match?(version.to_s)

      stable_version_string = version.to_s
      if stable_version_string.start_with?("HEAD")
        problem "Stable: non-HEAD version name (#{stable_version_string}) should not begin with HEAD"
      end

      stable_url_version = Version.parse(stable.url)
      stable_url_minor_version = stable_url_version.minor.to_i

      formula_suffix = stable.version.patch.to_i
      throttled_rate = formula.livecheck.throttle
      if throttled_rate && formula_suffix.modulo(throttled_rate).nonzero?
        problem "should only be updated every #{throttled_rate} releases on multiples of #{throttled_rate}"
      end

      case (url = stable.url)
      when /[\d._-](alpha|beta|rc\d)/
        matched = Regexp.last_match(1)
        version_prefix = stable_version_string.sub(/\d+$/, "")
        return if formula.tap&.audit_exception :unstable_allowlist, formula.name, version_prefix
        return if formula.tap&.audit_exception :unstable_devel_allowlist, formula.name, version_prefix

        problem "Stable version URLs should not contain #{matched}"
      when %r{download\.gnome\.org/sources}, %r{ftp\.gnome\.org/pub/GNOME/sources}i
        version_prefix = stable.version.major_minor
        return if formula.tap&.audit_exception :gnome_devel_allowlist, formula.name, version_prefix
        return if stable_url_version < Version.new("1.0")
        # All minor versions are stable in the new GNOME version scheme (which starts at version 40.0)
        # https://discourse.gnome.org/t/new-gnome-versioning-scheme/4235
        return if stable_url_version >= Version.new("40.0")
        return if stable_url_minor_version.even?

        problem "#{stable.version} is a development release"
      when %r{isc.org/isc/bind\d*/}i
        return if stable_url_minor_version.even?

        problem "#{stable.version} is a development release"

      when %r{https?://gitlab\.com/([\w-]+)/([\w-]+)}
        owner = T.must(Regexp.last_match(1))
        repo = T.must(Regexp.last_match(2))

        tag = SharedAudits.gitlab_tag_from_url(url)
        tag ||= stable.specs[:tag]
        tag ||= stable.version.to_s

        if @online
          error = SharedAudits.gitlab_release(owner, repo, tag, formula:)
          problem error if error
        end
      when %r{^https://github.com/([\w-]+)/([\w-]+)}
        owner = T.must(Regexp.last_match(1))
        repo = T.must(Regexp.last_match(2))
        tag = SharedAudits.github_tag_from_url(url)
        tag ||= formula.stable.specs[:tag]

        if @online && !tag.nil?
          error = SharedAudits.github_release(owner, repo, tag, formula:)
          problem error if error
        end
      end
    end

    def audit_stable_version
      return unless @git
      return unless formula.tap # skip formula not from core or any taps
      return unless formula.tap.git? # git log is required
      return if formula.stable.blank?

      current_version = formula.stable.version
      current_version_scheme = formula.version_scheme

      previous_committed, newest_committed = committed_version_info

      if !newest_committed[:version].nil? &&
         current_version < newest_committed[:version] &&
         current_version_scheme == previous_committed[:version_scheme]
        problem "stable version should not decrease (from #{newest_committed[:version]} to #{current_version})"
      end
    end

    def audit_revision
      new_formula_problem("New formulae should not define a revision.") if @new_formula && !formula.revision.zero?

      return unless @git
      return unless formula.tap # skip formula not from core or any taps
      return unless formula.tap.git? # git log is required
      return if formula.stable.blank?

      current_version = formula.stable.version
      current_revision = formula.revision

      previous_committed, newest_committed = committed_version_info

      if (previous_committed[:version] != newest_committed[:version] ||
         current_version != newest_committed[:version]) &&
         !current_revision.zero? &&
         current_revision == newest_committed[:revision] &&
         current_revision == previous_committed[:revision]
        problem "'revision #{current_revision}' should be removed"
      elsif current_version == previous_committed[:version] &&
            !previous_committed[:revision].nil? &&
            current_revision < previous_committed[:revision]
        problem "revision should not decrease (from #{previous_committed[:revision]} to #{current_revision})"
      elsif newest_committed[:revision] &&
            current_revision > (newest_committed[:revision] + 1)
        problem "revisions should only increment by 1"
      end
    end

    def audit_version_scheme
      return unless @git
      return unless formula.tap # skip formula not from core or any taps
      return unless formula.tap.git? # git log is required
      return if formula.stable.blank?

      current_version_scheme = formula.version_scheme

      previous_committed, = committed_version_info

      return if previous_committed[:version_scheme].nil?

      if current_version_scheme < previous_committed[:version_scheme]
        problem "version_scheme should not decrease (from #{previous_committed[:version_scheme]} " \
                "to #{current_version_scheme})"
      elsif current_version_scheme > (previous_committed[:version_scheme] + 1)
        problem "version_schemes should only increment by 1"
      end
    end

    def audit_unconfirmed_checksum_change
      return unless @git
      return unless formula.tap # skip formula not from core or any taps
      return unless formula.tap.git? # git log is required
      return if formula.stable.blank?

      current_version = formula.stable.version
      current_checksum = formula.stable.checksum
      current_url = formula.stable.url

      _, newest_committed = committed_version_info

      if current_version == newest_committed[:version] &&
         current_url == newest_committed[:url] &&
         current_checksum != newest_committed[:checksum] &&
         current_checksum.present? && newest_committed[:checksum].present?
        problem(
          "stable sha256 changed without the url/version also changing; " \
          "please create an issue upstream to rule out malicious " \
          "circumstances and to find out why the file changed.",
        )
      end
    end

    def audit_text
      bin_names = Set.new
      bin_names << formula.name
      bin_names += formula.aliases
      [formula.bin, formula.sbin].each do |dir|
        next unless dir.exist?

        bin_names += dir.children.map { |child| child.basename.to_s }
      end
      shell_commands = ["system", "shell_output", "pipe_output"]
      bin_names.each do |name|
        shell_commands.each do |cmd|
          if text.to_s.match?(/test do.*#{cmd}[(\s]+['"]#{Regexp.escape(name)}[\s'"]/m)
            problem %Q(fully scope test #{cmd} calls, e.g. #{cmd} "\#{bin}/#{name}")
          end
        end
      end
    end

    def audit_reverse_migration
      # Only enforce for new formula being re-added to core
      return unless @strict
      return unless @core_tap
      return unless formula.tap.tap_migrations.key?(formula.name)

      problem <<~EOS
        #{formula.name} seems to be listed in tap_migrations.json!
        Please remove #{formula.name} from present tap & tap_migrations.json
        before submitting it to Homebrew/homebrew-#{formula.tap.repository}.
      EOS
    end

    def audit_prefix_has_contents
      return unless formula.prefix.directory?
      return unless Keg.new(formula.prefix).empty_installation?

      problem <<~EOS
        The installation seems to be empty. Please ensure the prefix
        is set correctly and expected files are installed.
        The prefix configure/make argument may be case-sensitive.
      EOS
    end

    def audit_deprecate_disable
      error = SharedAudits.check_deprecate_disable_reason(formula)
      problem error if error
    end

    def quote_dep(dep)
      dep.is_a?(Symbol) ? dep.inspect : "'#{dep}'"
    end

    def problem_if_output(output)
      problem(output) if output
    end

    def audit
      only_audits = @only
      except_audits = @except

      methods.map(&:to_s).grep(/^audit_/).each do |audit_method_name|
        name = audit_method_name.delete_prefix("audit_")
        next if only_audits&.exclude?(name)
        next if except_audits&.include?(name)

        send(audit_method_name)
      end
    end

    private

    def problem(message, location: nil, corrected: false)
      @problems << ({ message:, location:, corrected: })
    end

    def new_formula_problem(message, location: nil, corrected: false)
      @new_formula_problems << ({ message:, location:, corrected: })
    end

    def head_only?(formula)
      formula.head && formula.stable.nil?
    end

    def linux_only_gcc_dep?(formula)
      odie "`#linux_only_gcc_dep?` works only on Linux!" if Homebrew::SimulateSystem.simulating_or_running_on_macos?
      return false if formula.deps.map(&:name).exclude?("gcc")

      variations = formula.to_hash_with_variations["variations"]
      # The formula has no variations, so all OS-version-arch triples depend on GCC.
      return false if variations.blank?

      MacOSVersion::SYMBOLS.keys.product(OnSystem::ARCH_OPTIONS).each do |os, arch|
        bottle_tag = Utils::Bottles::Tag.new(system: os, arch:)
        next unless bottle_tag.valid_combination?

        variation_dependencies = variations.dig(bottle_tag.to_sym, "dependencies")
        # This variation either:
        #   1. does not exist
        #   2. has no variation-specific dependencies
        # In either case, it matches Linux. We must check for `nil` because an empty
        # array indicates that this variation does not depend on GCC.
        return false if variation_dependencies.nil?
        # We found a non-Linux variation that depends on GCC.
        return false if variation_dependencies.include?("gcc")
      end

      true
    end

    def committed_version_info
      return [] unless @git
      return [] unless formula.tap # skip formula not from core or any taps
      return [] unless formula.tap.git? # git log is required
      return [] if formula.stable.blank?
      return [@previous_committed, @newest_committed] if @previous_committed.present? || @newest_committed.present?

      current_version = formula.stable.version
      current_revision = formula.revision

      fv = FormulaVersions.new(formula)
      fv.rev_list("origin/HEAD") do |revision, path|
        begin
          fv.formula_at_revision(revision, path) do |f|
            stable = f.stable
            next if stable.blank?

            @previous_committed[:version] = stable.version
            @previous_committed[:checksum] = stable.checksum
            @previous_committed[:version_scheme] = f.version_scheme
            @previous_committed[:revision] = f.revision

            @newest_committed[:version] ||= @previous_committed[:version]
            @newest_committed[:checksum] ||= @previous_committed[:checksum]
            @newest_committed[:revision] ||= @previous_committed[:revision]
            @newest_committed[:url] ||= stable.url
          end
        rescue MacOSVersion::Error
          break
        end

        break if @previous_committed[:version] && current_version != @previous_committed[:version]
        break if @previous_committed[:revision] && current_revision != @previous_committed[:revision]
      end

      @previous_committed.compact!
      @newest_committed.compact!

      [@previous_committed, @newest_committed]
    end
  end
end
