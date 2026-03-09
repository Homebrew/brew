# typed: strict
# frozen_string_literal: true

module Utils
  # Helper for normalizing commit message subjects.
  module CommitMessage
    # Normalizes a commit message subject to a consistent format:
    # - Ensures colon-space separator between name and action
    # - Removes trailing periods
    # - Strips leading/trailing whitespace
    # - Lowercases the action part (after the colon)
    sig { params(message: String).returns(String) }
    def self.normalize(message)
      message = message.strip
      message = message.delete_suffix(".")

      if message.include?(":")
        name, action = message.split(":", 2)
        "#{T.must(name).strip}: #{T.must(action).strip.downcase}"
      else
        message
      end
    end
  end
end
