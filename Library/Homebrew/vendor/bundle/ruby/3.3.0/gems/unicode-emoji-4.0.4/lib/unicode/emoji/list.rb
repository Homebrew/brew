# frozen_string_literal: true

module Unicode
  module Emoji
    # Contains an ordered and group list of all currently recommended Emoji (RGI/FQE)
    LIST                          = INDEX[:LIST].freeze.each_value(&:freeze)

    # Sometimes, categories change, we issue a warning in these cases
    LIST_REMOVED_KEYS             = [
      "Smileys & People",
    ].freeze
  end
end
