# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "kramdown/converter/kramdown"

module Homebrew
  module Manpages
    module Converter
      # Converts our Kramdown-like input to pure Kramdown.
      class Kramdown < ::Kramdown::Converter::Kramdown
        def initialize(root, options)
          super(root, options.merge(line_width: 80))
        end

        def convert_variable(element, _options)
          "*`#{element.value}`*"
        end

        def convert_a(element, options)
          text = inner(element, options)
          if element.attr["href"] == text
            # Don't duplicate the URL if the link text is the same as the URL.
            "<#{text}>"
          else
            super
          end
        end
      end
    end
  end
end
