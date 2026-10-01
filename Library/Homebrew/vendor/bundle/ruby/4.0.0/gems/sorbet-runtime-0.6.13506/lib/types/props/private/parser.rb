# frozen_string_literal: true
# typed: false

module T::Props
  module Private
    module Parse
      def parse(source)
        @current_ruby ||= require_parser(:CurrentRuby)
        @current_ruby.parse(source)
      end

      def s(type, *children)
        @node ||= require_parser(:AST, :Node)
        @node.new(type, children)
      end

      private def require_parser(*constants)
        # This is an optional dependency for sorbet-runtime in general,
        # but is required here
        require 'parser/current'

        # Hack to work around the static checker thinking the constant is
        # undefined
        cls = Kernel.const_get(:Parser, true)
        while (const = constants.shift)
          cls = cls.const_get(const, false)
        end
        cls
      end
    end
  end
end
