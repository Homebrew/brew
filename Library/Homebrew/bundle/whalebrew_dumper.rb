# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Homebrew
  module Bundle
    module WhalebrewDumper
      module_function

      def reset!
        @images = nil
      end

      def images
        return [] unless Bundle.whalebrew_installed?

        # odeprecated "`brew bundle` `whalebrew` support", "using `whalebrew` directly"
        @images ||= `whalebrew list 2>/dev/null`.split("\n")
                                                .reject { |line| line.start_with?("COMMAND ") }
                                                .map { |line| line.split(/\s+/).last }
                                                .uniq
      end

      def dump
        images.map { |image| "whalebrew \"#{image}\"" }.join("\n")
      end
    end
  end
end
