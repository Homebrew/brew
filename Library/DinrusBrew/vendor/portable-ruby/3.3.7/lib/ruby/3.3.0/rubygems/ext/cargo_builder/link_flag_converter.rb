# frozen_string_literal: true

class Gem::Ext::CargoBuilder < Gem::Ext::Builder
  # Converts Ruby link flags into something cargo understands
  class LinkFlagConverter
    FILTERED_PATTERNS = [
      /compress-debug-sections/, # Not supported by all linkers, and not required for Rust
    ].freeze

    def self.convert(arg)
      return [] if FILTERED_PATTERNS.any? {|p| p.match?(arg) }

      case arg.chomp
      when /^-L\s*(.+)$/
        ["-L", "native=#{$1}"]
      when /^--library=(\w+\S+)$/, /^-l\s*(\w+\S+)$/
        ["-l", $1]
      when /^-l\s*([^:\s])+/ # -lfoo, but not -l:libfoo.a
        ["-l", $1]
      when /^-F\s*(.*)$/
        ["-l", "framework=#{$1}"]
      else
        ["-C", "link-args=#{arg}"]
      end
    end
  end
end
