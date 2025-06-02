# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "utils/svn"

module DinrusBrew
  # Auditor for checking common violations in {Resource}s.
  class ResourceAuditor
    include Utils::Curl

    attr_reader :name, :version, :checksum, :url, :mirrors, :using, :specs, :owner, :spec_name, :problems

    def initialize(resource, spec_name, options = {})
      @name     = resource.name
      @version  = resource.version
      @checksum = resource.checksum
      @url      = resource.url
      @mirrors  = resource.mirrors
      @using    = resource.using
      @specs    = resource.specs
      @owner    = resource.owner
      @spec_name = spec_name
      @online    = options[:online]
      @strict    = options[:strict]
      @only      = options[:only]
      @except    = options[:except]
      @use_homebrew_curl = options[:use_homebrew_curl]
      @problems = []
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

      self
    end

    def audit_version
      if version.nil?
        problem "отсутствует версия"
      elsif owner.is_a?(Formula) && !version.to_s.match?(GitHubPackages::VALID_OCI_TAG_REGEX) &&
            (owner.core_formula? ||
            (owner.bottle_defined? && GitHubPackages::URL_REGEX.match?(owner.bottle_specification.root_url)))
        problem "версия #{version} не соответствует #{GitHubPackages::VALID_OCI_TAG_REGEX.source}"
      elsif !version.detected_from_url?
        version_text = version
        version_url = Version.detect(url, **specs)
        if version_url.to_s == version_text.to_s && version.instance_of?(Version)
          problem "версия #{version_text} повтряется в версии, отсканированной с URL"
        end
      end
    end

    def audit_download_strategy
      url_strategy = DownloadStrategyDetector.detect(url)

      if (using == :git || url_strategy == GitDownloadStrategy) && specs[:tag] && !specs[:revision]
        problem "Git должен указать :revision, если указан :tag."
      end

      return unless using

      if using == :cvs
        mod = specs[:module]

        problem "Повторение значения :module в URL" if mod == name

        if url.match?(%r{:[^/]+$})
          mod = url.split(":").last

          if mod == name
            problem "Повторно модуль CVS приставлен к URL"
          else
            problem "Укажите модуль CVS как `:module => \"#{mod}\"` вместо того, чтобы приставлять его к URL"
          end
        end
      end

      return if url_strategy != DownloadStrategyDetector.detect("", using)

      problem "Повторение значения :using в URL"
    end

    def audit_checksum
      return if spec_name == :head
      # This condition is non-invertible.
      # rubocop:disable Style/InvertibleUnlessCondition
      return unless DownloadStrategyDetector.detect(url, using) <= CurlDownloadStrategy
      # rubocop:enable Style/InvertibleUnlessCondition

      problem "Отсутствует контрольная сумма" if checksum.blank?
    end

    def self.curl_deps
      @curl_deps ||= begin
        ["curl"] + Formula["curl"].recursive_dependencies.map(&:name).uniq
      rescue FormulaUnavailableError
        []
      end
    end

    def audit_resource_name_matches_pypi_package_name_in_url
      return unless url.match?(%r{^https?://files\.pythonhosted\.org/packages/})
      return if name == owner.name # Skip the top-level package name as we only care about `resource "foo"` blocks.

      if url.end_with? ".whl"
        path = URI(url).path
        return unless path.present?

        pypi_package_name, = File.basename(path).split("-", 2)
      else
        url =~ %r{/(?<package_name>[^/]+)-}
        pypi_package_name = Regexp.last_match(:package_name).to_s
      end

      T.must(pypi_package_name).gsub!(/[_.]/, "-")

      return if name.casecmp(pypi_package_name).zero?

      problem "имя ресурса должно быть `#{pypi_package_name}`, чтобы соответствовать имени пакета PyPI"
    end

    def audit_urls
      urls = [url] + mirrors

      curl_dep = self.class.curl_deps.include?(owner.name)
      # Ideally `ca-certificates` would not be excluded here, but sourcing a HTTP mirror was tricky.
      # Instead, we have logic elsewhere to pass `--insecure` to curl when downloading the certs.
      # TODO: try remove the OS/env conditional
      if DinrusBrew::SimulateSystem.simulating_or_running_on_macos? && spec_name == :stable &&
         owner.name != "ca-certificates" && curl_dep && !urls.find { |u| u.start_with?("http://") }
        problem "нужно всегда включать хотя бы одно зеркало HTTP"
      end

      return unless @online

      urls.each do |url|
        next if !@strict && mirrors.include?(url)

        strategy = DownloadStrategyDetector.detect(url, using)
        if strategy <= CurlDownloadStrategy && !url.start_with?("file")

          raise HomebrewCurlDownloadStrategyError, url if
            strategy <= HomebrewCurlDownloadStrategy && !Formula["curl"].any_version_installed?

          if (http_content_problem = curl_check_http_content(
            url,
            "URL-источник",
            specs:,
            use_homebrew_curl: @use_homebrew_curl,
          ))
            problem http_content_problem
          end
        elsif strategy <= GitDownloadStrategy
          attempts = 0
          remote_exists = T.let(false, T::Boolean)
          while !remote_exists && attempts < DinrusBrew::EnvConfig.curl_retries.to_i
            remote_exists = Utils::Git.remote_exists?(url)
            attempts += 1
          end
          problem "URL #{url} неполноценный git URL" unless remote_exists
        elsif strategy <= SubversionDownloadStrategy
          next unless DevelopmentTools.subversion_handles_most_https_certificates?
          next unless Utils::Svn.available?

          problem "URL #{url} неполноценный svn URL" unless Utils::Svn.remote_exists? url
        end
      end
    end

    def audit_head_branch
      return unless @online
      return unless @strict
      return if spec_name != :head
      return unless Utils::Git.remote_exists?(url)
      return if specs[:tag].present?
      return if specs[:revision].present?

      branch = Utils.popen_read("git", "ls-remote", "--symref", url, "HEAD")
                    .match(%r{ref: refs/heads/(.*?)\s+HEAD})&.to_a&.second
      return if branch.blank? || branch == specs[:branch]

      problem "Используйте `branch: \"#{branch}\", чтобы указать дефолтную ветвь"
    end

    def problem(text)
      @problems << text
    end
  end
end
