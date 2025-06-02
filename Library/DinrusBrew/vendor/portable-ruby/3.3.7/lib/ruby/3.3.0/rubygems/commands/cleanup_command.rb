# frozen_string_literal: true

require_relative "../command"
require_relative "../dependency_list"
require_relative "../uninstaller"

class Gem::Commands::CleanupCommand < Gem::Command
  def initialize
    super "cleanup",
          "Clean up old versions of installed gems",
          force: false, install_dir: Gem.dir,
          check_dev: true

    add_option("-n", "-d", "--dry-run",
               "Do not uninstall gems") do |_value, options|
      options[:dryrun] = true
    end

    add_option(:Deprecated, "--dryrun",
               "Do not uninstall gems") do |_value, options|
      options[:dryrun] = true
    end
    deprecate_option("--dryrun", extra_msg: "Use --dry-run instead")

    add_option("-D", "--[no-]check-development",
               "Check development dependencies while uninstalling",
               "(default: true)") do |value, options|
      options[:check_dev] = value
    end

    add_option("--[no-]user-install",
               "Cleanup in user's home directory instead",
               "of GEM_HOME.") do |value, options|
      options[:user_install] = value
    end

    @candidate_gems  = nil
    @default_gems    = []
    @full            = nil
    @gems_to_cleanup = nil
    @primary_gems    = nil
  end

  def arguments # :nodoc:
    "GEMNAME       name of gem to cleanup"
  end

  def defaults_str # :nodoc:
    "--no-dry-run"
  end

  def description # :nodoc:
    <<-EOF
The cleanup command removes old versions of gems from GEM_HOME that are not
required to meet a dependency.  If a gem is installed elsewhere in GEM_PATH
the cleanup command won't delete it.

If no gems are named all gems in GEM_HOME are cleaned.
    EOF
  end

  def usage # :nodoc:
    "#{program_name} [GEMNAME ...]"
  end

  def execute
    say "Cleaning up installed gems..."

    if options[:args].empty?
      done     = false
      last_set = nil

      until done do
        clean_gems

        this_set = @gems_to_cleanup.map(&:full_name).sort

        done = this_set.empty? || last_set == this_set

        last_set = this_set
      end
    else
      clean_gems
    end

    say "Clean up complete"

    verbose do
      skipped = @default_gems.map(&:full_name)

      "Skipped default gems: #{skipped.join ", "}"
    end
  end

  def clean_gems
    get_primary_gems
    get_candidate_gems
    get_gems_to_cleanup

    @full = Gem::DependencyList.from_specs

    deplist = Gem::DependencyList.new
    @gems_to_cleanup.each {|spec| deplist.add spec }

    deps = deplist.strongly_connected_components.flatten

    deps.reverse_each do |spec|
      uninstall_dep spec
    end
  end

  def get_candidate_gems
    @candidate_gems = if options[:args].empty?
      Gem::Specification.to_a
    else
      options[:args].map do |gem_name|
        Gem::Specification.find_all_by_name gem_name
      end.flatten
    end
  end

  def get_gems_to_cleanup
    gems_to_cleanup = @candidate_gems.select do |spec|
      @primary_gems[spec.name].version != spec.version
    end

    default_gems, gems_to_cleanup = gems_to_cleanup.partition(&:default_gem?)

    uninstall_from = options[:user_install] ? Gem.user_dir : Gem.dir

    gems_to_cleanup = gems_to_cleanup.select do |spec|
      spec.base_dir == uninstall_from
    end

    @default_gems += default_gems
    @default_gems.uniq!
    @gems_to_cleanup = gems_to_cleanup.uniq
  end

  def get_primary_gems
    @primary_gems = {}

    Gem::Specification.each do |spec|
      if @primary_gems[spec.name].nil? ||
         @primary_gems[spec.name].version < spec.version
        @primary_gems[spec.name] = spec
      end
    end
  end

  def uninstall_dep(spec)
    return unless @full.ok_to_remove?(spec.full_name, options[:check_dev])

    if options[:dryrun]
      say "Dry Run Mode: Would uninstall #{spec.full_name}"
      return
    end

    say "Attempting to uninstall #{spec.full_name}"

    uninstall_options = {
      executables: false,
      version: "= #{spec.version}",
    }

    uninstall_options[:user_install] = Gem.user_dir == spec.base_dir

    uninstaller = Gem::Uninstaller.new spec.name, uninstall_options

    begin
      uninstaller.uninstall
    rescue Gem::DependencyRemovalException, Gem::InstallError,
           Gem::GemNotInHomeException, Gem::FilePermissionError => e
      say "Unable to uninstall #{spec.full_name}:"
      say "\t#{e.class}: #{e.message}"
    end
  end
end
