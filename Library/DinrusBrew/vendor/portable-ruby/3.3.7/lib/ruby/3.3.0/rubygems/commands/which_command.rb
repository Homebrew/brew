# frozen_string_literal: true

require_relative "../command"

class Gem::Commands::WhichCommand < Gem::Command
  def initialize
    super "which", "Find the location of a library file you can require",
          search_gems_first: false, show_all: false

    add_option "-a", "--[no-]all", "show all matching files" do |show_all, options|
      options[:show_all] = show_all
    end

    add_option "-g", "--[no-]gems-first",
               "search gems before non-gems" do |gems_first, options|
      options[:search_gems_first] = gems_first
    end
  end

  def arguments # :nodoc:
    "FILE          name of file to find"
  end

  def defaults_str # :nodoc:
    "--no-gems-first --no-all"
  end

  def description # :nodoc:
    <<-EOF
The which command is like the shell which command and shows you where
the file you wish to require lives.

You can use the which command to help determine why you are requiring a
version you did not expect or to look at the content of a file you are
requiring to see why it does not behave as you expect.
    EOF
  end

  def execute
    found = true

    options[:args].each do |arg|
      arg = arg.sub(/#{Regexp.union(*Gem.suffixes)}$/, "")
      dirs = $LOAD_PATH

      spec = Gem::Specification.find_by_path arg

      if spec
        if options[:search_gems_first]
          dirs = spec.full_require_paths + $LOAD_PATH
        else
          dirs = $LOAD_PATH + spec.full_require_paths
        end
      end

      paths = find_paths arg, dirs

      if paths.empty?
        alert_error "Can't find Ruby library file or shared library #{arg}"
        found = false
      else
        say paths
      end
    end

    terminate_interaction 1 unless found
  end

  def find_paths(package_name, dirs)
    result = []

    dirs.each do |dir|
      Gem.suffixes.each do |ext|
        full_path = File.join dir, "#{package_name}#{ext}"
        if File.exist?(full_path) && !File.directory?(full_path)
          result << full_path
          return result unless options[:show_all]
        end
      end
    end

    result
  end

  def usage # :nodoc:
    "#{program_name} FILE [FILE ...]"
  end
end
