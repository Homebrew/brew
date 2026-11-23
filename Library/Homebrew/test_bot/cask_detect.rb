# typed: strict
# frozen_string_literal: true

module Homebrew
  module TestBot
    # Finds changed casks in the tap revision range selected by test-bot.
    class CaskDetect < Test
      sig { params(start_revision: String, end_revision: String).returns(T::Array[String]) }
      def run!(start_revision, end_revision)
        return [] unless (cask_tap = tap)

        changed_files(start_revision, end_revision, cask_tap.cask_dir, "AMR").select do |file|
          cask_tap.cask_file?(file)
        end
      end
    end
  end
end
