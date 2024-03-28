# typed: true
# frozen_string_literal: true

require "abstract_command"
require "fileutils"
require "formula"
require "cli/parser"
require "utils/pypi"
require "utils/tar"

module Homebrew
  module DevCmd
    class BumpFormulaPr < AbstractCommand
      cmd_args do
        description <<~EOS
          Create a pull request to update <formula> with a new URL or a new tag.

          If a <URL> is specified, the <SHA-256> checksum of the new download should also
          be specified. A best effort to determine the <SHA-256> will be made if not supplied
          by the user.

          If a <tag> is specified, the Git commit <revision> corresponding to that tag
          should also be specified. A best effort to determine the <revision> will be made
          if the value is not supplied by the user.

          If a <version> is specified, a best effort to determine the <URL> and <SHA-256> or
          the <tag> and <revision> will be made if both values are not supplied by the user.

          *Note:* this command cannot be used to transition a formula from a
          URL-and-SHA-256 style specification into a tag-and-revision style specification,
          nor vice versa. It must use whichever style specification the formula already uses.
        EOS
        switch "-n", "--dry-run",
               description: "Print what would be done rather than doing it."
        switch "--write-only",
               description: "Make the expected file modifications without taking any Git actions."
        switch "--commit",
               depends_on:  "--write-only",
               description: "When passed with `--write-only`, generate a new commit after writing changes " \
                            "to the formula file."
        switch "--no-audit",
               description: "Don't run `brew audit` before opening the PR."
        switch "--strict",
               description: "Run `brew audit --strict` before opening the PR."
        switch "--online",
               description: "Run `brew audit --online` before opening the PR."
        switch "--no-browse",
               description: "Print the pull request URL instead of opening in a browser."
        switch "--no-fork",
               description: "Don't try to fork the repository."
        comma_array "--mirror",
                    description: "Use the specified <URL> as a mirror URL. If <URL> is a comma-separated list " \
                                 "of URLs, multiple mirrors will be added."
        flag   "--fork-org=",
               description: "Use the specified GitHub organization for forking."
        flag   "--version=",
               description: "Use the specified <version> to override the value parsed from the URL or tag. Note " \
                            "that `--version=0` can be used to delete an existing version override from a " \
                            "formula if it has become redundant."
        flag   "--message=",
               description: "Prepend <message> to the default pull request message."
        flag   "--url=",
               description: "Specify the <URL> for the new download. If a <URL> is specified, the <SHA-256> " \
                            "checksum of the new download should also be specified."
        flag   "--sha256=",
               depends_on:  "--url=",
               description: "Specify the <SHA-256> checksum of the new download."
        flag   "--tag=",
               description: "Specify the new git commit <tag> for the formula."
        flag   "--revision=",
               description: "Specify the new commit <revision> corresponding to the specified git <tag> " \
                            "or specified <version>."
        switch "-f", "--force",
               description: "Remove all mirrors if `--mirror` was not specified."
        switch "--install-dependencies",
               description: "Install missing dependencies required to update resources."
        flag   "--python-package-name=",
               description: "Use the specified <package-name> when finding Python resources for <formula>. " \
                            "If no package name is specified, it will be inferred from the formula's stable URL."
        comma_array "--python-extra-packages=",
                    description: "Include these additional Python packages when finding resources."
        comma_array "--python-exclude-packages=",
                    description: "Exclude these Python packages when finding resources."

        conflicts "--dry-run", "--write-only"
        conflicts "--no-audit", "--strict"
        conflicts "--no-audit", "--online"
        conflicts "--url", "--tag"

        named_args :formula, max: 1, without_api: true
      end

      sig { override.void }
      def run
        if args.revision.present? && args.tag.nil? && args.version.nil?
          raise UsageError, "`--revision` must be passed with either `--tag` or `--version`!"
        end

        # As this command is simplifying user-run commands then let's just use a
        # user path, too.
        ENV["PATH"] = PATH.new(ORIGINAL_PATHS).to_s

        # Use the user's browser, too.
        ENV["BROWSER"] = Homebrew::EnvConfig.browser

        formula = args.named.to_formulae.first
        new_url = args.url
        raise FormulaUnspecifiedError if formula.blank?

        odie "This formula is disabled!" if formula.disabled?
        odie "This formula is deprecated and does not build!" if formula.deprecation_reason == :does_not_build
        odie "This formula is not in a tap!" if formula.tap.blank?
        odie "This formula's tap is not a Git repository!" unless formula.tap.git?

        odie <<~EOS unless formula.tap.allow_bump?(formula.name)
          Whoops, the #{formula.name} formula has its version update
          pull requests automatically opened by BrewTestBot!
          We'd still love your contributions, though, so try another one
          that's not in the autobump list:
            #{Formatter.url("#{formula.tap.remote}/blob/master/.github/autobump.txt")}
        EOS

        odie "You have too many PRs open: close or merge some first!" if GitHub.too_many_open_prs?(formula.tap)

        formula_spec = formula.stable
        odie "#{formula}: no stable specification found!" if formula_spec.blank?

        # This will be run by `brew audit` later so run it first to not start
        # spamming during normal output.
        Homebrew.install_bundler_gems!(groups: ["audit", "style"]) unless args.no_audit?

        tap_remote_repo = formula.tap.full_name || formula.tap.remote_repo
        remote = "origin"
        remote_branch = formula.tap.git_repo.origin_branch_name
        previous_branch = "-"

        check_open_pull_requests(formula, tap_remote_repo)

        new_version = args.version
        check_new_version(formula, tap_remote_repo, version: new_version) if new_version.present?

        opoo "This formula has patches that may be resolved upstream." if formula.patchlist.present?
        if formula.resources.any? { |resource| !resource.name.start_with?("homebrew-") }
          opoo "This formula has resources that may need to be updated."
        end

        old_mirrors = formula_spec.mirrors
        new_mirrors ||= args.mirror
        new_mirror ||= determine_mirror(new_url)
        new_mirrors ||= [new_mirror] if new_mirror.present?

        check_for_mirrors(formula, old_mirrors, new_mirrors) if new_url.present?

        old_hash = formula_spec.checksum&.hexdigest
        new_hash = args.sha256
        new_tag = args.tag
        new_revision = args.revision
        old_url = formula_spec.url
        old_tag = formula_spec.specs[:tag]
        old_formula_version = formula_version(formula)
        old_version = old_formula_version.to_s
        forced_version = new_version.present?
        new_url_hash = if new_url.present? && new_hash.present?
          check_new_version(formula, tap_remote_repo, url: new_url) if new_version.blank?
          true
        elsif new_tag.present? && new_revision.present?
          check_new_version(formula, tap_remote_repo, url: old_url, tag: new_tag) if new_version.blank?
          false
        elsif old_hash.blank?
          if new_tag.blank? && new_version.blank? && new_revision.blank?
            raise UsageError, "#{formula}: no `--tag` or `--version` argument specified!"
          end

          if old_tag.present?
            new_tag ||= old_tag.gsub(old_version, new_version)
            if new_tag == old_tag
              odie <<~EOS
                You need to bump this formula manually since the new tag
                and old tag are both #{new_tag}.
              EOS
            end
            check_new_version(formula, tap_remote_repo, url: old_url, tag: new_tag) if new_version.blank?
            resource_path, forced_version = fetch_resource_and_forced_version(formula, new_version, old_url,
                                                                              tag: new_tag)
            new_revision = Utils.popen_read("git", "-C", resource_path.to_s, "rev-parse", "-q", "--verify", "HEAD")
            new_revision = new_revision.strip
          elsif new_revision.blank?
            odie "#{formula}: the current URL requires specifying a `--revision=` argument."
          end
          false
        elsif new_url.blank? && new_version.blank?
          raise UsageError, "#{formula}: no `--url` or `--version` argument specified!"
        else
          new_url ||= PyPI.update_pypi_url(old_url, T.must(new_version))
          if new_url.blank?
            new_url = update_url(old_url, old_version, T.must(new_version))
            if new_mirrors.blank? && old_mirrors.present?
              new_mirrors = old_mirrors.map do |old_mirror|
                update_url(old_mirror, old_version, T.must(new_version))
              end
            end
          end
          if new_url == old_url
            odie <<~EOS
              You need to bump this formula manually since the new URL
              and old URL are both:
                #{new_url}
            EOS
          end
          check_new_version(formula, tap_remote_repo, url: new_url) if new_version.blank?
          resource_path, forced_version = fetch_resource_and_forced_version(formula, new_version, new_url)
          Utils::Tar.validate_file(resource_path)
          new_hash = resource_path.sha256
        end

        replacement_pairs = []
        if formula.revision.nonzero?
          replacement_pairs << [
            /^  revision \d+\n(\n(  head "))?/m,
            "\\2",
          ]
        end

        replacement_pairs += formula_spec.mirrors.map do |mirror|
          [
            / +mirror "#{Regexp.escape(mirror)}"\n/m,
            "",
          ]
        end

        replacement_pairs += if new_url_hash.present?
          [
            [
              /#{Regexp.escape(formula_spec.url)}/,
              new_url,
            ],
            [
              old_hash,
              new_hash,
            ],
          ]
        elsif new_tag.present?
          [
            [
              /tag:(\s+")#{formula_spec.specs[:tag]}(?=")/,
              "tag:\\1#{new_tag}\\2",
            ],
            [
              formula_spec.specs[:revision],
              new_revision,
            ],
          ]
        elsif new_url.present?
          [
            [
              /#{Regexp.escape(formula_spec.url)}/,
              new_url,
            ],
            [
              formula_spec.specs[:revision],
              new_revision,
            ],
          ]
        else
          [
            [
              formula_spec.specs[:revision],
              new_revision,
            ],
          ]
        end

        old_contents = formula.path.read

        if new_mirrors.present?
          replacement_pairs << [
            /^( +)(url "#{Regexp.escape(T.must(new_url))}"[^\n]*?\n)/m,
            "\\1\\2\\1mirror \"#{new_mirrors.join("\"\n\\1mirror \"")}\"\n",
          ]
        end

        if forced_version && new_version != "0"
          replacement_pairs << if old_contents.include?("version \"#{old_formula_version}\"")
            [
              "version \"#{old_formula_version}\"",
              "version \"#{new_version}\"",
            ]
          elsif new_mirrors.present?
            [
              /^( +)(mirror "#{Regexp.escape(new_mirrors.last)}"\n)/m,
              "\\1\\2\\1version \"#{new_version}\"\n",
            ]
          elsif new_url.present?
            [
              /^( +)(url "#{Regexp.escape(new_url)}"[^\n]*?\n)/m,
              "\\1\\2\\1version \"#{new_version}\"\n",
            ]
          elsif new_revision.present?
            [
              /^( {2})( +)(:revision => "#{new_revision}"\n)/m,
              "\\1\\2\\3\\1version \"#{new_version}\"\n",
            ]
          end
        elsif forced_version && new_version == "0"
          replacement_pairs << [
            /^  version "[\w.\-+]+"\n/m,
            "",
          ]
        end
        new_contents = Utils::Inreplace.inreplace_pairs(formula.path,
                                                        replacement_pairs.uniq.compact,
                                                        read_only_run: args.dry_run?,
                                                        silent:        args.quiet?)

        new_formula_version = formula_version(formula, new_contents)

        if new_formula_version < old_formula_version
          formula.path.atomic_write(old_contents) unless args.dry_run?
          odie <<~EOS
            You need to bump this formula manually since changing the version
            from #{old_formula_version} to #{new_formula_version} would be a downgrade.
          EOS
        elsif new_formula_version == old_formula_version
          formula.path.atomic_write(old_contents) unless args.dry_run?
          odie <<~EOS
            You need to bump this formula manually since the new version
            and old version are both #{new_formula_version}.
          EOS
        end

        alias_rename = alias_update_pair(formula, new_formula_version)
        if alias_rename.present?
          ohai "Renaming alias #{alias_rename.first} to #{alias_rename.last}"
          alias_rename.map! { |a| formula.tap.alias_dir/a }
        end

        unless args.dry_run?
          resources_checked = PyPI.update_python_resources! formula,
                                                            version:                  new_formula_version.to_s,
                                                            package_name:             args.python_package_name,
                                                            extra_packages:           args.python_extra_packages,
                                                            exclude_packages:         args.python_exclude_packages,
                                                            install_dependencies:     args.install_dependencies?,
                                                            silent:                   args.quiet?,
                                                            ignore_non_pypi_packages: true
        end

        run_audit(formula, alias_rename, old_contents)

        pr_message = "Created with `brew bump-formula-pr`."
        if resources_checked.nil? && formula.resources.any? { |resource| !resource.name.start_with?("homebrew-") }
          pr_message += <<~EOS


            - [ ] `resource` blocks have been checked for updates.
          EOS
        end

        if new_url =~ %r{^https://github\.com/([\w-]+)/([\w-]+)/archive/refs/tags/(v?[.0-9]+)\.tar\.}
          owner = Regexp.last_match(1)
          repo = Regexp.last_match(2)
          tag = Regexp.last_match(3)
          github_release_data = begin
            GitHub::API.open_rest("#{GitHub::API_URL}/repos/#{owner}/#{repo}/releases/tags/#{tag}")
          rescue GitHub::API::HTTPNotFoundError
            # If this is a 404: we can't do anything.
            nil
          end

          if github_release_data.present?
            pre = "pre" if github_release_data["prerelease"].present?
            pr_message += <<~XML
              <details>
                <summary>#{pre}release notes</summary>
                <pre>#{github_release_data["body"]}</pre>
              </details>
            XML
          end
        end

        pr_info = {
          sourcefile_path:  formula.path,
          old_contents:,
          additional_files: alias_rename,
          remote:,
          remote_branch:,
          branch_name:      "bump-#{formula.name}-#{new_formula_version}",
          commit_message:   "#{formula.name} #{new_formula_version}",
          previous_branch:,
          tap:              formula.tap,
          tap_remote_repo:,
          pr_message:,
        }
        GitHub.create_bump_pr(pr_info, args:)
      end

      private

      def determine_mirror(url)
        case url
        when %r{.*ftp\.gnu\.org/gnu.*}
          url.sub "ftp.gnu.org/gnu", "ftpmirror.gnu.org"
        when %r{.*download\.savannah\.gnu\.org/*}
          url.sub "download.savannah.gnu.org", "download-mirror.savannah.gnu.org"
        when %r{.*www\.apache\.org/dyn/closer\.lua\?path=.*}
          url.sub "www.apache.org/dyn/closer.lua?path=", "archive.apache.org/dist/"
        when %r{.*mirrors\.ocf\.berkeley\.edu/debian.*}
          url.sub "mirrors.ocf.berkeley.edu/debian", "mirrorservice.org/sites/ftp.debian.org/debian"
        end
      end

      def check_for_mirrors(formula, old_mirrors, new_mirrors)
        return if new_mirrors.present? || old_mirrors.empty?

        if args.force?
          opoo "#{formula}: Removing all mirrors because a `--mirror=` argument was not specified."
        else
          odie <<~EOS
            #{formula}: a `--mirror=` argument for updating the mirror URL(s) was not specified.
            Use `--force` to remove all mirrors.
          EOS
        end
      end

      sig { params(old_url: String, old_version: String, new_version: String).returns(String) }
      def update_url(old_url, old_version, new_version)
        new_url = old_url.gsub(old_version, new_version)
        return new_url if (old_version_parts = old_version.split(".")).length < 2
        return new_url if (new_version_parts = new_version.split(".")).length != old_version_parts.length

        partial_old_version = T.must(old_version_parts[0..-2]).join(".")
        partial_new_version = T.must(new_version_parts[0..-2]).join(".")
        new_url.gsub(%r{/(v?)#{Regexp.escape(partial_old_version)}/}, "/\\1#{partial_new_version}/")
      end

      def fetch_resource_and_forced_version(formula, new_version, url, **specs)
        resource = Resource.new
        resource.url(url, **specs)
        resource.owner = Resource.new(formula.name)
        forced_version = new_version && new_version != resource.version.to_s
        resource.version(new_version) if forced_version
        odie "Couldn't identify version, specify it using `--version=`." if resource.version.blank?
        [resource.fetch, forced_version]
      end

      def formula_version(formula, contents = nil)
        spec = :stable
        name = formula.name
        path = formula.path
        if contents.present?
          Formulary.from_contents(name, path, contents, spec).version
        else
          Formulary::FormulaLoader.new(name, path).get_formula(spec).version
        end
      end

      def check_open_pull_requests(formula, tap_remote_repo)
        GitHub.check_for_duplicate_pull_requests(formula.name, tap_remote_repo,
                                                 state: "open",
                                                 file:  formula.path.relative_path_from(formula.tap.path).to_s,
                                                 quiet: args.quiet?)
      end

      def check_new_version(formula, tap_remote_repo, version: nil, url: nil, tag: nil)
        if version.nil?
          specs = {}
          specs[:tag] = tag if tag.present?
          version = Version.detect(url, **specs).to_s
          return if version.blank?
        end

        check_throttle(formula, version)
        check_closed_pull_requests(formula, tap_remote_repo, version:)
      end

      def check_throttle(formula, new_version)
        throttled_rate = formula.livecheck.throttle
        throttled_rate ||= formula.tap.audit_exceptions.dig(:throttled_formulae, formula.name)
        return if throttled_rate.blank?

        formula_suffix = Version.new(new_version).patch.to_i
        return if formula_suffix.modulo(throttled_rate).zero?

        odie "#{formula} should only be updated every #{throttled_rate} releases on multiples of #{throttled_rate}"
      end

      def check_closed_pull_requests(formula, tap_remote_repo, version:)
        # if we haven't already found open requests, try for an exact match across closed requests
        GitHub.check_for_duplicate_pull_requests(formula.name, tap_remote_repo,
                                                 version:,
                                                 state:   "closed",
                                                 file:    formula.path.relative_path_from(formula.tap.path).to_s,
                                                 quiet:   args.quiet?)
      end

      def alias_update_pair(formula, new_formula_version)
        versioned_alias = formula.aliases.grep(/^.*@\d+(\.\d+)?$/).first
        return if versioned_alias.nil?

        name, old_alias_version = versioned_alias.split("@")
        new_alias_regex = (old_alias_version.split(".").length == 1) ? /^\d+/ : /^\d+\.\d+/
        new_alias_version, = *new_formula_version.to_s.match(new_alias_regex)
        return if Version.new(new_alias_version) <= Version.new(old_alias_version)

        [versioned_alias, "#{name}@#{new_alias_version}"]
      end

      def run_audit(formula, alias_rename, old_contents)
        audit_args = ["--formula"]
        audit_args << "--strict" if args.strict?
        audit_args << "--online" if args.online?
        if args.dry_run?
          if args.no_audit?
            ohai "Skipping `brew audit`"
          elsif audit_args.present?
            ohai "brew audit #{audit_args.join(" ")} #{formula.path.basename}"
          else
            ohai "brew audit #{formula.path.basename}"
          end
          return
        end
        FileUtils.mv alias_rename.first, alias_rename.last if alias_rename.present?
        failed_audit = false
        if args.no_audit?
          ohai "Skipping `brew audit`"
        elsif audit_args.present?
          system HOMEBREW_BREW_FILE, "audit", *audit_args, formula.full_name
          failed_audit = !$CHILD_STATUS.success?
        else
          system HOMEBREW_BREW_FILE, "audit", formula.full_name
          failed_audit = !$CHILD_STATUS.success?
        end
        return unless failed_audit

        formula.path.atomic_write(old_contents)
        FileUtils.mv alias_rename.last, alias_rename.first if alias_rename.present?
        odie "`brew audit` failed!"
      end
    end
  end
end
