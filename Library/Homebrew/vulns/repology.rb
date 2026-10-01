# typed: strict
# frozen_string_literal: true

require "utils/repology"
require "vulns/cached_feed"

module Homebrew
  module Vulns
    # Reader for the Repology-derived formula → distro-package index published
    # by Homebrew/advisory-database (`data/repology.json`, built by that
    # repository's `RepologyIndex` via `rake repology:build`).
    #
    # The index maps each formula name to its source-package names in
    # OSV.dev-covered distro ecosystems so {Vulns::Match} can query those
    # ecosystems' advisories. {.lookup} provides a live single-project API
    # fallback for formulae the published index doesn't yet cover.
    class Repology < CachedFeed
      DATA_URL = "https://raw.githubusercontent.com/Homebrew/advisory-database/" \
                 "main/data/repology.json"

      sig { override.returns(String) }
      def self.data_url = DATA_URL

      sig { override.returns(String) }
      def self.cache_filename = "repology.json"

      sig { override.returns(Integer) }
      def self.default_max_age = 7 * 86_400

      DistroMap = T.type_alias { T::Hash[String, T::Array[String]] }

      sig { params(name: String).returns(String) }
      def self.base_name(name) = name.sub(/@.+\z/, "")

      sig { override.params(data: T.anything).void }
      def initialize(data)
        super
        raise Error, "Repology index is not a JSON object" unless (top = as_hash(data))
        raise Error, "Repology index missing 'formulae' key" unless (formulae = as_hash(top["formulae"]))

        @formulae = T.let(formulae, T::Hash[String, T.untyped])
        @meta = T.let(as_hash(top["meta"]) || {}, T::Hash[String, T.untyped])
      end

      sig { returns(T::Hash[String, T.untyped]) }
      attr_reader :meta

      sig { returns(T::Array[String]) }
      def formulae
        @formulae.keys
      end

      # Returns `{osv_ecosystem => [srcname, ...]}` for `formula_name`, or an
      # empty hash if the index has no entry. The index is keyed on the
      # Homebrew formula name as Repology records it, so `@`-versioned
      # variants (`postgresql@16`) are looked up under their base name too.
      sig { params(formula_name: String).returns(DistroMap) }
      def distro_packages_for(formula_name)
        entry = @formulae[formula_name] || @formulae[self.class.base_name(formula_name)]
        return {} unless entry.is_a?(Hash)

        entry.filter_map do |eco, names|
          next unless eco.is_a?(String)

          list = Array(names).grep(String)
          [eco, list.freeze] if list.any?
        end.to_h.freeze
      end

      # Repology repo-name prefix => `{ecosystem:, name_field:}`. Kept in step
      # with `RepologyIndex::OSV_DISTROS` in Homebrew/advisory-database; only
      # the fields {.distil} needs are duplicated here.
      OSV_DISTROS = T.let(
        {
          "debian_"             => { ecosystem: "Debian" },
          "ubuntu_"             => { ecosystem: "Ubuntu" },
          "alpine_"             => { ecosystem: "Alpine" },
          "opensuse_leap_"      => { ecosystem: "openSUSE" },
          "opensuse_tumbleweed" => { ecosystem: "openSUSE" },
          "rocky_"              => { ecosystem: "Rocky Linux" },
          "almalinux_"          => { ecosystem: "AlmaLinux" },
          "mageia_"             => { ecosystem: "Mageia" },
          "openeuler_"          => { ecosystem: "openEuler" },
          "ubi_"                => { ecosystem: "Red Hat" },
          "freebsd"             => { ecosystem: "FreeBSD", name_field: "binname" },
        }.freeze,
        T::Hash[String, { ecosystem: String, name_field: T.nilable(String) }],
      )
      private_constant :OSV_DISTROS

      # Kept in step with `RepologyIndex::PREFERRED_STATUSES`.
      PREFERRED_STATUSES = %w[newest outdated devel unique noscheme].freeze
      private_constant :PREFERRED_STATUSES

      # Live single-project fallback for a formula the published index does
      # not cover: a new formula in a homebrew-core PR before the next nightly
      # index build, or one the index put in `meta.ambiguous_projects`.
      #
      # Fetches each project in {.name_candidates}, keeps those whose Homebrew
      # entries include `formula_name` (or its `@`-stripped base), then applies
      # the same preferred-status resolution as `RepologyIndex#resolve` across
      # the survivors. Unlike the index builder, a project that also lists
      # sibling formulae with a different base (`wget` + `wget2`, `sqlite` +
      # `sqlite-analyzer`, `ffmpeg` + a third-party `ffmpeg-full`) is *not*
      # rejected: the distro srcnames for the sibling flow through as extra
      # low-confidence distro queries whose upstream-CVE range check will not
      # match this formula's identity, so the cost is uncomparable noise rather
      # than a wrong `:affected`/`:fixed` claim. This cannot detect collisions
      # with projects outside {.name_candidates} (e.g. `allegro4`), which only
      # the full crawl sees.
      sig { params(formula_name: String).returns(DistroMap) }
      def self.lookup(formula_name)
        base = base_name(formula_name)
        exact = []
        by_base = []
        name_candidates(formula_name).each do |candidate|
          entries = fetch_project(candidate)
          next if entries.empty?

          brew = homebrew_entries(entries)
          distros = distil(entries)
          next if distros.empty?

          # A project listing both the exact and base names contributes to both
          # pools, matching the producer's per-key contributions.
          exact << { preferred: brew.fetch(formula_name), distros: } if brew.key?(formula_name)
          by_base << { preferred: brew.fetch(base), distros: } if base != formula_name && brew.key?(base)
        end

        # Resolve the exact-name pool first, mirroring
        # `#distro_packages_for`'s `@formulae[name] || @formulae[base]`
        # precedence over the producer's per-key resolved index.
        resolve_contributions(exact) || resolve_contributions(by_base) || {}
      end

      sig {
        params(contributions: T::Array[{ preferred: T::Boolean, distros: DistroMap }])
          .returns(T.nilable(DistroMap))
      }
      def self.resolve_contributions(contributions)
        chosen = contributions.one? ? contributions : contributions.select { |c| c.fetch(:preferred) }
        chosen.fetch(0).fetch(:distros) if chosen.one?
      end

      sig { params(entries: T::Array[T::Hash[String, T.untyped]]).returns(T::Hash[String, T::Boolean]) }
      def self.homebrew_entries(entries)
        result = {}
        entries.each do |e|
          next if e["repo"] != "homebrew"

          name = (e["srcname"] || e["binname"]).to_s
          next if name.empty?

          result[name] ||= false
          result[name] = true if PREFERRED_STATUSES.include?(e["status"])
        end
        result
      end

      sig { params(formula_name: String).returns(T::Array[String]) }
      def self.name_candidates(formula_name)
        base = base_name(formula_name)
        [
          formula_name,
          base,
          base.delete_prefix("lib"),
          base.delete_prefix("gnu-"),
          base.delete_suffix("2"),
        ].uniq.reject(&:empty?)
      end

      # Fetch one Repology project. A nonexistent project returns HTTP 200 with
      # `[]`, so an empty array is the only "try next candidate" signal;
      # transport failures, HTTP errors, malformed JSON and unexpected shapes
      # all raise so callers don't mistake an outage for "no packages".
      sig { params(project: String).returns(T::Array[T::Hash[String, T.untyped]]) }
      def self.fetch_project(project)
        result = ::Repology.single_package_query(project, repository: ::Repology::HOMEBREW_CORE)
        raise Error, "Repology API request for #{project.inspect} failed" if result.nil?

        entries = result.fetch(project)
        if !entries.is_a?(Array) || !entries.all?(Hash)
          raise Error, "Repology API returned unexpected shape for #{project.inspect}"
        end

        entries
      end

      sig { params(entries: T::Array[T::Hash[String, T.untyped]]).returns(DistroMap) }
      def self.distil(entries)
        result = Hash.new { |h, k| h[k] = [] }
        entries.each do |entry|
          repo = entry["repo"]
          next unless repo.is_a?(String)

          distro = OSV_DISTROS.find { |prefix, _| repo.start_with?(prefix) }&.last
          next unless distro
          next if entry["status"] == "legacy"

          name = entry[distro[:name_field] || "srcname"] || entry["binname"]
          next unless name.is_a?(String)

          result[distro.fetch(:ecosystem)] << name
        end
        result.transform_values! { |names| names.uniq.sort.freeze }
        result.default = nil
        result.sort.to_h.freeze
      end
    end
  end
end
