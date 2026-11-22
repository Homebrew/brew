# typed: strict
# frozen_string_literal: true

require "date"

# Homepage metadata for formulae and casks.
module Homepage
  # The homepage URL and the date a human last checked that URL.
  module DSL
    extend T::Helpers

    requires_ancestor { Kernel }

    sig { returns(T.nilable(Date)) }
    attr_reader :homepage_browsed

    # Sets or reads the package homepage, which users can open with `brew home`.
    # `browsed` is the date a human last checked this URL in a browser.
    # Automated homepage availability audits are skipped for one year.
    #
    # ```ruby
    # homepage "https://www.example.com", browsed: "2026-07-26"
    # ```
    #
    # @api public
    sig { params(url: T.nilable(String), browsed: T.nilable(String)).returns(T.nilable(String)) }
    def homepage(url = nil, browsed: nil)
      if url.nil?
        raise ArgumentError, "`browsed` requires a homepage URL" if browsed

        return @homepage
      end

      if browsed
        @homepage_browsed = T.let(Date.parse(browsed), T.nilable(Date))
      elsif url != @homepage
        @homepage_browsed = nil
      end
      @homepage = T.let(url, T.nilable(String))
    end
  end
end
