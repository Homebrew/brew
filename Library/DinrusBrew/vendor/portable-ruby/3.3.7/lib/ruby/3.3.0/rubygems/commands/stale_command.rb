# frozen_string_literal: true

require_relative "../command"

class Gem::Commands::StaleCommand < Gem::Command
  def initialize
    super("stale", "List gems along with access times")
  end

  def description # :nodoc:
    <<-EOF
The stale command lists the latest access time for all the files in your
installed gems.

You can use this command to discover gems and gem versions you are no
longer using.
    EOF
  end

  def usage # :nodoc:
    program_name.to_s
  end

  def execute
    gem_to_atime = {}
    Gem::Specification.each do |spec|
      name = spec.full_name
      Dir["#{spec.full_gem_path}/**/*.*"].each do |file|
        next if File.directory?(file)
        stat = File.stat(file)
        gem_to_atime[name] ||= stat.atime
        gem_to_atime[name] = stat.atime if gem_to_atime[name] < stat.atime
      end
    end

    gem_to_atime.sort_by {|_, atime| atime }.each do |name, atime|
      say "#{name} at #{atime.strftime "%c"}"
    end
  end
end
