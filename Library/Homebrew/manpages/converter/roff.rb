# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "kramdown/converter/man"

module Homebrew
  module Manpages
    module Converter
      # Converts our Kramdown-like input to roff.
      class Roff < ::Kramdown::Converter::Man
        # Override that adds Homebrew metadata for the top level header
        # and doesn't escape the text inside subheaders.
        def convert_header(element, options)
          if element.options[:level] == 1
            element.attr["data-date"] = Date.today.strftime("%B %Y")
            element.attr["data-extra"] = "Homebrew"
            return super
          end

          result = +""
          inner(element, options.merge(result:))
          result.gsub!(" [", ' \fR[') # make args not bold

          options[:result] << if element.options[:level] == 2
            macro("SH", quote(result))
          else
            macro("SS", quote(result))
          end
        end

        def convert_variable(element, options)
          options[:result] << "\\fI#{escape(element.value)}\\fP"
        end

        def convert_a(element, options)
          if element.attr["href"].chr == "#"
            # Hide internal links - just make them italicised
            convert_em(element, options)
          else
            super
            # Remove the space after links if the next character is not a space
            if options[:result].end_with?(".UE\n") &&
               (next_element = options[:next]) &&
               next_element.type == :text &&
               next_element.value.chr.present? # i.e. not a space character
              options[:result].chomp!
              options[:result] << " "
            end
          end
        end
      end
    end
  end
end
