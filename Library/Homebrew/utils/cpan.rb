# typed: strict
# frozen_string_literal: true

require "utils/inreplace"
require "utils/output"

# Helper functions for updating CPAN resources.
module CPAN
  METACPAN_URL_PREFIX = "https://cpan.metacpan.org/authors/id/"
  CPAN_ARCHIVE_REGEX = /^(.+)-([0-9.v]+)\.(?:tar\.gz|tgz)$/
  private_constant :METACPAN_URL_PREFIX, :CPAN_ARCHIVE_REGEX

  extend Utils::Output::Mixin

  # Represents a Perl package from an existing resource.
  class Package
    sig { params(resource_name: String, resource_url: String).void }
    def initialize(resource_name, resource_url)
      @cpan_info = T.let(nil, T.nilable(T::Array[String]))
      @resource_name = resource_name
      @resource_url = resource_url
      @is_cpan_url = T.let(resource_url.start_with?(METACPAN_URL_PREFIX), T::Boolean)
    end

    sig { returns(String) }
    def name
      @resource_name
    end

    sig { returns(T.nilable(String)) }
    def current_version
      extract_version_from_url if @current_version.blank?
      @current_version
    end

    sig { returns(T::Boolean) }
    def valid_cpan_package?
      @is_cpan_url
    end

    # Get latest release information from MetaCPAN API.
    sig { returns(T.nilable(T::Array[String])) }
    def latest_cpan_info
      return @cpan_info if @cpan_info.present?
      return unless valid_cpan_package?

      metadata_url = "https://fastapi.metacpan.org/v1/download_url/#{@resource_name}"
      result = Utils::Curl.curl_output(metadata_url, "--location", "--fail")
      return unless result.status.success?

      begin
        json = JSON.parse(result.stdout)
      rescue JSON::ParserError
        return
      end

      download_url = json["download_url"]
      return unless download_url

      checksum = json["checksum_sha256"]
      return unless checksum

      @cpan_info = [@resource_name, download_url, checksum, json["version"]]
    end

    sig { returns(String) }
    def to_s
      @resource_name
    end

    private

    sig { returns(T.nilable(String)) }
    def extract_version_from_url
      return unless @is_cpan_url

      match = File.basename(@resource_url).match(CPAN_ARCHIVE_REGEX)
      return unless match

      @current_version = T.let(match[2], T.nilable(String))
    end
  end

  # Update CPAN resources in a formula.
  sig {
    params(
      formula:       Formula,
      print_only:    T.nilable(T::Boolean),
      silent:        T.nilable(T::Boolean),
      verbose:       T.nilable(T::Boolean),
      ignore_errors: T.nilable(T::Boolean),
    ).returns(T.nilable(T::Boolean))
  }
  def self.update_perl_resources!(formula, print_only: false, silent: false, verbose: false, ignore_errors: false)
    cpan_resources = formula.resources.select { |resource| resource.url.start_with?(METACPAN_URL_PREFIX) }

    odie "\"#{formula.name}\" has no CPAN resources to update." if cpan_resources.empty?

    show_info = !print_only && !silent

    non_cpan_resources = formula.resources.reject { |resource| resource.url.start_with?(METACPAN_URL_PREFIX) }
    ohai "Skipping #{non_cpan_resources.length} non-CPAN resources" if non_cpan_resources.any? && show_info
    ohai "Found #{cpan_resources.length} CPAN resources to update" if show_info

    new_resource_blocks = ""
    package_errors = ""
    updated_count = 0

    cpan_resources.each do |resource|
      package = Package.new(resource.name, resource.url)

      unless package.valid_cpan_package?
        if ignore_errors
          package_errors += "  # RESOURCE-ERROR: \"#{resource.name}\" is not a valid CPAN resource\n"
          next
        else
          odie "\"#{resource.name}\" is not a valid CPAN resource"
        end
      end

      ohai "Checking \"#{resource.name}\" for updates..." if show_info

      info = package.latest_cpan_info

      unless info
        if ignore_errors
          package_errors += "  # RESOURCE-ERROR: Unable to resolve \"#{resource.name}\"\n"
          next
        else
          odie "Unable to resolve \"#{resource.name}\""
        end
      end

      name, url, checksum, new_version = info
      current_version = package.current_version

      if current_version && new_version && current_version != new_version
        ohai "\"#{resource.name}\": #{current_version} -> #{new_version}" if show_info
        updated_count += 1
      elsif show_info
        ohai "\"#{resource.name}\": already up to date (#{current_version})" if current_version
      end

      new_resource_blocks += <<-EOS
  resource "#{name}" do
    url "#{url}"
    sha256 "#{checksum}"
  end

      EOS
    end

    package_errors += "\n" if package_errors.present?
    resource_section = "#{package_errors}#{new_resource_blocks}"

    if print_only
      puts resource_section.chomp
      return true
    end

    if formula.resources.all? { |resource| resource.name.start_with?("homebrew-") }
      inreplace_regex = /  def install/
      resource_section += "  def install"
    else
      inreplace_regex = /
        \ \ (
        (\#\ RESOURCE-ERROR:\ .*\s+)*
        resource\ .*\ do\s+
          url\ .*\s+
          sha256\ .*\s+
          ((\#.*\s+)*
          patch\ (.*\ )?do\s+
            url\ .*\s+
            sha256\ .*\s+
          end\s+)*
        end\s+)+
      /x
      resource_section += "  "
    end

    ohai "Updating resource blocks" unless silent
    Utils::Inreplace.inreplace formula.path do |s|
      if s.inreplace_string.split(/^  test do\b/, 2).fetch(0).scan(inreplace_regex).length > 1
        odie "Unable to update resource blocks for \"#{formula.name}\" automatically. Please update them manually."
      end
      s.sub! inreplace_regex, resource_section
    end

    if package_errors.present?
      ofail "Unable to resolve some dependencies. Please check #{formula.path} for RESOURCE-ERROR comments."
    elsif updated_count.positive?
      ohai "Updated #{updated_count} CPAN resource#{"s" if updated_count != 1}" unless silent
    end

    true
  end
end
