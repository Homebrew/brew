# typed: strict
# frozen_string_literal: true

module Cask
  # List of casks which are not allowed in official taps.
  module Denylist
    sig { params(name: String).returns(T.nilable(String)) }
    def self.reason(name)
      case name
      when /^adobe-(after|illustrator|indesign|photoshop|premiere)/
        "Adobe casks were removed because they are too difficult to maintain."
      when /^pharo$/
        "Pharo developers maintain their own tap."
      end
    end
  end
end
