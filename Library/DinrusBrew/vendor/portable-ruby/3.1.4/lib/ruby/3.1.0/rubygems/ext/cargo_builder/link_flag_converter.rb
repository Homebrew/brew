# frozen_string_literal: true

class Gem::Ext::CargoBuilder < Gem::Ext::Builder
  # Converts Ruby link flags into something cargo understands
  class LinkFlagConverter
    def self.convert(arg)
      case arg.chomp
      when /^-L\s*(.+)$/
        ["-L", "native=#{$1}"]
      when /^--library=(\w+\S+)$/, /^-l\s*(\w+\S+)$/
        ["-l", $1]
      when /^-l\s*:lib(\S+).a$/
        ["-l", "static=#{$1}"]
      when /^-l\s*:lib(\S+).(so|dylib|dll)$/
        ["-l", "dylib=#{$1}"]
      when /^-F\s*(.*)$/
        ["-l", "framework=#{$1}"]
      else
        ["-C", "link_arg=#{arg}"]
      end
    end
  end
end
