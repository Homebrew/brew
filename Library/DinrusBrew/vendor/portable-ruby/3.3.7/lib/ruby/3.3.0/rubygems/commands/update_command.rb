# frozen_string_literal: true

require_relative "../command"
require_relative "../command_manager"
require_relative "../dependency_installer"
require_relative "../install_update_options"
require_relative "../local_remote_options"
require_relative "../spec_fetcher"
require_relative "../version_option"
require_relative "../install_message" # must come before rdoc for messaging
require_relative "../rdoc"

class Gem::Commands::UpdateCommand < Gem::Command
  include Gem::InstallUpdateOptions
  include Gem::LocalRemoteOptions
  include Gem::VersionOption

  attr_reader :installer # :nodoc:

  attr_reader :updated # :nodoc:

  def initialize
    options = {
      force: false,
    }

    options.merge!(install_update_options)

    super "update", "Update installed gems to the latest version", options

    add_install_update_options

    Gem::OptionParser.accept Gem::Version do |value|
      Gem::Version.new value

      value
    end

    add_option("--system [VERSION]", Gem::Version,
               "Update the RubyGems system software") do |value, opts|
      value ||= true

      opts[:system] = value
    end

    add_local_remote_options
    add_platform_option
    add_prerelease_option "as update targets"

    @updated   = []
    @installer = nil
  end

  def arguments # :nodoc:
    "GEMNAME       name of gem to update"
  end

  def defaults_str # :nodoc:
    "--no-force --install-dir #{Gem.dir}\n" +
      install_update_defaults_str
  end

  def description # :nodoc:
    <<-EOF
The update command will update your gems to the latest version.

The update command does not remove the previous version. Use the cleanup
command to remove old versions.
    EOF
  end

  def usage # :nodoc:
    "#{program_name} GEMNAME [GEMNAME ...]"
  end

  def check_latest_rubygems(version) # :nodoc:
    if Gem.rubygems_version == version
      say "Latest version already installed. Done."
      terminate_interaction
    end
  end

  def check_oldest_rubygems(version) # :nodoc:
    if oldest_supported_version > version
      alert_error "rubygems #{version} is not supported on #{RUBY_VERSION}. The oldest version supported by this ruby is #{oldest_supported_version}"
      terminate_interaction 1
    end
  end

  def check_update_arguments # :nodoc:
    unless options[:args].empty?
      alert_error "Gem names are not allowed with the --system option"
      terminate_interaction 1
    end
  end

  def execute
    if options[:system]
      update_rubygems
      return
    end

    gems_to_update = which_to_update(
      highest_installed_gems,
      options[:args].uniq
    )

    if options[:explain]
      say "Gems to update:"

      gems_to_update.each do |name_tuple|
        say "  #{name_tuple.full_name}"
      end

      return
    end

    say "Updating installed gems"

    updated = update_gems gems_to_update

    installed_names = highest_installed_gems.keys
    updated_names = updated.map(&:name)
    not_updated_names = options[:args].uniq - updated_names
    not_installed_names = not_updated_names - installed_names
    up_to_date_names = not_updated_names - not_installed_names

    if updated.empty?
      say "Nothing to update"
    else
      say "Gems updated: #{updated_names.join(" ")}"
    end
    say "Gems already up-to-date: #{up_to_date_names.join(" ")}" unless up_to_date_names.empty?
    say "Gems not currently installed: #{not_installed_names.join(" ")}" unless not_installed_names.empty?
  end

  def fetch_remote_gems(spec) # :nodoc:
    dependency = Gem::Dependency.new spec.name, "> #{spec.version}"
    dependency.prerelease = options[:prerelease]

    fetcher = Gem::SpecFetcher.fetcher

    spec_tuples, errors = fetcher.search_for_dependency dependency

    error = errors.find {|e| e.respond_to? :exception }

    raise error if error

    spec_tuples
  end

  def highest_installed_gems # :nodoc:
    hig = {} # highest installed gems

    # Get only gem specifications installed as --user-install
    Gem::Specification.dirs = Gem.user_dir if options[:user_install]

    Gem::Specification.each do |spec|
      if hig[spec.name].nil? || hig[spec.name].version < spec.version
        hig[spec.name] = spec
      end
    end

    hig
  end

  def highest_remote_name_tuple(spec) # :nodoc:
    spec_tuples = fetch_remote_gems spec

    highest_remote_gem = spec_tuples.max
    return unless highest_remote_gem

    highest_remote_gem.first
  end

  def install_rubygems(spec) # :nodoc:
    args = update_rubygems_arguments
    version = spec.version

    update_dir = File.join spec.base_dir, "gems", "rubygems-update-#{version}"

    Dir.chdir update_dir do
      say "Installing RubyGems #{version}" unless options[:silent]

      installed = preparing_gem_layout_for(version) do
        system Gem.ruby, "--disable-gems", "setup.rb", *args
      end

      unless options[:silent]
        say "RubyGems system software updated" if installed
      end
    end
  end

  def preparing_gem_layout_for(version)
    if Gem::Version.new(version) >= Gem::Version.new("3.2.a")
      yield
    else
      require "tmpdir"
      Dir.mktmpdir("gem_update") do |tmpdir|
        FileUtils.mv Gem.plugindir, tmpdir

        status = yield

        unless status
          FileUtils.mv File.join(tmpdir, "plugins"), Gem.plugindir
        end

        status
      end
    end
  end

  def rubygems_target_version
    version = options[:system]
    update_latest = version == true

    unless update_latest
      version     = Gem::Version.new     version
      requirement = Gem::Requirement.new version

      return version, requirement
    end

    version     = Gem::Version.new     Gem::VERSION
    requirement = Gem::Requirement.new ">= #{Gem::VERSION}"

    rubygems_update         = Gem::Specification.new
    rubygems_update.name    = "rubygems-update"
    rubygems_update.version = version

    highest_remote_tup = highest_remote_name_tuple(rubygems_update)
    target = highest_remote_tup ? highest_remote_tup.version : version

    [target, requirement]
  end

  def update_gem(name, version = Gem::Requirement.default)
    return if @updated.any? {|spec| spec.name == name }

    update_options = options.dup
    update_options[:prerelease] = version.prerelease?

    @installer = Gem::DependencyInstaller.new update_options

    say "Updating #{name}" unless options[:system]
    begin
      @installer.install name, Gem::Requirement.new(version)
    rescue Gem::InstallError, Gem::DependencyError => e
      alert_error "Error installing #{name}:\n\t#{e.message}"
    end

    @installer.installed_gems.each do |spec|
      @updated << spec
    end
  end

  def update_gems(gems_to_update)
    gems_to_update.uniq.sort.each do |name_tuple|
      update_gem name_tuple.name, name_tuple.version
    end

    @updated
  end

  ##
  # Update RubyGems software to the latest version.

  def update_rubygems
    if Gem.disable_system_update_message
      alert_error Gem.disable_system_update_message
      terminate_interaction 1
    end

    check_update_arguments

    version, requirement = rubygems_target_version

    check_latest_rubygems version

    check_oldest_rubygems version

    installed_gems = Gem::Specification.find_all_by_name "rubygems-update", requirement
    installed_gems = update_gem("rubygems-update", requirement) if installed_gems.empty? || installed_gems.first.version != version
    return if installed_gems.empty?

    install_rubygems installed_gems.first
  end

  def update_rubygems_arguments # :nodoc:
    args = []
    args << "--silent" if options[:silent]
    args << "--prefix" << Gem.prefix if Gem.prefix
    args << "--no-document" unless options[:document].include?("rdoc") || options[:document].include?("ri")
    args << "--no-format-executable" if options[:no_format_executable]
    args << "--previous-version" << Gem::VERSION
    args
  end

  def which_to_update(highest_installed_gems, gem_names)
    result = []

    highest_installed_gems.each do |_l_name, l_spec|
      next if !gem_names.empty? &&
              gem_names.none? {|name| name == l_spec.name }

      highest_remote_tup = highest_remote_name_tuple l_spec
      next unless highest_remote_tup

      result << highest_remote_tup
    end

    result
  end

  private

  #
  # Oldest version we support downgrading to. This is the version that
  # originally ships with the first patch version of each ruby, because we never
  # test each ruby against older rubygems, so we can't really guarantee it
  # works. Version list can be checked here: https://stdgems.org/rubygems
  #
  def oldest_supported_version
    @oldest_supported_version ||=
      if Gem.ruby_version > Gem::Version.new("3.1.a")
        Gem::Version.new("3.3.3")
      else
        Gem::Version.new("3.2.3")
      end
  end
end
