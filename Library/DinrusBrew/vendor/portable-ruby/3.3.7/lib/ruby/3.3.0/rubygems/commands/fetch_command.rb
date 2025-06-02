# frozen_string_literal: true

require_relative "../command"
require_relative "../local_remote_options"
require_relative "../version_option"

class Gem::Commands::FetchCommand < Gem::Command
  include Gem::LocalRemoteOptions
  include Gem::VersionOption

  def initialize
    defaults = {
      suggest_alternate: true,
      version: Gem::Requirement.default,
    }

    super "fetch", "Download a gem and place it in the current directory", defaults

    add_bulk_threshold_option
    add_proxy_option
    add_source_option
    add_clear_sources_option

    add_version_option
    add_platform_option
    add_prerelease_option

    add_option "--[no-]suggestions", "Suggest alternates when gems are not found" do |value, options|
      options[:suggest_alternate] = value
    end
  end

  def arguments # :nodoc:
    "GEMNAME       name of gem to download"
  end

  def defaults_str # :nodoc:
    "--version '#{Gem::Requirement.default}'"
  end

  def description # :nodoc:
    <<-EOF
The fetch command fetches gem files that can be stored for later use or
unpacked to examine their contents.

See the build command help for an example of unpacking a gem, modifying it,
then repackaging it.
    EOF
  end

  def usage # :nodoc:
    "#{program_name} GEMNAME [GEMNAME ...]"
  end

  def check_version # :nodoc:
    if options[:version] != Gem::Requirement.default &&
       get_all_gem_names.size > 1
      alert_error "Can't use --version with multiple gems. You can specify multiple gems with" \
                  " version requirements using `gem fetch 'my_gem:1.0.0' 'my_other_gem:~>2.0.0'`"
      terminate_interaction 1
    end
  end

  def execute
    check_version

    exit_code = fetch_gems

    terminate_interaction exit_code
  end

  private

  def fetch_gems
    exit_code = 0

    version = options[:version]

    platform  = Gem.platforms.last
    gem_names = get_all_gem_names_and_versions

    gem_names.each do |gem_name, gem_version|
      gem_version ||= version
      dep = Gem::Dependency.new gem_name, gem_version
      dep.prerelease = options[:prerelease]
      suppress_suggestions = !options[:suggest_alternate]

      specs_and_sources, errors =
        Gem::SpecFetcher.fetcher.spec_for_dependency dep

      if platform
        filtered = specs_and_sources.select {|s,| s.platform == platform }
        specs_and_sources = filtered unless filtered.empty?
      end

      spec, source = specs_and_sources.max_by {|s,| s }

      if spec.nil?
        show_lookup_failure gem_name, gem_version, errors, suppress_suggestions, options[:domain]
        exit_code |= 2
        next
      end
      source.download spec
      say "Downloaded #{spec.full_name}"
    end

    exit_code
  end
end
