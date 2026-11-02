# typed: strict
# frozen_string_literal: true

require "livecheck/strategic"

module Homebrew
  module Livecheck
    module Strategy
      # The {Crate} strategy identifies versions of a Rust crate by checking
      # the information from the crates.io sparse index.
      #
      # Crate URLs have the following format:
      #   `https://static.crates.io/crates/example/example-1.2.3.crate`
      #
      # The default regex identifies versions like `1.2.3`/`v1.2.3` from the
      # version `vers` field. This is a common version format but a different
      # regex can be provided in a `livecheck` block to override the default
      # if a package uses a different format (e.g. `1.2.3d`, `1.2.3-4`, etc.).
      #
      # @api public
      class Crate
        extend Strategic

        # The default regex used to identify versions when a regex isn't
        # provided.
        DEFAULT_REGEX = /^v?(\d+(?:\.\d+)+)$/i

        # The default `strategy` block used to extract version information when
        # a `strategy` block isn't provided.
        DEFAULT_BLOCK = T.let(proc do |json, regex|
          next if json["yanked"]
          next unless (match = json["vers"]&.match(regex))

          match[1]
        end.freeze, T.proc.params(
          arg0: T::Hash[String, T.anything],
          arg1: Regexp,
        ).returns(T.any(String, T::Array[String])))

        # The `Regexp` used to determine if the strategy applies to the URL.
        URL_MATCH_REGEX = %r{
          ^https?://static\.crates\.io/crates
          /(?<package>[^/]+) # The name of the package
          /.+\.crate # The crate filename
        }ix

        # Whether the strategy can be applied to the provided URL.
        #
        # @param url [String] the URL to match against
        sig { override.params(url: String).returns(T::Boolean) }
        def self.match?(url)
          URL_MATCH_REGEX.match?(url)
        end

        # Extracts information from a provided URL and uses it to generate
        # various input values used by the strategy to check for new versions.
        #
        # @param url [String] the URL used to generate values
        sig { params(url: String).returns(T::Hash[Symbol, T.untyped]) }
        def self.generate_input_values(url)
          values = {}
          return values unless (match = url.match(URL_MATCH_REGEX))

          # https://doc.rust-lang.org/cargo/reference/registry-index.html#index-files
          package = match[:package].to_s.downcase
          directories = if package.length < 3
            package.length.to_s
          elsif package.length == 3
            "#{package.length}/#{package[0]}"
          else
            "#{package[0..1]}/#{package[2..3]}"
          end

          values[:url] = "https://index.crates.io/#{directories}/#{package}"

          values
        end

        # Generates a URL and checks the content at the URL for new versions
        # using {Json.versions_from_content}.
        #
        # @param url [String] the URL of the content to check
        # @param regex [Regexp, nil] a regex for matching versions in content
        # @param content [String, nil] content to check instead of fetching
        # @param options [Options] options to modify behavior
        # @return [Hash]
        sig {
          override.params(
            url:     String,
            regex:   T.nilable(Regexp),
            content: T.nilable(String),
            options: Options,
            block:   T.nilable(Proc),
          ).returns(T::Hash[Symbol, T.anything])
        }
        def self.find_versions(url:, regex: nil, content: nil, options: Options.new, &block)
          match_data = { matches: {}, regex:, url: }
          match_data[:cached] = true if content

          generated = generate_input_values(url)
          return match_data if generated.blank?

          match_data[:url] = generated[:url]

          unless match_data[:cached]
            match_data.merge!(Strategy.page_content(match_data[:url], options:))
            content = match_data[:content]
          end
          return match_data if content.blank?

          content.each_line do |line|
            Json.versions_from_content(line, regex || DEFAULT_REGEX, &block || DEFAULT_BLOCK).each do |match_text|
              match_data[:matches][match_text] = Version.new(match_text)
            end
          end

          match_data
        end
      end
    end
  end
end
