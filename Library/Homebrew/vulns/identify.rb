# typed: strict
# frozen_string_literal: true

require "vulns/purl"

module Homebrew
  module Vulns
    # Derives OSV.dev query keys (forge repo URL, release tag) from formula
    # source URLs. Shared between {Scanner} and the advisory-matching pipeline.
    module Identify
      TWO_SEGMENT_PATH = %r{/([^/]+/[^/]+)}
      private_constant :TWO_SEGMENT_PATH

      # GitLab supports nested subgroups (e.g. `xorg/lib/libx11`); the path is
      # bounded by `.git`, the `/-/` route marker, the legacy `/uploads/` and
      # `/wikis/` routes, or the end of the URL. Host-level `/-/` and `/api/`
      # routes are rejected via the leading negative lookahead.
      GITLAB_PATH = %r{/(?!-|api/)([^/]+(?:/[^/]+)+?)(?:\.git)?(?=/-/|/uploads/|/wikis/|/?\z)}
      private_constant :GITLAB_PATH

      FORGES = T.let(
        {
          "github.com"             => TWO_SEGMENT_PATH,
          "codeberg.org"           => TWO_SEGMENT_PATH,
          "gitlab.com"             => GITLAB_PATH,
          "gitlab.gnome.org"       => GITLAB_PATH,
          "gitlab.freedesktop.org" => GITLAB_PATH,
          "invent.kde.org"         => GITLAB_PATH,
        }.freeze,
        T::Hash[String, Regexp],
      )
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

      WAYBACK_PREFIX = %r{\Ahttps?://web\.archive\.org/web/\d+[a-z_*]*/}
      private_constant :WAYBACK_PREFIX

      # OSV.dev's GIT ecosystem indexes repository URLs case-sensitively but
      # normalises `github.com` paths to lowercase (GitHub itself is
      # case-insensitive). GitLab and Codeberg are case-sensitive so their
      # paths are preserved.
      LOWERCASE_PATH_HOSTS = ["github.com"].freeze
      private_constant :LOWERCASE_PATH_HOSTS

      sig { params(urls: T.nilable(String)).returns(T.nilable(String)) }
      def self.repo_url(*urls)
        urls.each do |url|
          next if url.nil?

          url = url.sub(WAYBACK_PREFIX, "")
          FORGES.each do |host, path_pattern|
            match = url.match(%r{\Ahttps?://#{Regexp.escape(host)}#{path_pattern}})
            next if match.nil?

            repo_path = T.must(match[1]).sub(/\.git$/, "")
            repo_path = repo_path.downcase if LOWERCASE_PATH_HOSTS.include?(host)
            return "https://#{host}/#{repo_path}"
          end
        end
        nil
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

      # `ecosystem` is the OSV.dev ecosystem identifier for `name`, or `"CPAN"`
      # for CPAN distributions (queried via CPANSA, not OSV).
      RegistryPackage = Struct.new(:ecosystem, :name, :version, :purl, keyword_init: true)

      ARCHIVE_EXTENSIONS = /\.(?:tar\.gz|tar\.bz2|tar\.xz|tgz|zip|gem|crate|tar|nupkg)\z/i
      private_constant :ARCHIVE_EXTENSIONS

      # Cabal package versions are dot-separated non-negative integers only.
      HACKAGE_PKGID = /\A(.+)-(\d+(?:\.\d+)*)\z/
      private_constant :HACKAGE_PKGID

      # Simplified from CPAN::DistnameInfo: greedy name, version is digits/
      # dots/underscores optionally `v`-prefixed. A -TRIAL suffix is stripped.
      # Does not handle the rare `_`-separated form (e.g. `libao-perl_0.03-1`);
      # no homebrew-core formula currently uses it.
      CPAN_DISTNAME = /\A(.+)-(v?\d[\d._]*)(?:-TRIAL\d*)?\z/
      private_constant :CPAN_DISTNAME

      # Recognise a `Gem::Platform` suffix by its OS token; the CPU token is
      # open-ended (riscv64, s390x, ppc64le, ...) so is matched generically.
      GEM_PLATFORM_SUFFIX = /
        -(?:
          java|jruby|truffleruby|dalvik|dotnet|mswin\d+(?:_\d+)?|
          \w+-
          (?:aix|cygwin|darwin|freebsd|linux|macruby|mingw\w*|mswin\d*|
             netbsd\w*|openbsd|bitrig|solaris|wasi)
          (?:[-_][\w.]+)?
        )\z
      /x
      private_constant :GEM_PLATFORM_SUFFIX

      sig { params(url: T.nilable(String)).returns(T.nilable(RegistryPackage)) }
      def self.registry_package(url)
        return if url.nil?

        ecosystem, purl = registry_purl(url)
        return if purl.nil?

        name = case purl.type
        when "maven" then "#{purl.namespace}:#{purl.name}"
        # OSV keys PyPI packages by their PEP 503 normalised name.
        when "pypi" then purl.name.gsub(/[-_.]+/, "-")
        # CPANSA is keyed on the distribution name alone, without the author.
        when "cpan" then purl.name
        else purl.namespace ? "#{purl.namespace}/#{purl.name}" : purl.name
        end
        RegistryPackage.new(ecosystem:, name:, version: purl.version, purl: purl.to_s).freeze
      end

      sig { params(url: String).returns(T.nilable([String, Purl])) }
      def self.registry_purl(url)
        basename = decode(File.basename(url)).sub(ARCHIVE_EXTENSIONS, "")

        case url
        when %r{\Ahttps://files\.pythonhosted\.org/packages/(?:[^/]+/){3}(?![^/]+\.whl\z)}
          # PEP 440 canonical versions contain no hyphen, so the last one delimits.
          name, _, version = basename.rpartition("-")
          return if name.empty?

          ["PyPI", Purl.new(type: "pypi", name:, version:)]
        when %r{\Ahttps://registry\.npmjs\.org/(?:((?:@|%40)[^/]+)/)?([^/@%][^/]*)/-/}
          namespace = Regexp.last_match(1)
          name = T.must(Regexp.last_match(2))
          namespace &&= "@#{decode(namespace).delete_prefix("@")}"
          name = decode(name)
          return unless (version = version_after_prefix(basename, name))

          ["npm", Purl.new(type: "npm", namespace:, name:, version:)]
        when %r{\Ahttps://static\.crates\.io/crates/([^/]+)/}
          name = decode(T.must(Regexp.last_match(1)))
          return unless (version = version_after_prefix(basename, name))

          ["crates.io", Purl.new(type: "cargo", name:, version:)]
        when %r{\Ahttps://rubygems\.org/(?:downloads|gems)/}
          name, version = gem_name_version(basename)
          return if name.nil?

          ["RubyGems", Purl.new(type: "gem", name:, version:)]
        when %r{\Ahttps://hackage\.haskell\.org/package/([^/]+)}
          match = T.must(Regexp.last_match(1)).match(HACKAGE_PKGID)
          return if match.nil?

          ["Hackage", Purl.new(type: "hackage", name: T.must(match[1]), version: match[2])]
        when %r{\Ahttps://repo\.hex\.pm/tarballs/}
          # Hex package names are `[a-z][a-z0-9_]*` so the first hyphen delimits.
          name, sep, version = basename.partition("-")
          return if sep.empty?

          ["Hex", Purl.new(type: "hex", name:, version:)]
        when %r{/authors/id/[A-Z]/[A-Z]{2}/([A-Z][A-Z0-9-]+)/}
          author = T.must(Regexp.last_match(1))
          match = basename.match(CPAN_DISTNAME)
          return if match.nil?

          ["CPAN", Purl.new(type: "cpan", namespace: author, name: T.must(match[1]), version: match[2])]
        # Maven Central only: OSV's bare `Maven` ecosystem is Central-scoped,
        # so third-party repositories (Google, fabricmc, jfrog, ...) are skipped.
        when %r{\Ahttps://repo1?\.maven\.(?:apache\.)?org/maven2/(.+)/([^/]+)/([^/]+)/\2-\3[.-][^/]+\z},
             %r{\Ahttps://search\.maven\.org/remotecontent\?filepath=(.+)/([^/]+)/([^/]+)/\2-\3[.-][^/]+\z}
          group_id = T.must(Regexp.last_match(1)).tr("/", ".")
          artifact_id = T.must(Regexp.last_match(2))
          version = Regexp.last_match(3)
          ["Maven", Purl.new(type: "maven", namespace: group_id, name: artifact_id, version:)]
        when %r{\Ahttps://(?:cran|cloud)\.r-project\.org/src/contrib/(?:Archive/[^/]+/)?([^/_]+)_([^/]+)\.tar\.gz\z}
          ["CRAN", Purl.new(type: "cran", name: T.must(Regexp.last_match(1)), version: Regexp.last_match(2))]
        when %r{\Ahttps://(?:api|www)\.nuget\.org/(?:v3-flatcontainer|api/v2/package)/([^/]+)/([^/]+)(?:/|\z)}
          ["NuGet", Purl.new(type: "nuget", name: T.must(Regexp.last_match(1)), version: Regexp.last_match(2))]
        end
      end

      # Percent-decode a URL path segment. Unlike `decode_www_form_component`
      # this leaves `+` alone and unlike `decode_uri_component` (missing from
      # Sorbet's stdlib RBI) it never raises on malformed input.
      sig { params(component: String).returns(String) }
      def self.decode(component)
        return component unless component.include?("%")

        component.b.gsub(/%[0-9A-Fa-f]{2}/) { |m| Integer(m[1, 2], 16).chr }
                 .force_encoding(component.encoding)
      end

      sig { params(basename: String, name: String).returns(T.nilable(String)) }
      def self.version_after_prefix(basename, name)
        prefix = "#{name}-"
        return unless basename.start_with?(prefix)

        version = basename[prefix.length..]
        version.presence
      end

      # Split a `.gem` basename into name and version, discarding any trailing
      # {Gem::Platform} suffix (e.g. `nokogiri-1.16.0-arm64-darwin-22`).
      sig { params(basename: String).returns([T.nilable(String), T.nilable(String)]) }
      def self.gem_name_version(basename)
        deplatformed = basename.sub(GEM_PLATFORM_SUFFIX, "")
        name, sep, version = deplatformed.rpartition("-")
        return [nil, nil] if sep.empty? || !version.match?(/\A\d[\w.]*\z/)

        [name, version]
      end
    end
  end
end
