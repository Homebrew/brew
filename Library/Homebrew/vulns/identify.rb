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
            repo_path = url[%r{\Ahttps?://#{Regexp.escape(host)}#{path_pattern}}, 1]
            next if repo_path.nil?

            repo_path = repo_path.sub(/\.git$/, "")
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

      REGISTRY_PURL_TYPES = T.let(
        {
          "CPAN"      => "cpan",
          "CRAN"      => "cran",
          "Hackage"   => "hackage",
          "Hex"       => "hex",
          "Maven"     => "maven",
          "NuGet"     => "nuget",
          "PyPI"      => "pypi",
          "RubyGems"  => "gem",
          "crates.io" => "cargo",
          "npm"       => "npm",
        }.freeze,
        T::Hash[String, String],
      )
      private_constant :REGISTRY_PURL_TYPES

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

        result = registry_purl(url)
        return if result.nil?

        ecosystem, purl = result
        registry_package_from_purl(ecosystem, purl)
      end

      # Build a canonical registry package from reviewed OSV package fields.
      # Returns nil for unsupported ecosystems or non-canonical package names.
      sig {
        params(ecosystem: String, name: String, version: T.nilable(String)).returns(T.nilable(RegistryPackage))
      }
      def self.registry_package_for(ecosystem:, name:, version: nil)
        return unless REGISTRY_PURL_TYPES.key?(ecosystem)
        return if name.empty? || name.match?(/\s/)

        namespace = T.let(nil, T.nilable(String))
        purl_name = T.let(name, String)
        case ecosystem
        when "npm"
          if name.start_with?("@")
            namespace, separator, purl_name = name.partition("/")
            return if namespace == "@" || separator.empty? || purl_name.empty? || purl_name.include?("/")
          elsif name.include?("/")
            return
          end
        when "Maven"
          namespace, separator, purl_name = name.rpartition(":")
          return if separator.empty? || namespace.empty? || purl_name.empty? || namespace.include?(":")
        end

        package = registry_package_from_purl(ecosystem, purl_for(ecosystem, namespace:, name: purl_name, version:))
        package if package.name == name
      end

      sig { params(ecosystem: String, purl: Purl).returns(RegistryPackage) }
      def self.registry_package_from_purl(ecosystem, purl)
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
      private_class_method :registry_package_from_purl

      sig {
        params(ecosystem: String, name: String, namespace: T.nilable(String),
               version: T.nilable(String)).returns(Purl)
      }
      def self.purl_for(ecosystem, name:, namespace: nil, version: nil)
        Purl.new(type: REGISTRY_PURL_TYPES.fetch(ecosystem), namespace:, name:, version:)
      end
      private_class_method :purl_for

      sig { params(url: String).returns(T.nilable([String, Purl])) }
      def self.registry_purl(url)
        basename = decode(File.basename(url)).sub(ARCHIVE_EXTENSIONS, "")

        case url
        when %r{\Ahttps://files\.pythonhosted\.org/packages/(?:[^/]+/){3}(?![^/]+\.whl\z)}
          # PEP 440 canonical versions contain no hyphen, so the last one delimits.
          name, _, version = basename.rpartition("-")
          return if name.empty?

          ["PyPI", purl_for("PyPI", name:, version:)]
        when %r{\Ahttps://registry\.npmjs\.org/(?:((?:@|%40)[^/]+)/)?([^/@%][^/]*)/-/}
          namespace = Regexp.last_match(1)
          name = Regexp.last_match(2)
          return if name.nil?

          namespace &&= "@#{decode(namespace).delete_prefix("@")}"
          name = decode(name)
          return unless (version = version_after_prefix(basename, name))

          ["npm", purl_for("npm", namespace:, name:, version:)]
        when %r{\Ahttps://static\.crates\.io/crates/([^/]+)/}
          name = Regexp.last_match(1)
          return if name.nil?

          name = decode(name)
          return unless (version = version_after_prefix(basename, name))

          ["crates.io", purl_for("crates.io", name:, version:)]
        when %r{\Ahttps://rubygems\.org/(?:downloads|gems)/}
          name, version = gem_name_version(basename)
          return if name.nil?

          ["RubyGems", purl_for("RubyGems", name:, version:)]
        when %r{\Ahttps://hackage\.haskell\.org/package/([^/]+)}
          match = Regexp.last_match(1)&.match(HACKAGE_PKGID)
          return if match.nil?

          name, version = match.captures
          return if name.nil?

          ["Hackage", purl_for("Hackage", name:, version:)]
        when %r{\Ahttps://repo\.hex\.pm/tarballs/}
          # Hex package names are `[a-z][a-z0-9_]*` so the first hyphen delimits.
          name, sep, version = basename.partition("-")
          return if sep.empty?

          ["Hex", purl_for("Hex", name:, version:)]
        when %r{/authors/id/[A-Z]/[A-Z]{2}/([A-Z][A-Z0-9-]+)/}
          author = Regexp.last_match(1)
          match = basename.match(CPAN_DISTNAME)
          return if author.nil? || match.nil?

          name, version = match.captures
          return if name.nil?

          ["CPAN", purl_for("CPAN", namespace: author, name:, version:)]
        # Maven Central only: OSV's bare `Maven` ecosystem is Central-scoped,
        # so third-party repositories (Google, fabricmc, jfrog, ...) are skipped.
        when %r{\Ahttps://repo1?\.maven\.(?:apache\.)?org/maven2/(.+)/([^/]+)/([^/]+)/\2-\3[.-][^/]+\z},
             %r{\Ahttps://search\.maven\.org/remotecontent\?filepath=(.+)/([^/]+)/([^/]+)/\2-\3[.-][^/]+\z}
          group_id = Regexp.last_match(1)
          artifact_id = Regexp.last_match(2)
          version = Regexp.last_match(3)
          return if group_id.nil? || artifact_id.nil?

          ["Maven", purl_for("Maven", namespace: group_id.tr("/", "."), name: artifact_id, version:)]
        when %r{\Ahttps://(?:cran|cloud)\.r-project\.org/src/contrib/(?:Archive/[^/]+/)?([^/_]+)_([^/]+)\.tar\.gz\z}
          name = Regexp.last_match(1)
          return if name.nil?

          ["CRAN", purl_for("CRAN", name:, version: Regexp.last_match(2))]
        when %r{\Ahttps://(?:api|www)\.nuget\.org/(?:v3-flatcontainer|api/v2/package)/([^/]+)/([^/]+)(?:/|\z)}
          name = Regexp.last_match(1)
          return if name.nil?

          ["NuGet", purl_for("NuGet", name:, version: Regexp.last_match(2))]
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
