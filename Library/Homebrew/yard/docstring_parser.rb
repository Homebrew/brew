# typed: true
# frozen_string_literal: true

# from https://github.com/lsegal/yard/issues/484#issuecomment-442586899
module Homebrew
  module YARD
    class DocstringParser < ::YARD::DocstringParser
      def parse_content(content)
        # Ignore non-documentation comments.
        content = content&.sub(/(\A(typed|.*rubocop)|TODO|FIXME):.*/m, "")

        content = super(content)

        # Mark everything as `@api private` by default.
        visibility_tags = ["visibility", "api", "private"]
        tags << create_tag("api", "private") if tags.none? { |tag| visibility_tags.include?(tag.tag_name) }

        content
      end
    end
  end
end

YARD::Docstring.default_parser = Homebrew::YARD::DocstringParser
