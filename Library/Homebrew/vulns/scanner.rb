# typed: strict
# frozen_string_literal: true

require "sbom"
require "vulns/osv"
require "vulns/vulnerability"

module Homebrew
  module Vulns
    class Scanner
      FORGES = %w[github.com gitlab.com codeberg.org].freeze
      private_constant :FORGES

      TAG_PATTERNS = T.let(
        [
          %r{/archive/refs/tags/([^/]+)\.tar\.gz$},
          %r{/archive/refs/tags/([^/]+)\.zip$},
          %r{/archive/([^/]+)\.tar\.gz$},
          %r{/archive/([^/]+)\.zip$},
          %r{/releases/download/([^/]+)/},
          %r{/tarball/([^/]+)$},
        ].freeze,
        T::Array[Regexp],
      )
      private_constant :TAG_PATTERNS

      sig { params(urls: T.nilable(String)).returns(T.nilable(String)) }
      def self.repo_url(*urls)
        urls.each do |url|
          next if url.nil?

          forge = FORGES.find { |f| url.include?(f) }
          next if forge.nil?

          match = url.match(%r{https?://#{Regexp.escape(forge)}/([^/]+/[^/]+)})
          next if match.nil?

          repo_path = T.must(match[1]).sub(/\.git$/, "").sub(%r{/-/.*}, "")
          return "https://#{forge}/#{repo_path}"
        end
        nil
      end

      sig {
        params(source_url: T.nilable(String), head_url: T.nilable(String),
               homepage: T.nilable(String)).returns(T.nilable(String))
      }
      def self.target_repo_url(source_url, head_url, homepage)
        url = repo_url(source_url, head_url, homepage)
        url ||= source_url if tag(source_url)
        url ||= head_url
        url
      end

      sig { params(url: T.nilable(String)).returns(T.nilable(String)) }
      def self.tag(url)
        return if url.nil?

        TAG_PATTERNS.each do |pattern|
          match = url.match(pattern)
          return match[1] if match
        end
        nil
      end

      SBOM_SRC_SPDXID = /\ASPDXRef-Archive-.*-src\z/
      private_constant :SBOM_SRC_SPDXID

      sig { params(prefix: Pathname).returns(T.nilable([T.nilable(String), T.nilable(String)])) }
      def self.source_from_sbom(prefix)
        file = prefix/SBOM::FILENAME
        return unless file.file?

        data = JSON.parse(file.read)
        src = Array(data["packages"]).find { |p| p["SPDXID"].to_s.match?(SBOM_SRC_SPDXID) }
        return if src.nil?

        url = src["downloadLocation"]
        url = nil if url == "NOASSERTION"
        version = src["versionInfo"]
        version = nil if version == "NOASSERTION"
        return if url.nil? && version.nil?

        [url, version]
      rescue JSON::ParserError
        nil
      end

      sig { params(serialized_patches: T::Array[T::Hash[String, T.untyped]]).returns(T::Array[String]) }
      def self.resolved_ids(serialized_patches)
        serialized_patches
          .flat_map { |p| Array(p["resolves"]) }
          .select { |r| r.is_a?(Hash) && r["type"] == "security" }
          .map { |r| r["id"].to_s.upcase }
          .uniq
      end

      Finding = Struct.new(:name, :version, :tag, :repo_url, :open, :patched, keyword_init: true)

      class Results
        sig { returns(T::Array[Finding]) }
        attr_reader :findings

        sig { returns(Integer) }
        attr_reader :checked, :skipped

        sig { returns(T::Array[String]) }
        attr_reader :outdated_without_sbom

        sig {
          params(findings: T::Array[Finding], checked: Integer, skipped: Integer,
                 outdated_without_sbom: T::Array[String]).void
        }
        def initialize(findings:, checked:, skipped:, outdated_without_sbom: [])
          @findings = findings
          @checked = checked
          @skipped = skipped
          @outdated_without_sbom = outdated_without_sbom
        end

        sig { returns(T::Boolean) }
        def any_open?
          findings.any? { |f| f.open.any? }
        end
      end

      MAX_VULN_FETCH_THREADS = 15
      private_constant :MAX_VULN_FETCH_THREADS

      SEVERITY_LEVELS = T.let(
        { low: 1, medium: 2, high: 3, critical: 4 }.freeze,
        T::Hash[Symbol, Integer],
      )
      private_constant :SEVERITY_LEVELS

      sig {
        params(formulae: T::Array[Formula], ignore_patches: T::Boolean, min_severity: T.nilable(Symbol)).void
      }
      def initialize(formulae, ignore_patches: true, min_severity: nil)
        @formulae = formulae
        @ignore_patches = ignore_patches
        @min_severity_level = T.let(min_severity ? SEVERITY_LEVELS.fetch(min_severity) : 0, Integer)
      end

      Target = Struct.new(:repo_url, :tag, :version, :from_installed_sbom, :current_recipe_applies,
                          keyword_init: true)
      private_constant :Target

      sig { returns(Results) }
      def scan
        queryable, skipped = @formulae.partition { |f| target_for(f) }
        outdated_without_sbom = queryable.select { |f| stale_target?(f) }.map(&:name)
        if queryable.empty?
          return Results.new(findings: [], checked: 0, skipped: skipped.size, outdated_without_sbom:)
        end

        targets = queryable.map { |f| T.must(target_for(f)) }
        batch = OSV.query_batch(targets.map { |t| { repo_url: t.repo_url, version: t.tag } })

        findings = queryable.each_with_index.filter_map do |formula, index|
          target = targets.fetch(index)
          ids = batch.fetch(index)
          next if ids.empty?

          vulns = fetch_vulnerabilities(ids)
                  .select { |v| v.affects_version?(target.tag) }
                  .select { |v| v.severity_level >= @min_severity_level }
          next if vulns.empty?

          open, patched = partition_patched(formula, target, vulns)
          next if open.empty? && patched.empty?

          Finding.new(
            name:     formula.name,
            version:  target.version,
            tag:      target.tag,
            repo_url: target.repo_url,
            open:,
            patched:,
          )
        end

        Results.new(findings:, checked: queryable.size, skipped: skipped.size, outdated_without_sbom:)
      end

      sig { params(formula: Formula).returns(T.nilable(Target)) }
      def target_for(formula)
        @targets ||= T.let({}, T.nilable(T::Hash[String, T.nilable(Target)]))
        @targets.fetch(formula.full_name) do
          @targets[formula.full_name] = build_target(formula)
        end
      end

      sig { params(formula: Formula).returns(T.nilable(Target)) }
      def build_target(formula)
        stable = formula.stable
        stable_url = stable&.url
        head_url = formula.head&.url
        homepage = formula.homepage

        stable_repo_url = self.class.target_repo_url(stable_url, head_url, homepage)
        stable_tag = self.class.tag(stable_url) || stable&.specs&.[](:tag) || stable&.version&.to_s

        if (prefix = formula.any_installed_prefix)
          installed_pkg_version = formula.any_installed_version
          installed_version = installed_pkg_version&.version.to_s
          current_recipe_applies = installed_pkg_version == formula.pkg_version

          if (sbom = self.class.source_from_sbom(prefix))
            sbom_url, sbom_version = sbom
            repo_url = self.class.target_repo_url(sbom_url, head_url, homepage)
            tag = self.class.tag(sbom_url) || sbom_version || installed_version.presence
            if repo_url && tag
              return Target.new(repo_url:, tag:, version: installed_version,
                                from_installed_sbom: true, current_recipe_applies:)
            end
          end

          return if stable_repo_url.nil? || stable_tag.nil?

          return Target.new(repo_url: stable_repo_url, tag: stable_tag, version: installed_version,
                            from_installed_sbom: false, current_recipe_applies:)
        end

        return if stable_repo_url.nil? || stable_tag.nil?

        Target.new(repo_url: stable_repo_url, tag: stable_tag, version: formula.version.to_s,
                   from_installed_sbom: false, current_recipe_applies: true)
      end

      sig { params(formula: Formula).returns(T::Boolean) }
      def stale_target?(formula)
        target = target_for(formula)
        return false if target.nil? || target.from_installed_sbom

        !target.current_recipe_applies
      end

      sig { params(ids: T::Array[T::Hash[String, T.untyped]]).returns(T::Array[Vulnerability]) }
      def fetch_vulnerabilities(ids)
        records = ids.each_slice(MAX_VULN_FETCH_THREADS).flat_map do |slice|
          slice
            .map { |v| Thread.new { OSV.vulnerability(v.fetch("id")) } }
            .map { |t| T.cast(t.value, T::Hash[String, T.untyped]) }
        end
        Vulnerability.from_osv_list(records)
      end

      sig {
        params(formula: Formula, target: Target, vulns: T::Array[Vulnerability])
          .returns([T::Array[Vulnerability], T::Array[Vulnerability]])
      }
      def partition_patched(formula, target, vulns)
        return [vulns, []] unless @ignore_patches
        # The current formula's `serialized_patches` reflects the recipe on
        # disk. If the scanned keg was built from an older recipe it may lack a
        # patch the recipe has since gained, so its `resolves` must not
        # suppress findings.
        return [vulns, []] unless target.current_recipe_applies

        resolved = self.class.resolved_ids(formula.serialized_patches)
        return [vulns, []] if resolved.empty?

        patched, open = vulns.partition do |v|
          v.identifiers.any? { |id| resolved.include?(id.to_s.upcase) }
        end
        [open, patched]
      end
    end
  end
end
