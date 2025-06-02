# frozen_string_literal: true
require_relative "../command"
require_relative "../remote_fetcher"
require_relative "../spec_fetcher"
require_relative "../local_remote_options"

class Gem::Commands::SourcesCommand < Gem::Command
  include Gem::LocalRemoteOptions

  def initialize
    require "fileutils"

    super "sources",
          "Manage the sources and cache file RubyGems uses to search for gems"

    add_option "-a", "--add SOURCE_URI", "Add source" do |value, options|
      options[:add] = value
    end

    add_option "-l", "--list", "List sources" do |value, options|
      options[:list] = value
    end

    add_option "-r", "--remove SOURCE_URI", "Remove source" do |value, options|
      options[:remove] = value
    end

    add_option "-c", "--clear-all",
               "Remove all sources (clear the cache)" do |value, options|
      options[:clear_all] = value
    end

    add_option "-u", "--update", "Update source cache" do |value, options|
      options[:update] = value
    end

    add_option "-f", "--[no-]force", "Do not show any confirmation prompts and behave as if 'yes' was always answered" do |value, options|
      options[:force] = value
    end

    add_proxy_option
  end

  def add_source(source_uri) # :nodoc:
    check_rubygems_https source_uri

    source = Gem::Source.new source_uri

    check_typo_squatting(source)

    begin
      if Gem.sources.include? source
        say "source #{source_uri} already present in the cache"
      else
        source.load_specs :released
        Gem.sources << source
        Gem.configuration.write

        say "#{source_uri} added to sources"
      end
    rescue URI::Error, ArgumentError
      say "#{source_uri} is not a URI"
      terminate_interaction 1
    rescue Gem::RemoteFetcher::FetchError => e
      say "Error fetching #{Gem::Uri.redact(source.uri)}:\n\t#{e.message}"
      terminate_interaction 1
    end
  end

  def check_typo_squatting(source)
    if source.typo_squatting?("rubygems.org")
      question = <<-QUESTION.chomp
#{source.uri.to_s} is too similar to https://rubygems.org

Do you want to add this source?
      QUESTION

      terminate_interaction 1 unless options[:force] || ask_yes_no(question)
    end
  end

  def check_rubygems_https(source_uri) # :nodoc:
    uri = URI source_uri

    if uri.scheme && uri.scheme.downcase == "http" &&
       uri.host.downcase == "rubygems.org"
      question = <<-QUESTION.chomp
https://rubygems.org is recommended for security over #{uri}

Do you want to add this insecure source?
      QUESTION

      terminate_interaction 1 unless options[:force] || ask_yes_no(question)
    end
  end

  def clear_all # :nodoc:
    path = Gem.spec_cache_dir
    FileUtils.rm_rf path

    unless File.exist? path
      say "*** Removed specs cache ***"
    else
      unless File.writable? path
        say "*** Unable to remove source cache (write protected) ***"
      else
        say "*** Unable to remove source cache ***"
      end

      terminate_interaction 1
    end
  end

  def defaults_str # :nodoc:
    "--list"
  end

  def description # :nodoc:
    <<-EOF
RubyGems fetches gems from the sources you have configured (stored in your
~/.gemrc).

The default source is https://rubygems.org, but you may have other sources
configured.  This guide will help you update your sources or configure
yourself to use your own gem server.

Without any arguments the sources lists your currently configured sources:

  $ gem sources
  *** CURRENT SOURCES ***

  https://rubygems.org

This may list multiple sources or non-rubygems sources.  You probably
configured them before or have an old `~/.gemrc`.  If you have sources you
do not recognize you should remove them.

RubyGems has been configured to serve gems via the following URLs through
its history:

* http://gems.rubyforge.org (RubyGems 1.3.5 and earlier)
* http://rubygems.org       (RubyGems 1.3.6 through 1.8.30, and 2.0.0)
* https://rubygems.org      (RubyGems 2.0.1 and newer)

Since all of these sources point to the same set of gems you only need one
of them in your list.  https://rubygems.org is recommended as it brings the
protections of an SSL connection to gem downloads.

To add a source use the --add argument:

    $ gem sources --add https://rubygems.org
    https://rubygems.org added to sources

RubyGems will check to see if gems can be installed from the source given
before it is added.

To remove a source use the --remove argument:

    $ gem sources --remove https://rubygems.org/
    https://rubygems.org/ removed from sources

    EOF
  end

  def list # :nodoc:
    say "*** CURRENT SOURCES ***"
    say

    Gem.sources.each do |src|
      say src
    end
  end

  def list? # :nodoc:
    !(options[:add] ||
      options[:clear_all] ||
      options[:remove] ||
      options[:update])
  end

  def execute
    clear_all if options[:clear_all]

    source_uri = options[:add]
    add_source source_uri if source_uri

    source_uri = options[:remove]
    remove_source source_uri if source_uri

    update if options[:update]

    list if list?
  end

  def remove_source(source_uri) # :nodoc:
    unless Gem.sources.include? source_uri
      say "source #{source_uri} not present in cache"
    else
      Gem.sources.delete source_uri
      Gem.configuration.write

      say "#{source_uri} removed from sources"
    end
  end

  def update # :nodoc:
    Gem.sources.each_source do |src|
      src.load_specs :released
      src.load_specs :latest
    end

    say "source cache successfully updated"
  end

  def remove_cache_file(desc, path) # :nodoc:
    FileUtils.rm_rf path

    if !File.exist?(path)
      say "*** Removed #{desc} source cache ***"
    elsif !File.writable?(path)
      say "*** Unable to remove #{desc} source cache (write protected) ***"
    else
      say "*** Unable to remove #{desc} source cache ***"
    end
  end
end
