# typed: strict
# frozen_string_literal: true

require "utils/svn"

module Homebrew
  # Auditor for checking common violations in {Resource}s.
  class ResourceAuditor
    include Utils::Curl

    sig { returns(T.nilable(String)) }
    attr_reader :name

    sig { returns(T.nilable(Version)) }
    attr_reader :version

    sig { returns(T.nilable(Checksum)) }
    attr_reader :checksum

    sig { returns(T.nilable(String)) }
    attr_reader :url

    sig { returns(T::Array[String]) }
    attr_reader :mirrors

    sig { returns(T.nilable(T.any(T::Class[AbstractDownloadStrategy], Symbol))) }
    attr_reader :using

    sig { returns(T::Hash[Symbol, T.untyped]) }
    attr_reader :specs

    sig { returns(T.nilable(Resource::Owner)) }
    attr_reader :owner

    sig { returns(Symbol) }
    attr_reader :spec_name

    sig { returns(T::Array[String]) }
    attr_reader :problems

    sig {
      params(
        resource:          T.any(Resource, SoftwareSpec),
        spec_name:         Symbol,
        online:            T.nilable(T::Boolean),
        strict:            T.nilable(T::Boolean),
        only:              T.nilable(T::Array[String]),
        except:            T.nilable(T::Array[String]),
        core_tap:          T.nilable(T::Boolean),
        use_homebrew_curl: T::Boolean,
      ).void
    }
    def initialize(resource, spec_name, online: nil, strict: nil, only: nil, except: nil, core_tap: nil,
                   use_homebrew_curl: false)
      @name     = T.let(resource.name, T.nilable(String))
      @version  = T.let(resource.version, T.nilable(Version))
      @checksum = T.let(resource.checksum, T.nilable(Checksum))
      @url      = T.let(resource.url&.to_s, T.nilable(String))
      @mirrors  = T.let(resource.mirrors, T::Array[String])
      @using    = T.let(resource.using, T.nilable(T.any(T::Class[AbstractDownloadStrategy], Symbol)))
      @specs    = T.let(resource.specs, T::Hash[Symbol, T.untyped])
      @owner    = T.let(resource.owner, T.nilable(T.any(Cask::Cask, Resource::Owner)))
      @spec_name = T.let(spec_name, Symbol)
      @online    = online
      @strict    = strict
      @only      = only
      @except    = except
      @core_tap  = core_tap
      @use_homebrew_curl = use_homebrew_curl
      @problems = T.let([], T::Array[String])
    end

    sig { returns(ResourceAuditor) }
    def audit
      only_audits = @only
      except_audits = @except

      methods.map(&:to_s).grep(/^audit_/).each do |audit_method_name|
        name = audit_method_name.delete_prefix("audit_")
        next if only_audits&.exclude?(name)
        next if except_audits&.include?(name)

        send(audit_method_name)
      end

      self
    end

    sig { void }
    def audit_version
      if (version_text = version).nil?
        problem "Missing version"
      elsif (formula_owner = owner).is_a?(::Formula) &&
            !version_text.to_s.match?(GitHubPackages::VALID_OCI_TAG_REGEX) &&
            (formula_owner.core_formula? ||
            (formula_owner.bottle_defined? &&
              GitHubPackages::URL_REGEX.match?(formula_owner.bottle_specification.root_url)))
        problem "`version #{version}` does not match #{GitHubPackages::VALID_OCI_TAG_REGEX.source}"
      elsif !version_text.detected_from_url?
        version_url = Version.detect(url!, **specs)
        if version_url.to_s == version_text.to_s && version.instance_of?(Version)
          problem "`version #{version_text}` is redundant with version scanned from URL"
        end
      end
    end

    sig { void }
    def audit_download_strategy
      url_strategy = DownloadStrategyDetector.detect(url!)

      if (using == :git || url_strategy == GitDownloadStrategy) && specs[:tag] && !specs[:revision]
        problem "Git should specify `revision:` when a `tag:` is specified."
      end

      return unless using

      if using == :cvs
        mod = specs[:module]

        problem "Redundant `module:` value in URL" if mod == name

        if url!.match?(%r{:[^/]+$})
          mod = url!.split(":").last

          if mod == name
            problem "Redundant CVS module appended to URL"
          else
            problem "Specify CVS module as `module: \"#{mod}\"` instead of appending it to the URL"
          end
        end
      end

      return if url_strategy != DownloadStrategyDetector.detect("", using)

      problem "Redundant `using:` value in URL"
    end

    sig { void }
    def audit_checksum
      return if spec_name == :head
      # This condition is non-invertible.
      # rubocop:disable Style/InvertibleUnlessCondition
      return unless DownloadStrategyDetector.detect(url.to_s, using) <= CurlDownloadStrategy
      # rubocop:enable Style/InvertibleUnlessCondition

      problem "Checksum is missing" if checksum.blank?
    end

    sig { returns(T::Array[String]) }
    def self.curl_deps
      @curl_deps ||= T.let(begin
        ["curl"] + ::Formula["curl"].recursive_dependencies.map(&:name).uniq
      rescue FormulaUnavailableError
        []
      end, T.nilable(T::Array[String]))
    end

    sig { void }
    def audit_resource_name_matches_pypi_package_name_in_url
      return unless url!.match?(%r{^https?://files\.pythonhosted\.org/packages/})
      # Skip the top-level package name as we only care about `resource "foo"` blocks.
      return if name == owner!.name

      if url!.end_with? ".whl"
        path = URI(url!).path
        return unless path.present?

        pypi_package_name, = File.basename(path).split("-", 2)
      else
        url =~ %r{/(?<package_name>[^/]+)-}
        pypi_package_name = Regexp.last_match(:package_name).to_s
      end

      T.must(pypi_package_name).gsub!(/[_.]/, "-")

      return if name.to_s.casecmp(pypi_package_name.to_s)&.zero?

      problem "`resource` name should be '#{pypi_package_name}' to match the PyPI package name"
    end

    sig { void }
    def audit_urls
      urls = [url.to_s] + mirrors

      curl_dep = self.class.curl_deps.include?(owner!.name)
      # Ideally `ca-certificates` would not be excluded here, but sourcing a HTTP mirror was tricky.
      # Instead, we have logic elsewhere to pass `--insecure` to curl when downloading the certs.
      # TODO: try remove the OS/env conditional
      if Homebrew::SimulateSystem.simulating_or_running_on_macos? && spec_name == :stable &&
         owner!.name != "ca-certificates" && curl_dep && !urls.find { |u| u.start_with?("http://") }
        problem "Should always include at least one HTTP mirror"
      end

      return unless @online

      urls.each do |url|
        next if !@strict && mirrors.include?(url)

        strategy = DownloadStrategyDetector.detect(url, using)
        if strategy <= CurlDownloadStrategy && !url.start_with?("file")

          raise HomebrewCurlDownloadStrategyError, url if
            strategy <= HomebrewCurlDownloadStrategy && !::Formula["curl"].any_version_installed?

          # Skip ftp.gnu.org audit, upstream has asked us to reduce load.
          # See issue: https://github.com/Homebrew/brew/issues/20456
          next if url.match?(%r{^https?://ftp\.gnu\.org/.+})

          # Skip https audit for curl dependencies
          if !curl_dep && (http_content_problem = curl_check_http_content(
            url,
            "source URL",
            specs:,
            use_homebrew_curl: @use_homebrew_curl,
          ))
            problem http_content_problem
          end
        elsif strategy <= GitDownloadStrategy
          attempts = 0
          remote_exists = T.let(false, T::Boolean)
          while !remote_exists && attempts < Homebrew::EnvConfig.curl_retries.to_i
            remote_exists = Utils::Git.remote_exists?(url)
            attempts += 1
          end
          problem "The URL #{url} is not a valid Git URL" unless remote_exists
        elsif strategy <= SubversionDownloadStrategy
          next unless Utils::Svn.available?

          problem "The URL #{url} is not a valid SVN URL" unless Utils::Svn.remote_exists? url
        end
      end
    end

    sig { void }
    def audit_head_branch
      return unless @online
      return if spec_name != :head
      return if specs[:tag].present?
      return if specs[:revision].present?
      # Skip `resource` URLs as they use SHAs instead of branch specifiers.
      return if name != owner!.name
      return unless url.to_s.end_with?(".git")
      return unless Utils::Git.remote_exists?(url.to_s)

      detected_branch = Utils.popen_read("git", "ls-remote", "--symref", url.to_s, "HEAD")
                             .match(%r{ref: refs/heads/(.*?)\s+HEAD})&.to_a&.second

      if specs[:branch].blank?
        problem "Git `head` URL must specify a branch name"
        return
      end

      return unless @core_tap
      return if specs[:branch] == detected_branch

      problem "To use a non-default HEAD branch, add the formula to `head_non_default_branch_allowlist.json`."
    end

    sig { params(text: String).void }
    def problem(text)
      @problems << text
    end

    private

    sig { returns(Resource::Owner) }
    def owner!
      owner || raise("ResourceAuditor owner is nil")
    end

    sig { returns(String) }
    def url!
      url || raise("ResourceAuditor URL is nil")
    end
  end
end
