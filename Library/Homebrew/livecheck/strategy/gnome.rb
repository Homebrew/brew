# typed: true
# frozen_string_literal: true

module Homebrew
  module Livecheck
    module Strategy
      # The {Gnome} strategy identifies versions of software at gnome.org by
      # checking the available downloads found in a project's `cache.json`
      # file.
      #
      # GNOME URLs generally follow a standard format:
      #
      # * `https://download.gnome.org/sources/example/1.2/example-1.2.3.tar.xz`
      #
      # Before version 40, GNOME used a version scheme where unstable releases
      # were indicated with a minor that's 90+ or odd. The newer version scheme
      # uses trailing alpha/beta/rc text to identify unstable versions
      # (e.g. `40.alpha`).
      #
      # When a regex isn't provided in a `livecheck` block, the strategy uses
      # a default regex that matches versions which don't include trailing text
      # after the numeric version (e.g. `40.0` instead of `40.alpha`) and it
      # selectively filters out unstable versions below 40 using the rules for
      # the older version scheme.
      #
      # @api public
      class Gnome
        NICE_NAME = "GNOME"

        # The `Regexp` used to determine if the strategy applies to the URL.
        URL_MATCH_REGEX = %r{
          ^https?://download\.gnome\.org
          /sources
          /(?<package_name>[^/]+)/ # The GNOME package name
        }ix.freeze

        # Whether the strategy can be applied to the provided URL.
        #
        # @param url [String] the URL to match against
        # @return [Boolean]
        sig { params(url: String).returns(T::Boolean) }
        def self.match?(url)
          URL_MATCH_REGEX.match?(url)
        end

        # Extracts information from a provided URL and uses it to generate
        # various input values used by the strategy to check for new versions.
        # Some of these values act as defaults and can be overridden in a
        # `livecheck` block.
        #
        # @param url [String] the URL used to generate values
        # @return [Hash]
        sig { params(url: String).returns(T::Hash[Symbol, T.untyped]) }
        def self.generate_input_values(url)
          values = {}

          match = url.match(URL_MATCH_REGEX)
          return values if match.blank?

          values[:url] = "https://download.gnome.org/sources/#{match[:package_name]}/cache.json"

          regex_name = Regexp.escape(T.must(match[:package_name])).gsub("\\-", "-")

          # GNOME archive files seem to use a standard filename format, so we
          # count on the delimiter between the package name and numeric
          # version being a hyphen and the file being a tarball.
          values[:regex] = /#{regex_name}-(\d+(?:\.\d+)*)\.t/i

          values
        end

        # Generates a URL and regex (if one isn't provided) and passes them
        # to {PageMatch.find_versions} to identify versions in the content.
        #
        # @param url [String] the URL of the content to check
        # @param regex [Regexp] a regex used for matching versions in content
        # @return [Hash]
        sig {
          params(
            url:    String,
            regex:  T.nilable(Regexp),
            unused: T.nilable(T::Hash[Symbol, T.untyped]),
            block:  T.nilable(Proc),
          ).returns(T::Hash[Symbol, T.untyped])
        }
        def self.find_versions(url:, regex: nil, **unused, &block)
          generated = generate_input_values(url)

          version_data = PageMatch.find_versions(
            url:   generated[:url],
            regex: regex || generated[:regex],
            **unused,
            &block
          )

          if regex.blank?
            # Filter out unstable versions using the old version scheme where
            # the major version is below 40.
            version_data[:matches].reject! do |_, version|
              next if version.major >= 40
              next if version.minor.blank?

              (version.minor.to_i.odd? || version.minor >= 90) ||
                (version.patch.present? && version.patch >= 90)
            end
          end

          version_data
        end
      end
    end
  end
end
