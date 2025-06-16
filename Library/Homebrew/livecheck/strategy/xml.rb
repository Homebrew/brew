# typed: strict
# frozen_string_literal: true

require "livecheck/strategic"

module Homebrew
  module Livecheck
    module Strategy
      # The {Xml} strategy fetches content at a URL, parses it as XML using
      # `REXML` and provides the `REXML::Document` to a `strategy` block.
      # If a regex is present in the `livecheck` block, it should be passed
      # as the second argument to the `strategy` block.
      #
      # This is a generic strategy that doesn't contain any logic for finding
      # versions, as the structure of XML data varies. Instead, a `strategy`
      # block must be used to extract version information from the XML data.
      # For more information on how to work with an `REXML::Document` object,
      # please refer to the [`REXML::Document`](https://ruby.github.io/rexml/REXML/Document.html)
      # and [`REXML::Element`](https://ruby.github.io/rexml/REXML/Element.html)
      # documentation.
      #
      # This strategy is not applied automatically and it is necessary to use
      # `strategy :xml` in a `livecheck` block (in conjunction with a
      # `strategy` block) to use it.
      #
      # This strategy's {find_versions} method can be used in other strategies
      # that work with XML content, so it should only be necessary to write
      # the version-finding logic that works with the parsed XML data.
      #
      # @api public
      class Xml
        extend Strategic

        NICE_NAME = "XML"

        # A priority of zero causes livecheck to skip the strategy. We do this
        # for {Xml} so we can selectively apply it only when a strategy block
        # is provided in a `livecheck` block.
        PRIORITY = 0

        # The `Regexp` used to determine if the strategy applies to the URL.
        URL_MATCH_REGEX = %r{^https?://}i

        # Whether the strategy can be applied to the provided URL.
        # {Xml} will technically match any HTTP URL but is only usable with
        # a `livecheck` block containing a `strategy` block.
        #
        # @param url [String] the URL to match against
        # @return [Boolean]
        sig { override.params(url: String).returns(T::Boolean) }
        def self.match?(url)
          URL_MATCH_REGEX.match?(url)
        end

        # Parses XML text and returns an `REXML::Document` object.
        # @param content [String] the XML text to parse
        # @return [REXML::Document, nil]
        sig { params(content: String).returns(T.nilable(REXML::Document)) }
        def self.parse_xml(content)
          parsing_tries = 0
          begin
            REXML::Document.new(content)
          rescue REXML::UndefinedNamespaceException => e
            undefined_prefix = e.to_s[/Undefined prefix ([^ ]+) found/i, 1]
            raise "Could not identify undefined prefix." if undefined_prefix.blank?

            # Only retry parsing once after removing prefix from content
            parsing_tries += 1
            raise "Could not parse XML after removing undefined prefix." if parsing_tries > 1

            # When an XML document contains a prefix without a corresponding
            # namespace, it's necessary to remove the prefix from the content
            # to be able to successfully parse it using REXML
            content = content.gsub(%r{(</?| )#{Regexp.escape(undefined_prefix)}:}, '\1')
            retry
          end
        end

        # Retrieves the stripped inner text of an `REXML` element. Returns
        # `nil` if the optional child element doesn't exist or the text is
        # blank.
        # @param element [REXML::Element] an `REXML` element to retrieve text
        #   from, either directly or from a child element
        # @param child_path [String, nil] the XPath of a child element to
        #   retrieve text from
        # @return [String, nil]
        sig {
          params(
            element:    REXML::Element,
            child_path: T.nilable(String),
          ).returns(T.nilable(String))
        }
        def self.element_text(element, child_path = nil)
          element = element.get_elements(child_path).first if child_path.present?
          return if element.nil?

          text = element.text
          return if text.blank?

          text.strip
        end

        # Parses XML text and identifies versions using a `strategy` block.
        # If a regex is provided, it will be passed as the second argument to
        # the  `strategy` block (after the parsed XML data).
        # @param content [String] the XML text to parse and check
        # @param regex [Regexp, nil] a regex used for matching versions in the
        #   content
        # @return [Array]
        sig {
          params(
            content: String,
            regex:   T.nilable(Regexp),
            block:   T.nilable(Proc),
          ).returns(T::Array[String])
        }
        def self.versions_from_content(content, regex = nil, &block)
          return [] if content.blank? || !block_given?

          require "rexml"
          xml = parse_xml(content)
          return [] if xml.blank?

          block_return_value = if regex.present?
            yield(xml, regex)
          elsif block.arity == 2
            raise "Two arguments found in `strategy` block but no regex provided."
          else
            yield(xml)
          end
          Strategy.handle_block_return(block_return_value)
        end

        # Checks the XML content at the URL for versions, using the provided
        # `strategy` block to extract version information.
        #
        # @param url [String] the URL of the content to check
        # @param regex [Regexp, nil] a regex used for matching versions
        # @param provided_content [String, nil] page content to use in place of
        #   fetching via `Strategy#page_content`
        # @param options [Options] options to modify behavior
        # @return [Hash]
        sig {
          override.params(
            url:              String,
            regex:            T.nilable(Regexp),
            provided_content: T.nilable(String),
            options:          Options,
            block:            T.nilable(Proc),
          ).returns(T::Hash[Symbol, T.anything])
        }
        def self.find_versions(url:, regex: nil, provided_content: nil, options: Options.new, &block)
          raise ArgumentError, "#{Utils.demodulize(name)} requires a `strategy` block" unless block_given?

          match_data = { matches: {}, regex:, url: }
          return match_data if url.blank?

          content = if provided_content.is_a?(String)
            match_data[:cached] = true
            provided_content
          else
            match_data.merge!(Strategy.page_content(url, options:))
            match_data[:content]
          end
          return match_data if content.blank?

          versions_from_content(content, regex, &block).each do |match_text|
            match_data[:matches][match_text] = Version.new(match_text)
          end

          match_data
        end
      end
    end
  end
end
