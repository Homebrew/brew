# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require_relative "../extend/module"

# from https://github.com/lsegal/yard/issues/484#issuecomment-442586899
module Homebrew
  module YARD
    class DocstringParser < ::YARD::DocstringParser
      # Every `Object` has these methods.
      unless const_defined?(:OVERRIDABLE_METHODS, false)
        OVERRIDABLE_METHODS = [
          :hash, :inspect, :to_s,
          :<=>, :===, :!~, :eql?, :equal?, :!, :==, :!=
        ].freeze
        private_constant :OVERRIDABLE_METHODS
      end
      unless const_defined?(:SELF_EXPLANATORY_METHODS, false)
        SELF_EXPLANATORY_METHODS = [:to_yaml, :to_json, :to_str].freeze
        private_constant :SELF_EXPLANATORY_METHODS
      end

      sig { params(content: T.nilable(String)).returns(String) }
      def parse_content(content)
        # Convert plain text to tags.
        content = content&.gsub(/^\s*(TODO|FIXME):\s*/i, "@todo ")
        content = content&.gsub(/^\s*NOTE:\s*/i, "@note ")

        # Ignore non-documentation comments.
        content = content&.sub(/\A(typed|.*rubocop):.*/m, "")

        content = super

        source = handler&.statement&.source

        if object&.type == :method &&
           (match = source&.match(/\so(deprecated|disabled)\s+"((?:\\"|[^"])*)"(?:\s*,\s*"((?:\\"|[^"])*))?"/m))
          type = match[1]
          method = match[2]
          method = method.sub(/\#{self(\.class)?}/, object.namespace.to_s)
          replacement = match[3]
          replacement = replacement.sub(/\#{self(\.class)?}/, object.namespace.to_s)

          # Only match `odeprecated`/`odisabled` for this method.
          if method.match?(/(.|#|`)#{Regexp.escape(object.name.to_s)}`/)
            if (method_name = method[/\A`([^`]*)`\Z/, 1]) && (
              (method_name.count(".") + method_name.count("#")) <= 1
            )
              method_name = method_name.delete_prefix(object.namespace.to_s)
              method = (method_name.delete_prefix(".") == object.name(true).to_s) ? nil : "{#{method_name}}"
            end

            if replacement &&
               (replacement_method_name = replacement[/\A`([^`]*)`\Z/, 1]) && (
               (replacement_method_name.count(".") + replacement_method_name.count("#")) <= 1
             )
              replacement_method_name = replacement_method_name.delete_prefix(object.namespace.to_s)
              replacement = "{#{replacement_method_name}}"
            end

            if method && !method.include?('#{')
              description = "Calling #{method} is #{type}"
              description += ", use #{replacement} instead" if replacement && !replacement.include?('#{')
              description += "."
            elsif replacement && !replacement.include?('#{')
              description = "Use #{replacement} instead."
            else
              description = ""
            end

            tags << create_tag("deprecated", description)
          end
        end

        api = tags.find { |tag| tag.tag_name == "api" }&.text
        is_private = tags.any? { |tag| tag.tag_name == "private" }
        visibility = directives.find { |d| d.tag.tag_name == "visibility" }&.tag&.text

        # Hide `#hash`, `#inspect` and `#to_s`.
        if visibility.nil? && OVERRIDABLE_METHODS.include?(object&.name)
          create_directive("visibility", "private")
          visibility = "private"
        end

        # Mark everything as `@api private` by default.
        if api.nil? && !is_private
          tags << create_tag("api", "private")
          api = "private"
        end

        # Warn about undocumented non-private APIs.
        if handler && api && api != "private" && visibility != "private" &&
           content.chomp.empty? && !SELF_EXPLANATORY_METHODS.include?(object&.name)
          stmt = handler.statement
          log.warn "#{api.capitalize} API should be documented:\n  " \
                   "in `#{handler.parser.file}`:#{stmt.line}:\n\n#{stmt.show}\n"
        end

        content
      end
    end
  end
end

YARD::Docstring.default_parser = Homebrew::YARD::DocstringParser
