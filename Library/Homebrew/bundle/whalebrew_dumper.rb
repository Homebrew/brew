# typed: strict
# frozen_string_literal: true

module Homebrew
  module Bundle
    module WhalebrewDumper
      sig { void }
      def self.reset!
        @images = T.let(nil, T.nilable(T::Array[String]))
      end

      sig { returns(T::Array[T.nilable(String)]) }
      def self.images
        return [] unless Bundle.whalebrew_installed?

        odeprecated "`brew bundle` `whalebrew` support", "using `whalebrew` directly"
        @images ||= T.let(
          `whalebrew list 2>/dev/null`.split("\n")
                                      .reject { |line| line.start_with?("COMMAND ") }
                                      .filter_map { |line| line.split(/\s+/).last }
                                      .uniq,
          T.nilable(T::Array[String]),
        )
      end

      sig { returns(String) }
      def self.dump
        images.map { |image| "whalebrew \"#{image}\"" }.join("\n")
      end
    end
  end
end
