# typed: true
# frozen_string_literal: true

module Bundle
  module Skipper
    class << self
      def macos_only_entry?(entry)
        [:cask, :mas].include?(entry.type)
      end

      def macos_only_tap?(entry)
        entry.type == :tap && entry.name == "homebrew/cask"
      end

      def skip?(entry, silent: false)
        if macos_only_entry?(entry) || macos_only_tap?(entry)
          puts Formatter.warning "Skipping #{entry.type} #{entry.name} (on Linux)" unless silent
          true
        else
          generic_skip?(entry)
        end
      end
    end
  end
end
