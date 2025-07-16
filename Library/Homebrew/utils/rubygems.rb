# typed: strict
# frozen_string_literal: true

require "utils/inreplace"

# Helper functions for updating RubyGems resources.
module RubyGems
  RUBYGEMS_URL_PREFIX = "https://rubygems.org/gems/"
  RUBYGEMS_DOWNLOADS_URL_PREFIX = "https://rubygems.org/downloads/"
  private_constant :RUBYGEMS_URL_PREFIX, :RUBYGEMS_DOWNLOADS_URL_PREFIX

  # Represents a Ruby gem from an existing resource.
  class Gem
    sig { params(resource_name: String, resource_url: String).void }
    def initialize(resource_name, resource_url)
      @rubygems_info = T.let(nil, T.nilable(T::Array[String]))
      @resource_name = resource_name
      @resource_url = resource_url
      @is_rubygems_url = T.let(
        resource_url.start_with?(RUBYGEMS_URL_PREFIX, RUBYGEMS_DOWNLOADS_URL_PREFIX),
        T::Boolean,
      )
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
    def valid_rubygems_gem?
      @is_rubygems_url
    end

    # Get latest release information from RubyGems API.
    sig { returns(T.nilable(T::Array[String])) }
    def latest_rubygems_info
      return @rubygems_info if @rubygems_info.present?
      return unless valid_rubygems_gem?

      api_url = "https://rubygems.org/api/v1/gems/#{@resource_name}.json"
      result = Utils::Curl.curl_output(api_url, "--location", "--fail")
      return unless result.status.success?

      begin
        json = JSON.parse(result.stdout)
      rescue JSON::ParserError
        return
      end

      version = json["version"]
      return unless version

      download_url = "https://rubygems.org/gems/#{@resource_name}-#{version}.gem"
      sha256 = json["sha"]
      return unless sha256

      @rubygems_info = [@resource_name, download_url, sha256, version]
    end

    sig { returns(String) }
    def to_s
      @resource_name
    end

    private

    sig { returns(T.nilable(String)) }
    def extract_version_from_url
      return unless @is_rubygems_url

      # Extract version from gem URL patterns:
      # https://rubygems.org/gems/gem-name-1.2.3.gem
      # https://rubygems.org/downloads/gem-name-1.2.3.gem
      match = File.basename(@resource_url).match(/^(.+)-([0-9.]+(?:\.[a-zA-Z0-9]+)*)\.gem$/)
      return unless match

      @current_version = T.let(match[2], T.nilable(String))
    end
  end

  # Update RubyGems resources in a formula.
  sig {
    params(
      formula:       Formula,
      print_only:    T.nilable(T::Boolean),
      silent:        T.nilable(T::Boolean),
      verbose:       T.nilable(T::Boolean),
      ignore_errors: T.nilable(T::Boolean),
    ).returns(T.nilable(T::Boolean))
  }
  def self.update_ruby_resources!(formula, print_only: false, silent: false, verbose: false, ignore_errors: false)
    rubygems_resources = formula.resources.select do |resource|
      resource.url.start_with?(RUBYGEMS_URL_PREFIX, RUBYGEMS_DOWNLOADS_URL_PREFIX)
    end

    odie "\"#{formula.name}\" has no RubyGems resources to update." if rubygems_resources.empty?

    show_info = !print_only && !silent

    non_rubygems_resources = formula.resources.reject do |resource|
      resource.url.start_with?(RUBYGEMS_URL_PREFIX, RUBYGEMS_DOWNLOADS_URL_PREFIX)
    end
    if non_rubygems_resources.any? && show_info
      ohai "Skipping #{non_rubygems_resources.length} non-RubyGems resources"
    end
    ohai "Found #{rubygems_resources.length} RubyGems resources to update" if show_info

    new_resource_blocks = ""
    gem_errors = ""
    updated_count = 0

    rubygems_resources.each do |resource|
      gem = Gem.new(resource.name, resource.url)

      unless gem.valid_rubygems_gem?
        if ignore_errors
          gem_errors += "  # RESOURCE-ERROR: \"#{resource.name}\" is not a valid RubyGems resource\n"
          next
        else
          odie "\"#{resource.name}\" is not a valid RubyGems resource"
        end
      end

      ohai "Checking \"#{resource.name}\" for updates..." if show_info

      info = gem.latest_rubygems_info

      unless info
        if ignore_errors
          gem_errors += "  # RESOURCE-ERROR: Unable to resolve \"#{resource.name}\"\n"
          next
        else
          odie "Unable to resolve \"#{resource.name}\""
        end
      end

      name, url, checksum, new_version = info
      current_version = gem.current_version

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

    gem_errors += "\n" if gem_errors.present?
    resource_section = "#{gem_errors}#{new_resource_blocks}"

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
      if T.must(s.inreplace_string.split(/^  test do\b/, 2).first).scan(inreplace_regex).length > 1
        odie "Unable to update resource blocks for \"#{formula.name}\" automatically. Please update them manually."
      end
      s.sub! inreplace_regex, resource_section
    end

    if gem_errors.present?
      ofail "Unable to resolve some dependencies. Please check #{formula.path} for RESOURCE-ERROR comments."
    elsif updated_count.positive?
      ohai "Updated #{updated_count} RubyGems resource#{"s" if updated_count != 1}" unless silent
    end

    true
  end
end
