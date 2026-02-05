# typed: strict
# frozen_string_literal: true

require "bundle_version"
require "livecheck/strategic"
require "unversioned_cask_checker"

module Homebrew
  module Livecheck
    module Strategy
      # The {ExtractPlist} strategy downloads the file at a URL and extracts
      # versions from contained `.plist` files using {UnversionedCaskChecker}.
      #
      # In practice, this strategy operates by downloading very large files,
      # so it's both slow and data-intensive. As such, the {ExtractPlist}
      # strategy should only be used as an absolute last resort.
      #
      # This strategy is not applied automatically and it's necessary to use
      # `strategy :extract_plist` in a `livecheck` block to apply it.
      class ExtractPlist
        extend Strategic

        # A priority of zero causes livecheck to skip the strategy. We do this
        # for {ExtractPlist} so we can selectively apply it when appropriate.
        PRIORITY = 0

        # The `Regexp` used to determine if the strategy applies to the URL.
        URL_MATCH_REGEX = %r{^https?://}i

        Item = Struct.new(
          :bundle_version,
          keyword_init: true,
        ) do
          extend Forwardable

          # @!attribute [r] version
          # @api public
          delegate version: :bundle_version

          # @!attribute [r] short_version
          # @api public
          delegate short_version: :bundle_version

          sig { returns(T::Hash[Symbol, T::Hash[Symbol, String]]) }
          def to_h
            {
              bundle_version: bundle_version&.to_h,
            }.compact
          end
        end

        # Whether the strategy can be applied to the provided URL.
        #
        # @param url [String] the URL to match against
        # @return [Boolean]
        sig { override.params(url: String).returns(T::Boolean) }
        def self.match?(url)
          URL_MATCH_REGEX.match?(url)
        end

        # Identify versions from `Item`s produced using
        # {UnversionedCaskChecker} version information.
        #
        # @param items [Hash] a hash of `Item`s containing version information
        # @param regex [Regexp, nil] a regex for use in a strategy block
        # @return [Array]
        sig {
          params(
            items: T::Hash[String, Item],
            regex: T.nilable(Regexp),
            block: T.nilable(Proc),
          ).returns(T::Array[String])
        }
        def self.versions_from_content(items, regex = nil, &block)
          if block
            block_return_value = regex.present? ? yield(items, regex) : yield(items)
            return Strategy.handle_block_return(block_return_value)
          end

          items.filter_map do |_key, item|
            item.bundle_version.nice_version
          end.uniq
        end

        # Creates a copy of the cask with the artifact URL replaced by the
        # provided URL, using the provided `url_options`. This will error if
        # `url_options` contains any non-nil values with keys that aren't
        # found in the `Cask::URL.initialize` keyword parameters.
        # @param cask [Cask::Cask] the cask to copy and modify to use the
        #   provided URL and options
        # @param url [String] the replacement URL
        # @param url_options [Hash] options to use when replacing the URL
        # @return [Cask::Cask]
        sig {
          params(
            cask:        Cask::Cask,
            url:         String,
            url_options: T::Hash[Symbol, T.untyped],
          ).returns(Cask::Cask)
        }
        def self.cask_with_url(cask, url, url_options)
          # Collect the `Cask::URL` initializer keyword parameter symbols
          @cask_url_kw_params ||= T.let(
            T::Utils.signature_for_method(
              Cask::URL.instance_method(:initialize),
            ).parameters.filter_map { |type, sym| sym if type == :key },
            T.nilable(T::Array[Symbol]),
          )

          # Collect `livecheck` block URL options supported by `Cask::URL`
          unused_opts = []
          url_kwargs = url_options.select do |key, value|
            next if value.nil?

            unless @cask_url_kw_params.include?(key)
              unused_opts << key
              next
            end

            true
          end

          unless unused_opts.empty?
            raise ArgumentError,
                  "Cask `url` does not support `#{unused_opts.join("`, `")}` " \
                  "#{Utils.pluralize("option", unused_opts.length)} from " \
                  "`livecheck` block"
          end

          # Create a copy of the cask that overrides the artifact URL with the
          # provided URL and supported `livecheck` block URL options
          cask_copy = Cask::CaskLoader.load(cask.sourcefile_path)
          cask_copy.allow_reassignment = true
          cask_copy.url(url, **url_kwargs)
          cask_copy
        end

        # Uses {UnversionedCaskChecker} on the provided cask to identify
        # versions from `plist` files.
        #
        # @param cask [Cask::Cask] the cask to check for version information
        # @param url [String, nil] an alternative URL to check for version
        #   information
        # @param content [String, nil] content to check instead of fetching
        # @param regex [Regexp, nil] a regex for use in a strategy block
        # @param options [Options] options to modify behavior
        # @return [Hash]
        sig {
          override(allow_incompatible: true).params(
            cask:    Cask::Cask,
            url:     T.nilable(String),
            regex:   T.nilable(Regexp),
            content: T.nilable(String),
            options: Options,
            block:   T.nilable(Proc),
          ).returns(T::Hash[Symbol, T.anything])
        }
        def self.find_versions(cask:, url: nil, regex: nil, content: nil, options: Options.new, &block)
          if regex.present? && !block_given?
            raise ArgumentError,
                  "#{Utils.demodulize(name)} only supports a regex when using a `strategy` block"
          end

          match_data = { matches: {}, regex:, url: }
          match_data[:cached] = true if content

          if match_data[:cached]
            items = Json.parse_json(T.must(content)).transform_values do |obj|
              short_version = obj.dig("bundle_version", "short_version")
              version = obj.dig("bundle_version", "version")
              Item.new(bundle_version: BundleVersion.new(short_version, version))
            end
          else
            unversioned_cask_checker = if url.present? && url != cask.url.to_s
              UnversionedCaskChecker.new(cask_with_url(cask, url, options.url_options))
            else
              UnversionedCaskChecker.new(cask)
            end

            items = unversioned_cask_checker.all_versions.transform_values { |v| Item.new(bundle_version: v) }
          end
          return match_data if items.blank?

          versions_from_content(items, regex, &block).each do |version_text|
            match_data[:matches][version_text] = Version.new(version_text)
          end

          require "json"
          match_data[:content] = JSON.generate(items.transform_values(&:to_h)) unless match_data[:cached]
          match_data
        end
      end
    end
  end
end
