# frozen_string_literal: true

require_relative "../command"
require_relative "../version_option"
require_relative "../uninstaller"
require "fileutils"

##
# Gem uninstaller command line tool
#
# See `gem help uninstall`

class Gem::Commands::UninstallCommand < Gem::Command
  include Gem::VersionOption

  def initialize
    super "uninstall", "Uninstall gems from the local repository",
          version: Gem::Requirement.default, user_install: true,
          check_dev: false, vendor: false

    add_option("-a", "--[no-]all",
      "Uninstall all matching versions") do |value, options|
      options[:all] = value
    end

    add_option("-I", "--[no-]ignore-dependencies",
               "Ignore dependency requirements while",
               "uninstalling") do |value, options|
      options[:ignore] = value
    end

    add_option("-D", "--[no-]check-development",
               "Check development dependencies while uninstalling",
               "(default: false)") do |value, options|
      options[:check_dev] = value
    end

    add_option("-x", "--[no-]executables",
                 "Uninstall applicable executables without",
                 "confirmation") do |value, options|
      options[:executables] = value
    end

    add_option("-i", "--install-dir DIR",
               "Directory to uninstall gem from") do |value, options|
      options[:install_dir] = File.expand_path(value)
    end

    add_option("-n", "--bindir DIR",
               "Directory to remove executables from") do |value, options|
      options[:bin_dir] = File.expand_path(value)
    end

    add_option("--[no-]user-install",
               "Uninstall from user's home directory",
               "in addition to GEM_HOME.") do |value, options|
      options[:user_install] = value
    end

    add_option("--[no-]format-executable",
               "Assume executable names match Ruby's prefix and suffix.") do |value, options|
      options[:format_executable] = value
    end

    add_option("--[no-]force",
               "Uninstall all versions of the named gems",
               "ignoring dependencies") do |value, options|
      options[:force] = value
    end

    add_option("--[no-]abort-on-dependent",
               "Prevent uninstalling gems that are",
               "depended on by other gems.") do |value, options|
      options[:abort_on_dependent] = value
    end

    add_version_option
    add_platform_option

    add_option("--vendor",
               "Uninstall gem from the vendor directory.",
               "Only for use by gem repackagers.") do |_value, options|
      unless Gem.vendor_dir
        raise Gem::OptionParser::InvalidOption.new "your platform is not supported"
      end

      alert_warning "Use your OS package manager to uninstall vendor gems"
      options[:vendor] = true
      options[:install_dir] = Gem.vendor_dir
    end
  end

  def arguments # :nodoc:
    "GEMNAME       name of gem to uninstall"
  end

  def defaults_str # :nodoc:
    "--version '#{Gem::Requirement.default}' --no-force " \
      "--user-install"
  end

  def description # :nodoc:
    <<-EOF
The uninstall command removes a previously installed gem.

RubyGems will ask for confirmation if you are attempting to uninstall a gem
that is a dependency of an existing gem.  You can use the
--ignore-dependencies option to skip this check.
    EOF
  end

  def usage # :nodoc:
    "#{program_name} GEMNAME [GEMNAME ...]"
  end

  def check_version # :nodoc:
    if options[:version] != Gem::Requirement.default &&
       get_all_gem_names.size > 1
      alert_error "Can't use --version with multiple gems. You can specify multiple gems with" \
                  " version requirements using `gem uninstall 'my_gem:1.0.0' 'my_other_gem:~>2.0.0'`"
      terminate_interaction 1
    end
  end

  def execute
    check_version

    # Consider only gem specifications installed at `--install-dir`
    Gem::Specification.dirs = options[:install_dir] if options[:install_dir]

    if options[:all] && !options[:args].empty?
      uninstall_specific
    elsif options[:all]
      uninstall_all
    else
      uninstall_specific
    end
  end

  def uninstall_all
    specs = Gem::Specification.reject(&:default_gem?)

    specs.each do |spec|
      options[:version] = spec.version
      uninstall_gem spec.name
    end

    alert "Uninstalled all gems in #{options[:install_dir] || Gem.dir}"
  end

  def uninstall_specific
    deplist = Gem::DependencyList.new
    original_gem_version = {}

    get_all_gem_names_and_versions.each do |name, version|
      original_gem_version[name] = version || options[:version]

      gem_specs = Gem::Specification.find_all_by_name(name, original_gem_version[name])

      if gem_specs.empty?
        say("Gem '#{name}' is not installed")
      else
        gem_specs.reject!(&:default_gem?) if gem_specs.size > 1

        gem_specs.each do |spec|
          deplist.add spec
        end
      end
    end

    deps = deplist.strongly_connected_components.flatten.reverse

    gems_to_uninstall = {}

    deps.each do |dep|
      if original_gem_version[dep.name] == Gem::Requirement.default
        next if gems_to_uninstall[dep.name]
        gems_to_uninstall[dep.name] = true
      else
        options[:version] = dep.version
      end

      uninstall_gem(dep.name)
    end
  end

  def uninstall_gem(gem_name)
    uninstall(gem_name)
  rescue Gem::GemNotInHomeException => e
    spec = e.spec
    alert("In order to remove #{spec.name}, please execute:\n" \
          "\tgem uninstall #{spec.name} --install-dir=#{spec.base_dir}")
  rescue Gem::UninstallError => e
    spec = e.spec
    alert_error("Error: unable to successfully uninstall '#{spec.name}' which is " \
          "located at '#{spec.full_gem_path}'. This is most likely because" \
          "the current user does not have the appropriate permissions")
    terminate_interaction 1
  end

  def uninstall(gem_name)
    Gem::Uninstaller.new(gem_name, options).uninstall
  end
end
