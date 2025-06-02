# frozen_string_literal: true

require_relative "../command"
require_relative "../package"
require_relative "../installer"
require_relative "../version_option"

class Gem::Commands::PristineCommand < Gem::Command
  include Gem::VersionOption

  def initialize
    super "pristine",
          "Restores installed gems to pristine condition from files located in the gem cache",
          version: Gem::Requirement.default,
          extensions: true,
          extensions_set: false,
          all: false

    add_option("--all",
               "Restore all installed gems to pristine",
               "condition") do |value, options|
      options[:all] = value
    end

    add_option("--skip=gem_name",
               "used on --all, skip if name == gem_name") do |value, options|
      options[:skip] ||= []
      options[:skip] << value
    end

    add_option("--[no-]extensions",
               "Restore gems with extensions",
               "in addition to regular gems") do |value, options|
      options[:extensions_set] = true
      options[:extensions]     = value
    end

    add_option("--only-missing-extensions",
               "Only restore gems with missing extensions") do |value, options|
      options[:only_missing_extensions] = value
    end

    add_option("--only-executables",
               "Only restore executables") do |value, options|
      options[:only_executables] = value
    end

    add_option("--only-plugins",
               "Only restore plugins") do |value, options|
      options[:only_plugins] = value
    end

    add_option("-E", "--[no-]env-shebang",
               "Rewrite executables with a shebang",
               "of /usr/bin/env") do |value, options|
      options[:env_shebang] = value
    end

    add_option("-i", "--install-dir DIR",
               "Gem repository to get gems restored") do |value, options|
      options[:install_dir] = File.expand_path(value)
    end

    add_option("-n", "--bindir DIR",
               "Directory where executables are",
               "located") do |value, options|
      options[:bin_dir] = File.expand_path(value)
    end

    add_version_option("restore to", "pristine condition")
  end

  def arguments # :nodoc:
    "GEMNAME       gem to restore to pristine condition (unless --all)"
  end

  def defaults_str # :nodoc:
    "--extensions"
  end

  def description # :nodoc:
    <<-EOF
The pristine command compares an installed gem with the contents of its
cached .gem file and restores any files that don't match the cached .gem's
copy.

If you have made modifications to an installed gem, the pristine command
will revert them.  All extensions are rebuilt and all bin stubs for the gem
are regenerated after checking for modifications.

If the cached gem cannot be found it will be downloaded.

If --no-extensions is provided pristine will not attempt to restore a gem
with an extension.

If --extensions is given (but not --all or gem names) only gems with
extensions will be restored.
    EOF
  end

  def usage # :nodoc:
    "#{program_name} [GEMNAME ...]"
  end

  def execute
    install_dir = options[:install_dir]

    specification_record = install_dir ? Gem::SpecificationRecord.from_path(install_dir) : Gem::Specification.specification_record

    specs = if options[:all]
      specification_record.map

    # `--extensions` must be explicitly given to pristine only gems
    # with extensions.
    elsif options[:extensions_set] &&
          options[:extensions] && options[:args].empty?
      specification_record.select do |spec|
        spec.extensions && !spec.extensions.empty?
      end
    elsif options[:only_missing_extensions]
      specification_record.select(&:missing_extensions?)
    else
      get_all_gem_names.sort.map do |gem_name|
        specification_record.find_all_by_name(gem_name, options[:version]).reverse
      end.flatten
    end

    specs = specs.select {|spec| spec.platform == RUBY_ENGINE || Gem::Platform.local === spec.platform || spec.platform == Gem::Platform::RUBY }

    if specs.to_a.empty?
      raise Gem::Exception,
            "Failed to find gems #{options[:args]} #{options[:version]}"
    end

    say "Restoring gems to pristine condition..."

    specs.group_by(&:full_name_with_location).values.each do |grouped_specs|
      spec = grouped_specs.find {|s| !s.default_gem? } || grouped_specs.first

      unless only_executables_or_plugins?
        # Default gemspecs include changes provided by ruby-core installer that
        # can't currently be pristined (inclusion of compiled extension targets in
        # the file list). So stick to resetting executables if it's a default gem.
        options[:only_executables] = true if spec.default_gem?
      end

      if options.key? :skip
        if options[:skip].include? spec.name
          say "Skipped #{spec.full_name}, it was given through options"
          next
        end
      end

      unless spec.extensions.empty? || options[:extensions] || only_executables_or_plugins?
        say "Skipped #{spec.full_name_with_location}, it needs to compile an extension"
        next
      end

      gem = spec.cache_file

      unless File.exist?(gem) || only_executables_or_plugins?
        require_relative "../remote_fetcher"

        say "Cached gem for #{spec.full_name_with_location} not found, attempting to fetch..."

        dep = Gem::Dependency.new spec.name, spec.version
        found, _ = Gem::SpecFetcher.fetcher.spec_for_dependency dep

        if found.empty?
          say "Skipped #{spec.full_name}, it was not found from cache and remote sources"
          next
        end

        spec_candidate, source = found.first
        Gem::RemoteFetcher.fetcher.download spec_candidate, source.uri.to_s, spec.base_dir
      end

      env_shebang =
        if options.include? :env_shebang
          options[:env_shebang]
        else
          install_defaults = Gem::ConfigFile::PLATFORM_DEFAULTS["install"]
          install_defaults.to_s["--env-shebang"]
        end

      bin_dir = options[:bin_dir] if options[:bin_dir]

      installer_options = {
        wrappers: true,
        force: true,
        install_dir: install_dir || spec.base_dir,
        env_shebang: env_shebang,
        build_args: spec.build_args,
        bin_dir: bin_dir,
      }

      if options[:only_executables]
        installer = Gem::Installer.for_spec(spec, installer_options)
        installer.generate_bin
      elsif options[:only_plugins]
        installer = Gem::Installer.for_spec(spec, installer_options)
        installer.generate_plugins
      else
        installer = Gem::Installer.at(gem, installer_options)
        installer.install
      end

      say "Restored #{spec.full_name_with_location}"
    end
  end

  private

  def only_executables_or_plugins?
    options[:only_executables] || options[:only_plugins]
  end
end
