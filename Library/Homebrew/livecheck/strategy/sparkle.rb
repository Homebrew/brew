# typed: strict
# frozen_string_literal: true

require "bundle_version"
require "livecheck/strategic"

module Homebrew
  module Livecheck
    module Strategy
      # The {Sparkle} strategy fetches content at a URL and parses it as a
      # Sparkle appcast in XML format.
      #
      # This strategy is not applied automatically and it's necessary to use
      # `strategy :sparkle` in a `livecheck` block to apply it.
      class Sparkle
        extend Strategic

        # A priority of zero causes livecheck to skip the strategy. We do this
        # for {Sparkle} so we can selectively apply it when appropriate.
        PRIORITY = 0

        # The `Regexp` used to determine if the strategy applies to the URL.
        URL_MATCH_REGEX = %r{^https?://}i

        # Common `os` values used in appcasts to refer to macOS.
        APPCAST_MACOS_STRINGS = T.let(["macos", "osx"].freeze, T::Array[String])

        # Whether the strategy can be applied to the provided URL.
        #
        # @param url [String] the URL to match against
        # @return [Boolean]
        sig { override.params(url: String).returns(T::Boolean) }
        def self.match?(url)
          URL_MATCH_REGEX.match?(url)
        end

        Item = Struct.new(
          # @api public
          :title,
          # @api public
          :link,
          # @api public
          :channel,
          # @api public
          :release_notes_link,
          # @api public
          :pub_date,
          # @api public
          :os,
          # @api public
          :url,
          # @api private
          :bundle_version,
          # @api public
          :minimum_system_version,
          keyword_init: true,
        ) do
          extend Forwardable

          # @!attribute [r] version
          # @api public
          delegate version: :bundle_version

          # @!attribute [r] short_version
          # @api public
          delegate short_version: :bundle_version

          # @!attribute [r] nice_version
          # @api public
          delegate nice_version: :bundle_version
        end

        # Identifies version information from a Sparkle appcast.
        #
        # @param content [String] the text of the Sparkle appcast
        # @return [Item, nil]
        sig { params(content: String).returns(T::Array[Item]) }
        def self.items_from_content(content)
          require "rexml/document"
          xml = Xml.parse_xml(content)
          return [] if xml.blank?

          # Remove prefixes, so we can reliably identify elements and attributes
          xml.root&.each_recursive do |node|
            node.prefix = ""
            node.attributes.each_attribute do |attribute|
              attribute.prefix = ""
            end
          end

          xml.get_elements("//rss//channel//item").filter_map do |item|
            enclosure = item.elements["enclosure"]

            if enclosure
              url = enclosure["url"].presence
              short_version = enclosure["shortVersionString"].presence
              version = enclosure["version"].presence
              os = enclosure["os"].presence
            end

            title = Xml.element_text(item, "title")
            link = Xml.element_text(item, "link")
            url ||= link
            channel = Xml.element_text(item, "channel")
            release_notes_link = Xml.element_text(item, "releaseNotesLink")
            short_version ||= Xml.element_text(item, "shortVersionString")
            version ||= Xml.element_text(item, "version")

            minimum_system_version_text =
              Xml.element_text(item, "minimumSystemVersion")&.gsub(/\A\D+|\D+\z/, "")
            if minimum_system_version_text.present?
              minimum_system_version = begin
                MacOSVersion.new(minimum_system_version_text)
              rescue MacOSVersion::Error
                nil
              end
            end

            pub_date = Xml.element_text(item, "pubDate")&.then do |date_string|
              Time.parse(date_string)
            rescue ArgumentError
              # Omit unparsable strings (e.g. non-English dates)
              nil
            end

            if (match = title&.match(/(\d+(?:\.\d+)*)\s*(\([^)]+\))?\Z/))
              short_version ||= match[1]
              version ||= match[2]
            end

            bundle_version = BundleVersion.new(short_version, version) if short_version || version

            data = {
              title:,
              link:,
              channel:,
              release_notes_link:,
              pub_date:,
              os:,
              url:,
              bundle_version:,
              minimum_system_version:,
            }.compact
            next if data.empty?

            # Set a default `pub_date` (for sorting) if one isn't provided
            data[:pub_date] ||= Time.new(0)

            Item.new(**data)
          end
        end

        # Filters out items that aren't suitable for Homebrew.
        #
        # @param items [Array] appcast items
        # @return [Array]
        sig { params(items: T::Array[Item]).returns(T::Array[Item]) }
        def self.filter_items(items)
          items.select do |item|
            # Omit items with an explicit `os` value that isn't macOS
            next false if item.os && APPCAST_MACOS_STRINGS.none?(item.os)

            # Omit items for prerelease macOS versions
            next false if item.minimum_system_version&.strip_patch&.prerelease?

            true
          end.compact
        end

        # Sorts items from newest to oldest.
        #
        # @param items [Array] appcast items
        # @return [Array]
        sig { params(items: T::Array[Item]).returns(T::Array[Item]) }
        def self.sort_items(items)
          items.sort_by { |item| [item.pub_date, item.bundle_version] }
               .reverse
        end

        # Uses `#items_from_content` to identify versions from the Sparkle
        # appcast content or, if a block is provided, passes the content to
        # the block to handle matching.
        #
        # @param content [String] the content to check
        # @param regex [Regexp, nil] a regex for use in a strategy block
        # @return [Array]
        sig {
          params(
            content: String,
            regex:   T.nilable(Regexp),
            block:   T.nilable(Proc),
          ).returns(T::Array[String])
        }
        def self.versions_from_content(content, regex = nil, &block)
          items = sort_items(filter_items(items_from_content(content)))
          return [] if items.blank?

          item = items.first

          if block
            block_return_value = case block.parameters[0]
            when [:opt, :item], [:rest], [:req]
              regex.present? ? yield(item, regex) : yield(item)
            when [:opt, :items]
              regex.present? ? yield(items, regex) : yield(items)
            else
              raise "First argument of Sparkle `strategy` block must be `item` or `items`"
            end
            return Strategy.handle_block_return(block_return_value)
          end

          version = T.must(item).bundle_version&.nice_version
          version.present? ? [version] : []
        end

        # Checks the content at the URL for new versions.
        #
        # @param url [String] the URL of the content to check
        # @param regex [Regexp, nil] a regex for use in a strategy block
        # @param options [Options] options to modify behavior
        # @return [Hash]
        sig {
          override(allow_incompatible: true).params(
            url:     String,
            regex:   T.nilable(Regexp),
            options: Options,
            block:   T.nilable(Proc),
          ).returns(T::Hash[Symbol, T.anything])
        }
        def self.find_versions(url:, regex: nil, options: Options.new, &block)
          if regex.present? && !block_given?
            raise ArgumentError,
                  "#{Utils.demodulize(name)} only supports a regex when using a `strategy` block"
          end

          match_data = { matches: {}, regex:, url: }

          match_data.merge!(Strategy.page_content(url, options:))
          content = match_data.delete(:content)
          return match_data if content.blank?

          versions_from_content(content, regex, &block).each do |version_text|
            match_data[:matches][version_text] = Version.new(version_text)
          end

          match_data
        end
      end
    end
  end
end
