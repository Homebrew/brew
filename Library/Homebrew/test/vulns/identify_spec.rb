# typed: strict
# frozen_string_literal: true

require "vulns/identify"

RSpec.describe Homebrew::Vulns::Identify do
  describe ".repo_url" do
    it "extracts a GitHub repo from an archive/refs/tags URL" do
      url = "https://github.com/nektos/act/archive/refs/tags/v0.2.84.tar.gz"
      expect(described_class.repo_url(url)).to eq "https://github.com/nektos/act"
    end

    it "extracts a GitHub repo from a releases/download URL" do
      url = "https://github.com/owner/repo/releases/download/v1.2.3/source.tar.gz"
      expect(described_class.repo_url(url)).to eq "https://github.com/owner/repo"
    end

    it "extracts a GitHub repo from a .git URL, lowercasing the path (OSV normalises github.com)" do
      expect(described_class.repo_url("https://github.com/AomediaOrg/aom.git"))
        .to eq "https://github.com/aomediaorg/aom"
      expect(described_class.repo_url("https://github.com/FFmpeg/FFmpeg.git"))
        .to eq "https://github.com/ffmpeg/ffmpeg"
    end

    it "preserves path case for GitLab (case-sensitive host)" do
      expect(described_class.repo_url("https://gitlab.gnome.org/GNOME/glib.git"))
        .to eq "https://gitlab.gnome.org/GNOME/glib"
    end

    it "extracts a GitLab repo, stripping the /-/ path segment" do
      url = "https://gitlab.com/owner/repo/-/archive/v1.2.3/repo-v1.2.3.tar.gz"
      expect(described_class.repo_url(url)).to eq "https://gitlab.com/owner/repo"
    end

    it "extracts a Codeberg repo" do
      url = "https://codeberg.org/owner/repo/archive/v1.2.3.tar.gz"
      expect(described_class.repo_url(url)).to eq "https://codeberg.org/owner/repo"
    end

    it "extracts a gitlab.gnome.org repo from an archive URL" do
      url = "https://gitlab.gnome.org/Archive/pangox-compat/-/archive/0.0.2/pangox-compat-0.0.2.tar.gz"
      expect(described_class.repo_url(url)).to eq "https://gitlab.gnome.org/Archive/pangox-compat"
    end

    it "extracts a gitlab.freedesktop.org repo with a nested subgroup path" do
      url = "https://gitlab.freedesktop.org/xorg/lib/libx11/-/archive/libX11-1.8.7/" \
            "libx11-libX11-1.8.7.tar.gz"
      expect(described_class.repo_url(url)).to eq "https://gitlab.freedesktop.org/xorg/lib/libx11"
    end

    it "extracts a gitlab.freedesktop.org repo from a bare .git URL" do
      expect(described_class.repo_url("https://gitlab.freedesktop.org/cairo/cairo.git"))
        .to eq "https://gitlab.freedesktop.org/cairo/cairo"
    end

    it "extracts an invent.kde.org repo" do
      expect(described_class.repo_url("https://invent.kde.org/frameworks/karchive.git"))
        .to eq "https://invent.kde.org/frameworks/karchive"
    end

    it "extracts a gitlab.com repo with a nested subgroup path" do
      url = "https://gitlab.com/gitlab-org/security/gitlab/-/archive/v16.0.0/gitlab-v16.0.0.tar.gz"
      expect(described_class.repo_url(url)).to eq "https://gitlab.com/gitlab-org/security/gitlab"
    end

    it "extracts a GitLab repo from a legacy /uploads/ URL" do
      url = "https://gitlab.com/akkuscm/akku/uploads/9a82f6a11e35c67f0e0086/akku-1.1.0.tar.gz"
      expect(described_class.repo_url(url)).to eq "https://gitlab.com/akkuscm/akku"
    end

    it "extracts a GitLab repo from a /wikis/ URL" do
      expect(described_class.repo_url("https://gitlab.gnome.org/GNOME/gjs/wikis/Home"))
        .to eq "https://gitlab.gnome.org/GNOME/gjs"
    end

    it "extracts a GitLab repo from a URL with a trailing slash" do
      expect(described_class.repo_url("https://gitlab.com/gsasl/libntlm/"))
        .to eq "https://gitlab.com/gsasl/libntlm"
    end

    it "rejects a GitLab host-level /-/ route and falls back to a later URL" do
      stable = "https://gitlab.freedesktop.org/-/project/62/uploads/54a0f9/spice-0.16.0.tar.bz2"
      head = "https://gitlab.freedesktop.org/spice/spice.git"
      expect(described_class.repo_url(stable, head)).to eq "https://gitlab.freedesktop.org/spice/spice"
    end

    it "returns nil for a GitLab /api/ route" do
      expect(described_class.repo_url("https://gitlab.freedesktop.org/api/v4/projects/1205/releases"))
        .to be_nil
    end

    it "unwraps a Wayback Machine snapshot URL" do
      url = "https://web.archive.org/web/20180102081127/https://github.com/satori-com/tcpkali"
      expect(described_class.repo_url(url)).to eq "https://github.com/satori-com/tcpkali"
    end

    it "falls back to the head URL when the stable URL is not a supported forge" do
      stable = "https://aomedia.googlesource.com/aom.git"
      head = "https://github.com/AomediaOrg/aom.git"
      expect(described_class.repo_url(stable, head)).to eq "https://github.com/aomediaorg/aom"
    end

    it "falls back to the homepage when neither stable nor head is a supported forge" do
      stable = "https://libssh2.org/download/libssh2-1.11.0.tar.gz"
      homepage = "https://github.com/libssh2/libssh2"
      expect(described_class.repo_url(stable, nil, homepage)).to eq "https://github.com/libssh2/libssh2"
    end

    it "returns nil for unsupported hosts" do
      expect(described_class.repo_url("https://example.com/source.tar.gz")).to be_nil
    end

    it "returns nil for nil input" do
      expect(described_class.repo_url(nil)).to be_nil
      expect(described_class.repo_url(nil, nil)).to be_nil
    end
  end

  describe ".tag" do
    it "extracts from archive/refs/tags .tar.gz" do
      expect(described_class.tag("https://github.com/nektos/act/archive/refs/tags/v0.2.84.tar.gz"))
        .to eq "v0.2.84"
    end

    it "extracts a tag without a v prefix" do
      url = "https://github.com/abseil/abseil-cpp/archive/refs/tags/20250814.1.tar.gz"
      expect(described_class.tag(url)).to eq "20250814.1"
    end

    it "extracts from archive/refs/tags .zip" do
      expect(described_class.tag("https://github.com/owner/repo/archive/refs/tags/v1.0.0.zip"))
        .to eq "v1.0.0"
    end

    it "extracts from archive/<tag>.tar.gz" do
      expect(described_class.tag("https://codeberg.org/owner/repo/archive/v1.2.3.tar.gz"))
        .to eq "v1.2.3"
    end

    it "extracts from releases/download/<tag>/" do
      url = "https://github.com/owner/repo/releases/download/v1.2.3/source.tar.gz"
      expect(described_class.tag(url)).to eq "v1.2.3"
    end

    it "extracts from tarball/<tag>" do
      expect(described_class.tag("https://github.com/owner/repo/tarball/v1.2.3")).to eq "v1.2.3"
    end

    it "returns nil when no tag pattern matches" do
      expect(described_class.tag("https://example.com/source.tar.gz")).to be_nil
      expect(described_class.tag(nil)).to be_nil
    end
  end

  describe ".registry_package" do
    sig { params(url: T.nilable(String)).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def result(url)
      described_class.registry_package(url)&.to_h
    end

    context "with a PyPI sdist URL" do
      it "parses a simple package" do
        url = "https://files.pythonhosted.org/packages/00/2a/e8/jmespath-1.0.1.tar.gz"
        expect(result(url)).to eq(ecosystem: "PyPI", name: "jmespath", version: "1.0.1",
                                  purl: "pkg:pypi/jmespath@1.0.1")
      end

      it "normalises an underscored name" do
        url = "https://files.pythonhosted.org/packages/00/07/d1/types_setuptools-80.9.0.20251223.tar.gz"
        expect(result(url)).to eq(ecosystem: "PyPI", name: "types-setuptools",
                                  version: "80.9.0.20251223",
                                  purl: "pkg:pypi/types-setuptools@80.9.0.20251223")
      end

      it "handles a name containing a hyphen followed by digits" do
        url = "https://files.pythonhosted.org/packages/aa/bb/cc/iso-639-2025.2.18.tar.gz"
        expect(result(url)).to eq(ecosystem: "PyPI", name: "iso-639", version: "2025.2.18",
                                  purl: "pkg:pypi/iso-639@2025.2.18")
      end

      it "PEP 503-normalises a dotted name for OSV while preserving the dot in the purl" do
        url = "https://files.pythonhosted.org/packages/aa/bb/cc/ruamel.yaml-0.18.6.tar.gz"
        expect(result(url)).to eq(ecosystem: "PyPI", name: "ruamel-yaml", version: "0.18.6",
                                  purl: "pkg:pypi/ruamel.yaml@0.18.6")
      end

      it "returns nil for a wheel" do
        url = "https://files.pythonhosted.org/packages/aa/bb/cc/foo-1.0-py3-none-any.whl"
        expect(result(url)).to be_nil
      end
    end

    context "with an npm tarball URL" do
      it "parses a scoped package" do
        url = "https://registry.npmjs.org/@angular/cli/-/cli-22.0.3.tgz"
        expect(result(url)).to eq(ecosystem: "npm", name: "@angular/cli", version: "22.0.3",
                                  purl: "pkg:npm/%40angular/cli@22.0.3")
      end

      it "parses an unscoped package" do
        url = "https://registry.npmjs.org/reveal-md/-/reveal-md-6.1.4.tgz"
        expect(result(url)).to eq(ecosystem: "npm", name: "reveal-md", version: "6.1.4",
                                  purl: "pkg:npm/reveal-md@6.1.4")
      end

      it "handles a name containing a hyphen followed by digits" do
        url = "https://registry.npmjs.org/es5-shim/-/es5-shim-4.6.7.tgz"
        expect(result(url)).to eq(ecosystem: "npm", name: "es5-shim", version: "4.6.7",
                                  purl: "pkg:npm/es5-shim@4.6.7")
      end

      it "handles a semver prerelease version" do
        url = "https://registry.npmjs.org/react/-/react-19.0.0-rc.1.tgz"
        expect(result(url))
          .to eq(ecosystem: "npm", name: "react", version: "19.0.0-rc.1",
                 purl: "pkg:npm/react@19.0.0-rc.1")
      end

      it "decodes a percent-encoded scope" do
        url = "https://registry.npmjs.org/%40angular/cli/-/cli-22.0.3.tgz"
        expect(result(url)).to eq(ecosystem: "npm", name: "@angular/cli", version: "22.0.3",
                                  purl: "pkg:npm/%40angular/cli@22.0.3")
      end

      it "decodes multi-byte percent escapes without an encoding error" do
        expect(described_class.decode("caf%C3%A9")).to eq "café"
        expect(described_class.decode("%80").bytes).to eq [0x80]
      end

      it "returns nil when the tarball filename does not match the path name" do
        expect(result("https://registry.npmjs.org/foo/-/bar-1.0.0.tgz")).to be_nil
      end
    end

    context "with a crates.io URL" do
      it "parses the crate name from the path and version from the filename" do
        url = "https://static.crates.io/crates/cargo-llvm-cov/cargo-llvm-cov-0.8.7.crate"
        expect(result(url)).to eq(ecosystem: "crates.io", name: "cargo-llvm-cov", version: "0.8.7",
                                  purl: "pkg:cargo/cargo-llvm-cov@0.8.7")
      end

      it "returns nil when the filename does not match the path name" do
        expect(result("https://static.crates.io/crates/foo/bar-1.0.0.crate")).to be_nil
      end
    end

    context "with a RubyGems URL" do
      it "parses a /downloads/ URL" do
        url = "https://rubygems.org/downloads/activesupport-8.1.1.gem"
        expect(result(url)).to eq(ecosystem: "RubyGems", name: "activesupport", version: "8.1.1",
                                  purl: "pkg:gem/activesupport@8.1.1")
      end

      it "parses a /gems/ URL" do
        url = "https://rubygems.org/gems/addressable-2.8.6.gem"
        expect(result(url)).to eq(ecosystem: "RubyGems", name: "addressable", version: "2.8.6",
                                  purl: "pkg:gem/addressable@2.8.6")
      end

      it "handles a name containing a hyphen followed by digits" do
        url = "https://rubygems.org/downloads/iso-639-0.3.6.gem"
        expect(result(url)).to eq(ecosystem: "RubyGems", name: "iso-639", version: "0.3.6",
                                  purl: "pkg:gem/iso-639@0.3.6")
      end

      it "strips a trailing platform suffix" do
        url = "https://rubygems.org/downloads/nokogiri-1.16.0-arm64-darwin.gem"
        expect(result(url)).to eq(ecosystem: "RubyGems", name: "nokogiri", version: "1.16.0",
                                  purl: "pkg:gem/nokogiri@1.16.0")
      end

      it "strips a platform suffix ending in a numeric OS version" do
        url = "https://rubygems.org/downloads/couchbase-3.5.1-arm64-darwin-22.gem"
        expect(result(url)).to eq(ecosystem: "RubyGems", name: "couchbase", version: "3.5.1",
                                  purl: "pkg:gem/couchbase@3.5.1")
      end

      it "strips a bare-word platform suffix" do
        url = "https://rubygems.org/downloads/jrubyfx-2.0.0-java.gem"
        expect(result(url)).to eq(ecosystem: "RubyGems", name: "jrubyfx", version: "2.0.0",
                                  purl: "pkg:gem/jrubyfx@2.0.0")
      end

      it "strips a musl platform suffix" do
        url = "https://rubygems.org/downloads/ffi-1.17.4-x86_64-linux-musl.gem"
        expect(result(url)).to eq(ecosystem: "RubyGems", name: "ffi", version: "1.17.4",
                                  purl: "pkg:gem/ffi@1.17.4")
      end

      it "strips a mingw-ucrt platform suffix" do
        url = "https://rubygems.org/downloads/ruby-prof-2.0.4-x64-mingw-ucrt.gem"
        expect(result(url)).to eq(ecosystem: "RubyGems", name: "ruby-prof", version: "2.0.4",
                                  purl: "pkg:gem/ruby-prof@2.0.4")
      end

      it "strips a platform suffix with an unenumerated CPU" do
        url = "https://rubygems.org/downloads/sass-embedded-1.97.2-riscv64-linux-gnu.gem"
        expect(result(url)).to eq(ecosystem: "RubyGems", name: "sass-embedded", version: "1.97.2",
                                  purl: "pkg:gem/sass-embedded@1.97.2")
      end

      it "strips a platform suffix with a dotted OS version" do
        url = "https://rubygems.org/downloads/concurrent-ruby-0.7.1-x86-solaris-2.11.gem"
        expect(result(url)).to eq(ecosystem: "RubyGems", name: "concurrent-ruby", version: "0.7.1",
                                  purl: "pkg:gem/concurrent-ruby@0.7.1")
      end

      it "keeps a prerelease segment in the version" do
        url = "https://rubygems.org/downloads/rails-8.0.0.beta1.gem"
        expect(result(url)).to eq(ecosystem: "RubyGems", name: "rails", version: "8.0.0.beta1",
                                  purl: "pkg:gem/rails@8.0.0.beta1")
      end
    end

    context "with a Hackage URL" do
      it "parses a package identifier from the path" do
        url = "https://hackage.haskell.org/package/Allure-0.11.0.0/Allure-0.11.0.0.tar.gz"
        expect(result(url)).to eq(ecosystem: "Hackage", name: "Allure", version: "0.11.0.0",
                                  purl: "pkg:hackage/Allure@0.11.0.0")
      end

      it "handles a name containing a hyphen followed by digits" do
        url = "https://hackage.haskell.org/package/base64-bytestring-1.2.1.0/" \
              "base64-bytestring-1.2.1.0.tar.gz"
        expect(result(url)).to eq(ecosystem: "Hackage", name: "base64-bytestring",
                                  version: "1.2.1.0",
                                  purl: "pkg:hackage/base64-bytestring@1.2.1.0")
      end
    end

    context "with a Hex URL" do
      it "parses name and version, keeping a semver prerelease" do
        url = "https://repo.hex.pm/tarballs/phoenix-1.7.0-rc.0.tar"
        expect(result(url)).to eq(ecosystem: "Hex", name: "phoenix", version: "1.7.0-rc.0",
                                  purl: "pkg:hex/phoenix@1.7.0-rc.0")
      end
    end

    context "with a CPAN URL" do
      it "uses the distribution alone as the CPANSA name and includes the author in the purl" do
        url = "https://cpan.metacpan.org/authors/id/A/AB/ABIGAIL/Regexp-Common-2024080801.tar.gz"
        expect(result(url)).to eq(ecosystem: "CPAN", name: "Regexp-Common",
                                  version: "2024080801",
                                  purl: "pkg:cpan/ABIGAIL/Regexp-Common@2024080801")
      end

      it "handles a distribution name containing a digit-led segment" do
        url = "https://cpan.metacpan.org/authors/id/C/CF/CFRANKS/Perl6-Junction-1.60000.tar.gz"
        expect(result(url)).to eq(ecosystem: "CPAN", name: "Perl6-Junction",
                                  version: "1.60000",
                                  purl: "pkg:cpan/CFRANKS/Perl6-Junction@1.60000")
      end

      it "handles a v-prefixed version" do
        url = "https://cpan.metacpan.org/authors/id/L/LE/LEONT/ExtUtils-HasCompiler-v0.25.0.tar.gz"
        expect(result(url)).to eq(ecosystem: "CPAN", name: "ExtUtils-HasCompiler",
                                  version: "v0.25.0",
                                  purl: "pkg:cpan/LEONT/ExtUtils-HasCompiler@v0.25.0")
      end

      it "handles a subdirectory below the author directory" do
        url = "https://cpan.metacpan.org/authors/id/A/AM/AMBS/BibTeX/Text-BibTeX-0.91.tar.gz"
        expect(result(url)).to eq(ecosystem: "CPAN", name: "Text-BibTeX", version: "0.91",
                                  purl: "pkg:cpan/AMBS/Text-BibTeX@0.91")
      end

      it "keeps a developer _NN suffix in the version" do
        url = "https://cpan.metacpan.org/authors/id/E/ET/ETHER/Moose-2.2207_01.tar.gz"
        expect(result(url)).to eq(ecosystem: "CPAN", name: "Moose", version: "2.2207_01",
                                  purl: "pkg:cpan/ETHER/Moose@2.2207_01")
      end

      it "strips a -TRIAL suffix from the version" do
        url = "https://cpan.metacpan.org/authors/id/E/ET/ETHER/Moose-2.2200-TRIAL.tar.gz"
        expect(result(url)).to eq(ecosystem: "CPAN", name: "Moose", version: "2.2200",
                                  purl: "pkg:cpan/ETHER/Moose@2.2200")
      end
    end

    context "with a Maven URL" do
      it "parses groupId, artifactId and version from repo.maven.apache.org" do
        url = "https://repo.maven.apache.org/maven2/com/github/spotbugs/spotbugs/4.10.2/" \
              "spotbugs-4.10.2.tgz"
        expect(result(url)).to eq(ecosystem: "Maven", name: "com.github.spotbugs:spotbugs",
                                  version: "4.10.2",
                                  purl: "pkg:maven/com.github.spotbugs/spotbugs@4.10.2")
      end

      it "parses a search.maven.org remotecontent URL" do
        url = "https://search.maven.org/remotecontent?filepath=org/gradle/profiler/" \
              "gradle-profiler/0.24.0/gradle-profiler-0.24.0.zip"
        expect(result(url)).to eq(ecosystem: "Maven", name: "org.gradle.profiler:gradle-profiler",
                                  version: "0.24.0",
                                  purl: "pkg:maven/org.gradle.profiler/gradle-profiler@0.24.0")
      end

      it "returns nil for a maven-metadata.xml URL" do
        url = "https://repo.maven.apache.org/maven2/com/madgag/bfg/maven-metadata.xml"
        expect(result(url)).to be_nil
      end

      it "returns nil for a third-party Maven repository (Central-only by design)" do
        url = "https://maven.fabricmc.net/net/fabricmc/fabric-installer/1.1.1/" \
              "fabric-installer-1.1.1.jar"
        expect(result(url)).to be_nil
      end

      it "returns nil for a non-Central host with a /maven2/ path" do
        url = "https://dl.google.com/dl/android/maven2/com/android/tools/build/gradle/" \
              "8.0.0/gradle-8.0.0.jar"
        expect(result(url)).to be_nil
      end
    end

    context "with a CRAN URL" do
      it "parses name and version from a src/contrib URL" do
        url = "https://cran.r-project.org/src/contrib/data.table_1.15.4.tar.gz"
        expect(result(url)).to eq(ecosystem: "CRAN", name: "data.table", version: "1.15.4",
                                  purl: "pkg:cran/data.table@1.15.4")
      end

      it "parses an Archive/ URL" do
        url = "https://cran.r-project.org/src/contrib/Archive/rlang/rlang_1.1.3.tar.gz"
        expect(result(url)).to eq(ecosystem: "CRAN", name: "rlang", version: "1.1.3",
                                  purl: "pkg:cran/rlang@1.1.3")
      end

      it "parses a cloud.r-project.org URL" do
        url = "https://cloud.r-project.org/src/contrib/IRkernel_1.3.2.tar.gz"
        expect(result(url)).to eq(ecosystem: "CRAN", name: "IRkernel", version: "1.3.2",
                                  purl: "pkg:cran/IRkernel@1.3.2")
      end
    end

    context "with a NuGet URL" do
      it "parses a v3 flatcontainer URL" do
        url = "https://api.nuget.org/v3-flatcontainer/newtonsoft.json/13.0.3/" \
              "newtonsoft.json.13.0.3.nupkg"
        expect(result(url)).to eq(ecosystem: "NuGet", name: "newtonsoft.json", version: "13.0.3",
                                  purl: "pkg:nuget/newtonsoft.json@13.0.3")
      end

      it "parses a v2 API URL" do
        url = "https://www.nuget.org/api/v2/package/Newtonsoft.Json/13.0.3"
        expect(result(url)).to eq(ecosystem: "NuGet", name: "Newtonsoft.Json", version: "13.0.3",
                                  purl: "pkg:nuget/Newtonsoft.Json@13.0.3")
      end
    end

    it "returns nil for a non-registry URL" do
      expect(result("https://example.com/foo-1.0.tar.gz")).to be_nil
    end

    it "returns nil for a supported forge URL" do
      expect(result("https://github.com/nektos/act/archive/refs/tags/v0.2.84.tar.gz")).to be_nil
    end

    it "returns nil for nil input" do
      expect(result(nil)).to be_nil
    end
  end

  describe ".registry_package_for" do
    it "round-trips every source-derived registry ecosystem supported by overrides" do
      urls = [
        "https://files.pythonhosted.org/packages/00/2a/e8/jmespath-1.0.1.tar.gz",
        "https://registry.npmjs.org/@angular/cli/-/cli-22.0.3.tgz",
        "https://static.crates.io/crates/cargo-llvm-cov/cargo-llvm-cov-0.8.7.crate",
        "https://rubygems.org/downloads/activesupport-8.1.1.gem",
        "https://hackage.haskell.org/package/Allure-0.11.0.0/Allure-0.11.0.0.tar.gz",
        "https://repo.hex.pm/tarballs/phoenix-1.7.0-rc.0.tar",
        "https://cpan.metacpan.org/authors/id/A/AB/ABIGAIL/Regexp-Common-2024080801.tar.gz",
        "https://repo.maven.apache.org/maven2/com/github/spotbugs/spotbugs/4.10.2/spotbugs-4.10.2.tgz",
        "https://cran.r-project.org/src/contrib/data.table_1.15.4.tar.gz",
        "https://api.nuget.org/v3-flatcontainer/newtonsoft.json/13.0.3/newtonsoft.json.13.0.3.nupkg",
      ]

      round_tripped = urls.map do |url|
        package = described_class.registry_package(url)
        next false if package.nil?

        rebuilt = described_class.registry_package_for(
          ecosystem: package.ecosystem,
          name:      package.name,
          version:   package.version,
        )
        # `purl` is excluded because CPAN purls carry the author as a
        # namespace, which an OSV `ecosystem`/`name` identity cannot supply.
        rebuilt&.to_h&.slice(:ecosystem, :name, :version) == package.to_h.slice(:ecosystem, :name, :version)
      end

      expect(round_tripped).to all(be(true))
    end

    it "builds a canonical scoped npm package from an OSV identity" do
      package = described_class.registry_package_for(ecosystem: "npm", name: "@babel/core", version: "7.0.0")

      expect(package&.to_h).to eq(
        ecosystem: "npm",
        name:      "@babel/core",
        version:   "7.0.0",
        purl:      "pkg:npm/%40babel/core@7.0.0",
      )
    end

    it "builds a canonical Maven package from an OSV identity" do
      package = described_class.registry_package_for(
        ecosystem: "Maven", name: "com.github.spotbugs:spotbugs", version: "4.10.2",
      )

      expect(package&.purl).to eq "pkg:maven/com.github.spotbugs/spotbugs@4.10.2"
    end

    it "rejects an unsupported OSV ecosystem" do
      expect(described_class.registry_package_for(ecosystem: "GIT", name: "example", version: "1.0")).to be_nil
    end

    it "rejects non-canonical registry package names" do
      invalid = [
        { ecosystem: "PyPI", name: "Foo_Bar" },
        { ecosystem: "Hex", name: "Foo" },
        { ecosystem: "npm", name: "foo/bar" },
        { ecosystem: "Maven", name: "spotbugs" },
      ]

      expect(invalid).to all(satisfy do |package|
        described_class.registry_package_for(**package, version: "1.0").nil?
      end)
    end
  end
end
