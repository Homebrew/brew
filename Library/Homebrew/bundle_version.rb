# typed: true
# frozen_string_literal: true

require "system_command"

module Homebrew
  # Representation of a macOS bundle version, commonly found in `Info.plist` files.
  class BundleVersion
    include Comparable

    extend SystemCommand::Mixin

    sig { params(info_plist_path: Pathname).returns(T.nilable(T.attached_class)) }
    def self.from_info_plist(info_plist_path)
      plist = system_command!("plutil", args: ["-convert", "xml1", "-o", "-", info_plist_path]).plist
      from_info_plist_content(plist)
    end

    sig { params(plist: T::Hash[String, T.untyped]).returns(T.nilable(T.attached_class)) }
    def self.from_info_plist_content(plist)
      short_version = plist["CFBundleShortVersionString"].presence
      version = plist["CFBundleVersion"].presence

      new(short_version, version) if short_version || version
    end

    sig { params(package_info_path: Pathname).returns(T.nilable(T.attached_class)) }
    def self.from_package_info(package_info_path)
      require "rexml/document"

      xml = REXML::Document.new(package_info_path.read)

      bundle_version_bundle = xml.get_elements("//pkg-info//bundle-version//bundle").first
      bundle_id = bundle_version_bundle["id"] if bundle_version_bundle
      return if bundle_id.blank?

      bundle = xml.get_elements("//pkg-info//bundle").find { |b| b["id"] == bundle_id }
      return unless bundle

      short_version = bundle["CFBundleShortVersionString"]
      version = bundle["CFBundleVersion"]

      new(short_version, version) if short_version || version
    end

    sig { returns(T.nilable(String)) }
    attr_reader :short_version, :version

    sig { params(short_version: T.nilable(String), version: T.nilable(String)).void }
    def initialize(short_version, version)
      # Remove version from short version, if present.
      short_version = short_version&.sub(/\s*\(#{Regexp.escape(version)}\)\Z/, "") if version

      @short_version = short_version.presence
      @version = version.presence

      return if @short_version || @version

      raise ArgumentError, "`short_version` and `version` cannot both be `nil` or empty"
    end

    def <=>(other)
      return super unless instance_of?(other.class)

      make_version = ->(v) { v ? Version.new(v) : Version::NULL }

      version = self.version.then(&make_version)
      other_version = other.version.then(&make_version)

      difference = version <=> other_version

      # If `version` is equal or cannot be compared, compare `short_version` instead.
      if difference.nil? || difference.zero?
        short_version = self.short_version.then(&make_version)
        other_short_version = other.short_version.then(&make_version)

        return short_version <=> other_short_version
      end

      difference
    end

    def ==(other)
      instance_of?(other.class) && short_version == other.short_version && version == other.version
    end
    alias eql? ==

    # Create a nicely formatted version (on a best effort basis).
    sig { returns(String) }
    def nice_version
      nice_parts.join(",")
    end

    sig { returns(T::Array[String]) }
    def nice_parts
      short_version = self.short_version
      version = self.version

      return [T.must(short_version)] if short_version == version

      if short_version && version
        return [version] if version.match?(/\A\d+(\.\d+)+\Z/) && version.start_with?("#{short_version}.")
        return [short_version] if short_version.match?(/\A\d+(\.\d+)+\Z/) && short_version.start_with?("#{version}.")

        if short_version.match?(/\A\d+(\.\d+)*\Z/) && version.match?(/\A\d+\Z/)
          return [short_version] if short_version.start_with?("#{version}.") || short_version.end_with?(".#{version}")

          return [short_version, version]
        end
      end

      [short_version, version].compact
    end
    private :nice_parts
  end
end
