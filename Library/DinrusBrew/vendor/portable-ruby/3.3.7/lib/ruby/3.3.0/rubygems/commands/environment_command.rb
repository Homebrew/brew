# frozen_string_literal: true

require_relative "../command"

class Gem::Commands::EnvironmentCommand < Gem::Command
  def initialize
    super "environment", "Display information about the RubyGems environment"
  end

  def arguments # :nodoc:
    args = <<-EOF
          home            display the path where gems are installed. Aliases: gemhome, gemdir, GEM_HOME
          path            display path used to search for gems. Aliases: gempath, GEM_PATH
          user_gemhome    display the path where gems are installed when `--user-install` is given. Aliases: user_gemdir
          version         display the gem format version
          remotesources   display the remote gem servers
          platform        display the supported gem platforms
          <omitted>       display everything
    EOF
    args.gsub(/^\s+/, "")
  end

  def description # :nodoc:
    <<-EOF
The environment command lets you query rubygems for its configuration for
use in shell scripts or as a debugging aid.

The RubyGems environment can be controlled through command line arguments,
gemrc files, environment variables and built-in defaults.

Command line argument defaults and some RubyGems defaults can be set in a
~/.gemrc file for individual users and a gemrc in the SYSTEM CONFIGURATION
DIRECTORY for all users. These files are YAML files with the following YAML
keys:

  :sources: A YAML array of remote gem repositories to install gems from
  :verbose: Verbosity of the gem command. false, true, and :really are the
            levels
  :update_sources: Enable/disable automatic updating of repository metadata
  :backtrace: Print backtrace when RubyGems encounters an error
  :gempath: The paths in which to look for gems
  :disable_default_gem_server: Force specification of gem server host on push
  <gem_command>: A string containing arguments for the specified gem command

Example:

  :verbose: false
  install: --no-wrappers
  update: --no-wrappers
  :disable_default_gem_server: true

RubyGems' default local repository can be overridden with the GEM_PATH and
GEM_HOME environment variables. GEM_HOME sets the default repository to
install into. GEM_PATH allows multiple local repositories to be searched for
gems.

If you are behind a proxy server, RubyGems uses the HTTP_PROXY,
HTTP_PROXY_USER and HTTP_PROXY_PASS environment variables to discover the
proxy server.

If you would like to push gems to a private gem server the RUBYGEMS_HOST
environment variable can be set to the URI for that server.

If you are packaging RubyGems all of RubyGems' defaults are in
lib/rubygems/defaults.rb.  You may override these in
lib/rubygems/defaults/operating_system.rb
    EOF
  end

  def usage # :nodoc:
    "#{program_name} [arg]"
  end

  def execute
    out = String.new
    arg = options[:args][0]
    out <<
      case arg
      when /^version/ then
        Gem::VERSION
      when /^gemdir/, /^gemhome/, /^home/, /^GEM_HOME/ then
        Gem.dir
      when /^gempath/, /^path/, /^GEM_PATH/ then
        Gem.path.join(File::PATH_SEPARATOR)
      when /^user_gemdir/, /^user_gemhome/ then
        Gem.user_dir
      when /^remotesources/ then
        Gem.sources.to_a.join("\n")
      when /^platform/ then
        Gem.platforms.join(File::PATH_SEPARATOR)
      when nil then
        show_environment
      else
        raise Gem::CommandLineError, "Unknown environment option [#{arg}]"
      end
    say out
    true
  end

  def add_path(out, path)
    path.each do |component|
      out << "     - #{component}\n"
    end
  end

  def show_environment # :nodoc:
    out = "RubyGems Environment:\n".dup

    out << "  - RUBYGEMS VERSION: #{Gem::VERSION}\n"

    out << "  - RUBY VERSION: #{RUBY_VERSION} (#{RUBY_RELEASE_DATE} patchlevel #{RUBY_PATCHLEVEL}) [#{RUBY_PLATFORM}]\n"

    out << "  - INSTALLATION DIRECTORY: #{Gem.dir}\n"

    out << "  - USER INSTALLATION DIRECTORY: #{Gem.user_dir}\n"

    out << "  - RUBYGEMS PREFIX: #{Gem.prefix}\n" unless Gem.prefix.nil?

    out << "  - RUBY EXECUTABLE: #{Gem.ruby}\n"

    out << "  - GIT EXECUTABLE: #{git_path}\n"

    out << "  - EXECUTABLE DIRECTORY: #{Gem.bindir}\n"

    out << "  - SPEC CACHE DIRECTORY: #{Gem.spec_cache_dir}\n"

    out << "  - SYSTEM CONFIGURATION DIRECTORY: #{Gem::ConfigFile::SYSTEM_CONFIG_PATH}\n"

    out << "  - RUBYGEMS PLATFORMS:\n"
    Gem.platforms.each do |platform|
      out << "     - #{platform}\n"
    end

    out << "  - GEM PATHS:\n"
    out << "     - #{Gem.dir}\n"

    gem_path = Gem.path.dup
    gem_path.delete Gem.dir
    add_path out, gem_path

    out << "  - GEM CONFIGURATION:\n"
    Gem.configuration.each do |name, value|
      value = value.gsub(/./, "*") if name == "gemcutter_key"
      out << "     - #{name.inspect} => #{value.inspect}\n"
    end

    out << "  - REMOTE SOURCES:\n"
    Gem.sources.each do |s|
      out << "     - #{s}\n"
    end

    out << "  - SHELL PATH:\n"

    shell_path = ENV["PATH"].split(File::PATH_SEPARATOR)
    add_path out, shell_path

    out
  end

  private

  ##
  # Git binary path

  def git_path
    exts = ENV["PATHEXT"] ? ENV["PATHEXT"].split(";") : [""]
    ENV["PATH"].split(File::PATH_SEPARATOR).each do |path|
      exts.each do |ext|
        exe = File.join(path, "git#{ext}")
        return exe if File.executable?(exe) && !File.directory?(exe)
      end
    end

    nil
  end
end
