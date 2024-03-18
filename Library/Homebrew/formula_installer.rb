# typed: true
# frozen_string_literal: true

require "formula"
require "keg"
require "tab"
require "utils/bottles"
require "caveats"
require "cleaner"
require "formula_cellar_checks"
require "install_renamed"
require "sandbox"
require "development_tools"
require "cache_store"
require "linkage_checker"
require "install"
require "messages"
require "cask/cask_loader"
require "cmd/install"
require "find"
require "utils/spdx"
require "deprecate_disable"
require "unlink"
require "service"

# Installer for a formula.
#
# @api private
class FormulaInstaller
  include FormulaCellarChecks
  extend Attrable

  attr_reader :formula, :bottle_tab_runtime_dependencies

  attr_accessor :options, :link_keg

  attr_predicate :installed_as_dependency?, :installed_on_request?
  attr_predicate :show_summary_heading?, :show_header?
  attr_predicate :force_bottle?, :ignore_deps?, :only_deps?, :interactive?, :git?, :force?, :overwrite?, :keep_tmp?
  attr_predicate :debug_symbols?
  attr_predicate :verbose?, :debug?, :quiet?

  def initialize(
    formula,
    link_keg: false,
    installed_as_dependency: false,
    installed_on_request: true,
    show_header: false,
    build_bottle: false,
    skip_post_install: false,
    force_bottle: false,
    bottle_arch: nil,
    ignore_deps: false,
    only_deps: false,
    include_test_formulae: [],
    build_from_source_formulae: [],
    env: nil,
    git: false,
    interactive: false,
    keep_tmp: false,
    debug_symbols: false,
    cc: nil,
    options: Options.new,
    force: false,
    overwrite: false,
    debug: false,
    quiet: false,
    verbose: false
  )
    @formula = formula
    @env = env
    @force = force
    @overwrite = overwrite
    @keep_tmp = keep_tmp
    @debug_symbols = debug_symbols
    @link_keg = !formula.keg_only? || link_keg
    @show_header = show_header
    @ignore_deps = ignore_deps
    @only_deps = only_deps
    @build_from_source_formulae = build_from_source_formulae
    @build_bottle = build_bottle
    @skip_post_install = skip_post_install
    @bottle_arch = bottle_arch
    @formula.force_bottle ||= force_bottle
    @force_bottle = @formula.force_bottle
    @include_test_formulae = include_test_formulae
    @interactive = interactive
    @git = git
    @cc = cc
    @verbose = verbose
    @quiet = quiet
    @debug = debug
    @installed_as_dependency = installed_as_dependency
    @installed_on_request = installed_on_request
    @options = options
    @requirement_messages = []
    @poured_bottle = false
    @start_time = nil
    @bottle_tab_runtime_dependencies = {}.freeze

    # Take the original formula instance, which might have been swapped from an API instance to a source instance
    @formula = previously_fetched_formula if previously_fetched_formula
  end

  def self.attempted
    @attempted ||= Set.new
  end

  sig { void }
  def self.clear_attempted
    @attempted = Set.new
  end

  def self.installed
    @installed ||= Set.new
  end

  sig { void }
  def self.clear_installed
    @installed = Set.new
  end

  def self.fetched
    @fetched ||= Set.new
  end

  sig { void }
  def self.clear_fetched
    @fetched = Set.new
  end

  sig { returns(T::Boolean) }
  def build_from_source?
    @build_from_source_formulae.include?(formula.full_name)
  end

  sig { returns(T::Boolean) }
  def include_test?
    @include_test_formulae.include?(formula.full_name)
  end

  sig { returns(T::Boolean) }
  def build_bottle?
    @build_bottle.present?
  end

  sig { returns(T::Boolean) }
  def skip_post_install?
    @skip_post_install.present?
  end

  sig { params(output_warning: T::Boolean).returns(T::Boolean) }
  def pour_bottle?(output_warning: false)
    return false if !formula.bottle_tag? && !formula.local_bottle_path
    return true  if force_bottle?
    return false if build_from_source? || build_bottle? || interactive?
    return false if @cc
    return false unless options.empty?

    unless formula.pour_bottle?
      if output_warning && formula.pour_bottle_check_unsatisfied_reason
        opoo <<~EOS
          Building #{formula.full_name} from source:
            #{formula.pour_bottle_check_unsatisfied_reason}
        EOS
      end
      return false
    end

    return true if formula.local_bottle_path.present?

    bottle = formula.bottle_for_tag(Utils::Bottles.tag)
    return false if bottle.nil?

    unless bottle.compatible_locations?
      if output_warning
        prefix = Pathname(bottle.cellar.to_s).parent
        opoo <<~EOS
          Building #{formula.full_name} from source as the bottle needs:
          - HOMEBREW_CELLAR: #{bottle.cellar} (yours is #{HOMEBREW_CELLAR})
          - HOMEBREW_PREFIX: #{prefix} (yours is #{HOMEBREW_PREFIX})
        EOS
      end
      return false
    end

    true
  end

  sig { params(dep: Formula, build: BuildOptions).returns(T::Boolean) }
  def install_bottle_for?(dep, build)
    return pour_bottle? if dep == formula

    @build_from_source_formulae.exclude?(dep.full_name) &&
      dep.bottle.present? &&
      dep.pour_bottle? &&
      build.used_options.empty? &&
      dep.bottle&.compatible_locations?
  end

  sig { void }
  def prelude
    deprecate_disable_type = DeprecateDisable.type(formula)
    if deprecate_disable_type.present?
      message = "#{formula.full_name} has been #{DeprecateDisable.message(formula)}"

      case deprecate_disable_type
      when :deprecated
        puts "::warning::#{message}" if ENV["GITHUB_ACTIONS"]
        opoo message
      when :disabled
        puts "::error::#{message}" if ENV["GITHUB_ACTIONS"]
        raise CannotInstallFormulaError, message
      end
    end

    Tab.clear_cache

    verify_deps_exist unless ignore_deps?
    forbidden_license_check

    check_install_sanity
    install_fetch_deps unless ignore_deps?
  end

  sig { void }
  def verify_deps_exist
    begin
      compute_dependencies
    rescue TapFormulaUnavailableError => e
      raise if e.tap.installed?

      e.tap.ensure_installed!
      retry if e.tap.installed? # It may have not installed if it's a core tap.
    end
  rescue FormulaUnavailableError => e
    e.dependent = formula.full_name
    raise
  end

  def check_installation_already_attempted
    raise FormulaInstallationAlreadyAttemptedError, formula if self.class.attempted.include?(formula)
  end

  def check_install_sanity
    check_installation_already_attempted

    if force_bottle? && !pour_bottle?
      raise CannotInstallFormulaError, "--force-bottle passed but #{formula.full_name} has no bottle!"
    end

    if Homebrew.default_prefix? &&
       !build_from_source? && !build_bottle? && !formula.head? && formula.tap&.core_tap? &&
       # Integration tests override homebrew-core locations
       ENV["HOMEBREW_INTEGRATION_TEST"].nil? &&
       !pour_bottle?
      message = if !formula.pour_bottle? && formula.pour_bottle_check_unsatisfied_reason
        formula_message = formula.pour_bottle_check_unsatisfied_reason
        formula_message[0] = formula_message[0].downcase

        <<~EOS
          #{formula}: #{formula_message}
        EOS
      # don't want to complain about no bottle available if doing an
      # upgrade/reinstall/dependency install (but do in the case the bottle
      # check fails)
      elsif fresh_install?(formula)
        <<~EOS
          #{formula}: no bottle available!
        EOS
      end

      if message
        message += <<~EOS
          If you're feeling brave, you can try to install from source with:
            brew install --build-from-source #{formula}

          It is expected behaviour that most formulae will fail to build from source.
          It is expected behaviour that Homebrew will be buggy and slow when building from source.
          Do not create any issues about failures building from source on Homebrew's GitHub repositories.
          Do not create any issues building from source even if you think this message is unrelated.
          Any opened issues will be immediately closed without response.
          Do not ask for help from Homebrew or its maintainers on social media.
          You may ask for help building from source in Homebrew's discussions but are unlikely to receive a response.
          If building from source fails, try to figure out the problem yourself and submit a fix as a pull request.
          We will review it but may or may not accept it.
        EOS
        raise CannotInstallFormulaError, message
      end
    end

    return if ignore_deps?

    if Homebrew::EnvConfig.developer?
      # `recursive_dependencies` trims cyclic dependencies, so we do one level and take the recursive deps of that.
      # Mapping direct dependencies to deeper dependencies in a hash is also useful for the cyclic output below.
      recursive_dep_map = formula.deps.to_h { |dep| [dep, dep.to_formula.recursive_dependencies] }

      cyclic_dependencies = []
      recursive_dep_map.each do |dep, recursive_deps|
        if [formula.name, formula.full_name].include?(dep.name)
          cyclic_dependencies << "#{formula.full_name} depends on itself directly"
        elsif recursive_deps.any? { |rdep| [formula.name, formula.full_name].include?(rdep.name) }
          cyclic_dependencies << "#{formula.full_name} depends on itself via #{dep.name}"
        end
      end

      if cyclic_dependencies.present?
        raise CannotInstallFormulaError, <<~EOS
          #{formula.full_name} contains a recursive dependency on itself:
            #{cyclic_dependencies.join("\n  ")}
        EOS
      end

      # Merge into one list
      recursive_deps = recursive_dep_map.flat_map { |dep, rdeps| [dep] + rdeps }
      Dependency.merge_repeats(recursive_deps)
    else
      recursive_deps = formula.recursive_dependencies
    end

    invalid_arch_dependencies = []
    pinned_unsatisfied_deps = []
    recursive_deps.each do |dep|
      if (tab = Tab.for_formula(dep.to_formula)) && tab.arch.present? && tab.arch.to_s != Hardware::CPU.arch.to_s
        invalid_arch_dependencies << "#{dep} was built for #{tab.arch}"
      end

      next unless dep.to_formula.pinned?
      next if dep.satisfied?(inherited_options_for(dep))
      next if dep.build? && pour_bottle?

      pinned_unsatisfied_deps << dep
    end

    if invalid_arch_dependencies.present?
      raise CannotInstallFormulaError, <<~EOS
        #{formula.full_name} dependencies not built for the #{Hardware::CPU.arch} CPU architecture:
          #{invalid_arch_dependencies.join("\n  ")}
      EOS
    end

    return if pinned_unsatisfied_deps.empty?

    raise CannotInstallFormulaError,
          "You must `brew unpin #{pinned_unsatisfied_deps * " "}` as installing " \
          "#{formula.full_name} requires the latest version of pinned dependencies"
  end

  sig { params(_formula: Formula).returns(T.nilable(T::Boolean)) }
  def fresh_install?(_formula)
    false
  end

  sig { void }
  def install_fetch_deps
    return if @compute_dependencies.blank?

    compute_dependencies(use_cache: false) if @compute_dependencies.any? do |dep, options|
      next false unless dep.implicit?

      fetch_dependencies
      install_dependency(dep, options)
      true
    end
  end

  def build_bottle_preinstall
    @etc_var_dirs ||= [HOMEBREW_PREFIX/"etc", HOMEBREW_PREFIX/"var"]
    @etc_var_preinstall = Find.find(*@etc_var_dirs.select(&:directory?)).to_a
  end

  def build_bottle_postinstall
    @etc_var_postinstall = Find.find(*@etc_var_dirs.select(&:directory?)).to_a
    (@etc_var_postinstall - @etc_var_preinstall).each do |file|
      Pathname.new(file).cp_path_sub(HOMEBREW_PREFIX, formula.bottle_prefix)
    end
  end

  sig { void }
  def install
    lock

    start_time = Time.now
    Homebrew::Install.perform_build_from_source_checks if !pour_bottle? && DevelopmentTools.installed?

    # Warn if a more recent version of this formula is available in the tap.
    begin
      if formula.pkg_version < (v = Formulary.factory(formula.full_name, force_bottle: force_bottle?).pkg_version)
        opoo "#{formula.full_name} #{v} is available and more recent than version #{formula.pkg_version}."
      end
    rescue FormulaUnavailableError
      nil
    end

    check_conflicts

    raise UnbottledError, [formula] if !pour_bottle? && !DevelopmentTools.installed?

    unless ignore_deps?
      deps = compute_dependencies(use_cache: false)
      if ((pour_bottle? && !DevelopmentTools.installed?) || build_bottle?) &&
         (unbottled = unbottled_dependencies(deps)).presence
        # Check that each dependency in deps has a bottle available, terminating
        # abnormally with a UnbottledError if one or more don't.
        raise UnbottledError, unbottled
      end

      install_dependencies(deps)
    end

    return if only_deps?

    formula.deprecated_flags.each do |deprecated_option|
      old_flag = deprecated_option.old_flag
      new_flag = deprecated_option.current_flag
      opoo "#{formula.full_name}: #{old_flag} was deprecated; using #{new_flag} instead!"
    end

    options = display_options(formula).join(" ")
    oh1 "Installing #{Formatter.identifier(formula.full_name)} #{options}".strip if show_header?

    if (tap = formula.tap) && tap.should_report_analytics?
      Utils::Analytics.report_package_event(:formula_install, package_name: formula.name, tap_name: tap.name,
on_request: installed_on_request?, options:)
    end

    self.class.attempted << formula

    if pour_bottle?
      begin
        pour
      rescue Exception # rubocop:disable Lint/RescueException
        # any exceptions must leave us with nothing installed
        ignore_interrupts do
          begin
            formula.prefix.rmtree if formula.prefix.directory?
          rescue Errno::EACCES, Errno::ENOTEMPTY
            odie <<~EOS
              Could not remove #{formula.prefix.basename} keg! Do so manually:
                sudo rm -rf #{formula.prefix}
            EOS
          end
          formula.rack.rmdir_if_possible
        end
        raise
      else
        @poured_bottle = true
      end
    end

    puts_requirement_messages

    build_bottle_preinstall if build_bottle?

    unless @poured_bottle
      build
      clean

      # Store the formula used to build the keg in the keg.
      formula_contents = if formula.local_bottle_path
        Utils::Bottles.formula_contents formula.local_bottle_path, name: formula.name
      else
        formula.path.read
      end
      s = formula_contents.gsub(/  bottle do.+?end\n\n?/m, "")
      brew_prefix = formula.prefix/".brew"
      brew_prefix.mkpath
      Pathname(brew_prefix/"#{formula.name}.rb").atomic_write(s)

      keg = Keg.new(formula.prefix)
      tab = Tab.for_keg(keg)
      tab.installed_as_dependency = installed_as_dependency?
      tab.installed_on_request = installed_on_request?
      tab.write
    end

    build_bottle_postinstall if build_bottle?

    opoo "Nothing was installed to #{formula.prefix}" unless formula.latest_version_installed?
    end_time = Time.now
    Homebrew.messages.package_installed(formula.name, end_time - start_time)
  end

  def check_conflicts
    return if force?

    conflicts = formula.conflicts.select do |c|
      f = Formulary.factory(c.name)
    rescue TapFormulaUnavailableError
      # If the formula name is a fully-qualified name let's silently
      # ignore it as we don't care about things used in taps that aren't
      # currently tapped.
      false
    rescue FormulaUnavailableError => e
      # If the formula name doesn't exist any more then complain but don't
      # stop installation from continuing.
      opoo <<~EOS
        #{formula}: #{e.message}
        'conflicts_with "#{c.name}"' should be removed from #{formula.path.basename}.
      EOS

      raise if Homebrew::EnvConfig.developer?

      $stderr.puts "Please report this issue to the #{formula.tap} tap (not Homebrew/brew or Homebrew/homebrew-core)!"
      false
    else
      f.linked_keg.exist? && f.opt_prefix.exist?
    end

    raise FormulaConflictError.new(formula, conflicts) unless conflicts.empty?
  end

  # Compute and collect the dependencies needed by the formula currently
  # being installed.
  def compute_dependencies(use_cache: true)
    @compute_dependencies = nil unless use_cache
    @compute_dependencies ||= begin
      # Needs to be done before expand_dependencies
      fetch_bottle_tab if pour_bottle?

      check_requirements(expand_requirements)
      expand_dependencies
    end
  end

  def unbottled_dependencies(deps)
    deps.map { |(dep, _options)| dep.to_formula }.reject do |dep_f|
      next false unless dep_f.pour_bottle?

      dep_f.bottled?
    end
  end

  def compute_and_install_dependencies
    deps = compute_dependencies
    install_dependencies(deps)
  end

  def check_requirements(req_map)
    @requirement_messages = []
    fatals = []

    req_map.each_pair do |dependent, reqs|
      reqs.each do |req|
        next if dependent.latest_version_installed? && req.name == "macos" && req.comparator == "<="

        @requirement_messages << "#{dependent}: #{req.message}"
        fatals << req if req.fatal?
      end
    end

    return if fatals.empty?

    puts_requirement_messages
    raise UnsatisfiedRequirements, fatals
  end

  def runtime_requirements(formula)
    runtime_deps = formula.runtime_formula_dependencies(undeclared: false)
    recursive_requirements = formula.recursive_requirements do |dependent, _|
      Requirement.prune unless runtime_deps.include?(dependent)
    end
    (recursive_requirements.to_a + formula.requirements.to_a).reject(&:build?).uniq
  end

  def expand_requirements
    unsatisfied_reqs = Hash.new { |h, k| h[k] = [] }
    formulae = [formula]
    formula_deps_map = formula.recursive_dependencies
                              .each_with_object({}) { |dep, h| h[dep.name] = dep }

    while (f = formulae.pop)
      runtime_requirements = runtime_requirements(f)
      f.recursive_requirements do |dependent, req|
        build = effective_build_options_for(dependent)
        install_bottle_for_dependent = install_bottle_for?(dependent, build)

        keep_build_test = false
        keep_build_test ||= runtime_requirements.include?(req)
        keep_build_test ||= req.test? && include_test? && dependent == f
        keep_build_test ||= req.build? && !install_bottle_for_dependent && !dependent.latest_version_installed?

        if req.prune_from_option?(build) ||
           req.satisfied?(env: @env, cc: @cc, build_bottle: @build_bottle, bottle_arch: @bottle_arch) ||
           ((req.build? || req.test?) && !keep_build_test) ||
           formula_deps_map[dependent.name]&.build? ||
           (only_deps? && f == dependent)
          Requirement.prune
        else
          unsatisfied_reqs[dependent] << req
        end
      end
    end

    unsatisfied_reqs
  end

  def expand_dependencies_for_formula(formula, inherited_options)
    # Cache for this expansion only. FormulaInstaller has a lot of inputs which can alter expansion.
    cache_key = "FormulaInstaller-#{formula.full_name}-#{Time.now.to_f}"
    Dependency.expand(formula, cache_key:) do |dependent, dep|
      inherited_options[dep.name] |= inherited_options_for(dep)
      build = effective_build_options_for(
        dependent,
        inherited_options.fetch(dependent.name, []),
      )

      keep_build_test = false
      keep_build_test ||= dep.test? && include_test? && @include_test_formulae.include?(dependent.full_name)
      keep_build_test ||= dep.build? && !install_bottle_for?(dependent, build) &&
                          (formula.head? || !dependent.latest_version_installed?)

      bottle_runtime_version = @bottle_tab_runtime_dependencies.dig(dep.name, "version").presence
      bottle_runtime_version = Version.new(bottle_runtime_version) if bottle_runtime_version
      bottle_runtime_revision = @bottle_tab_runtime_dependencies.dig(dep.name, "revision")

      if dep.prune_from_option?(build) || ((dep.build? || dep.test?) && !keep_build_test)
        Dependency.prune
      elsif dep.satisfied?(inherited_options[dep.name], minimum_version:  bottle_runtime_version,
                                                        minimum_revision: bottle_runtime_revision)
        Dependency.skip
      end
    end
  end

  def expand_dependencies
    inherited_options = Hash.new { |hash, key| hash[key] = Options.new }

    expanded_deps = expand_dependencies_for_formula(formula, inherited_options)

    expanded_deps.map { |dep| [dep, inherited_options[dep.name]] }
  end

  def effective_build_options_for(dependent, inherited_options = [])
    args  = dependent.build.used_options
    args |= (dependent == formula) ? options : inherited_options
    args |= Tab.for_formula(dependent).used_options
    args &= dependent.options
    BuildOptions.new(args, dependent.options)
  end

  def display_options(formula)
    options = if formula.head?
      ["--HEAD"]
    else
      []
    end
    options += effective_build_options_for(formula).used_options.to_a
    options
  end

  sig { params(dep: Dependency).returns(Options) }
  def inherited_options_for(dep)
    inherited_options = Options.new
    u = Option.new("universal")
    if (options.include?(u) || formula.require_universal_deps?) && !dep.build? && dep.to_formula.option_defined?(u)
      inherited_options << u
    end
    inherited_options
  end

  sig { params(deps: T::Array[[Dependency, Options]]).void }
  def install_dependencies(deps)
    if deps.empty? && only_deps?
      puts "All dependencies for #{formula.full_name} are satisfied."
    elsif !deps.empty?
      oh1 "Installing dependencies for #{formula.full_name}: " \
          "#{deps.map(&:first).map { Formatter.identifier(_1) }.to_sentence}",
          truncate: false
      deps.each { |dep, options| install_dependency(dep, options) }
    end

    @show_header = true unless deps.empty?
  end

  sig { params(dep: Dependency).void }
  def fetch_dependency(dep)
    df = dep.to_formula
    fi = FormulaInstaller.new(
      df,
      force_bottle:               false,
      # When fetching we don't need to recurse the dependency tree as it's already
      # been done for us in `compute_dependencies` and there's no requirement to
      # fetch in a particular order.
      # Note, this tree can vary when pouring bottles so we need to check it then.
      ignore_deps:                !pour_bottle?,
      installed_as_dependency:    true,
      include_test_formulae:      @include_test_formulae,
      build_from_source_formulae: @build_from_source_formulae,
      keep_tmp:                   keep_tmp?,
      debug_symbols:              debug_symbols?,
      force:                      force?,
      debug:                      debug?,
      quiet:                      quiet?,
      verbose:                    verbose?,
    )
    fi.prelude
    fi.fetch
  end

  sig { params(dep: Dependency, inherited_options: Options).void }
  def install_dependency(dep, inherited_options)
    df = dep.to_formula

    if df.linked_keg.directory?
      linked_keg = Keg.new(df.linked_keg.resolved_path)
      tab = Tab.for_keg(linked_keg)
      keg_had_linked_keg = true
      keg_was_linked = linked_keg.linked?
      linked_keg.unlink
    end

    if df.latest_version_installed?
      installed_keg = Keg.new(df.prefix)
      tab ||= Tab.for_keg(installed_keg)
      tmp_keg = Pathname.new("#{installed_keg}.tmp")
      installed_keg.rename(tmp_keg)
    end

    if df.tap.present? && tab.present? && (tab_tap = tab.source["tap"].presence) &&
       df.tap.to_s != tab_tap.to_s
      odie <<~EOS
        #{df} is already installed from #{tab_tap}!
        Please `brew uninstall #{df}` first."
      EOS
    end

    options = Options.new
    options |= tab.used_options if tab.present?
    options |= Tab.remap_deprecated_options(df.deprecated_options, dep.options)
    options |= inherited_options
    options &= df.options

    fi = FormulaInstaller.new(
      df,
      options:,
      link_keg:                   keg_had_linked_keg ? keg_was_linked : nil,
      installed_as_dependency:    true,
      installed_on_request:       df.any_version_installed? && tab.present? && tab.installed_on_request,
      force_bottle:               false,
      include_test_formulae:      @include_test_formulae,
      build_from_source_formulae: @build_from_source_formulae,
      keep_tmp:                   keep_tmp?,
      debug_symbols:              debug_symbols?,
      force:                      force?,
      debug:                      debug?,
      quiet:                      quiet?,
      verbose:                    verbose?,
    )
    oh1 "Installing #{formula.full_name} dependency: #{Formatter.identifier(dep.name)}"
    fi.install
    fi.finish
  rescue Exception => e # rubocop:disable Lint/RescueException
    ignore_interrupts do
      tmp_keg.rename(installed_keg.to_path) if tmp_keg && !installed_keg.directory?
      linked_keg.link(verbose: verbose?) if keg_was_linked
    end
    raise unless e.is_a? FormulaInstallationAlreadyAttemptedError

    # We already attempted to install f as part of another formula's
    # dependency tree. In that case, don't generate an error, just move on.
    nil
  else
    ignore_interrupts { tmp_keg.rmtree if tmp_keg&.directory? }
  end

  sig { void }
  def caveats
    return if only_deps?

    audit_installed if Homebrew::EnvConfig.developer?

    return if !installed_on_request? || installed_as_dependency?

    caveats = Caveats.new(formula)

    return if caveats.empty?

    @show_summary_heading = true
    ohai "Caveats", caveats.to_s
    Homebrew.messages.record_caveats(formula.name, caveats)
  end

  sig { void }
  def finish
    return if only_deps?

    ohai "Finishing up" if verbose?

    keg = Keg.new(formula.prefix)
    link(keg)

    install_service

    fix_dynamic_linkage(keg) if !@poured_bottle || !formula.bottle_specification.skip_relocation?

    Homebrew::Install.global_post_install

    if build_bottle? || skip_post_install?
      if build_bottle?
        ohai "Not running 'post_install' as we're building a bottle"
      elsif skip_post_install?
        ohai "Skipping 'post_install' on request"
      end
      puts "You can run it manually using:"
      puts "  brew postinstall #{formula.full_name}"
    else
      formula.install_etc_var
      post_install if formula.post_install_defined?
    end

    keg.prepare_debug_symbols if debug_symbols?

    # Updates the cache for a particular formula after doing an install
    CacheStoreDatabase.use(:linkage) do |db|
      break unless db.created?

      LinkageChecker.new(keg, formula, cache_db: db, rebuild_cache: true)
    end

    # Update tab with actual runtime dependencies
    tab = Tab.for_keg(keg)
    Tab.clear_cache
    f_runtime_deps = formula.runtime_dependencies(read_from_tab: false)
    tab.runtime_dependencies = Tab.runtime_deps_hash(formula, f_runtime_deps)
    tab.write

    # let's reset Utils::Git.available? if we just installed git
    Utils::Git.clear_available_cache if formula.name == "git"

    # use installed ca-certificates when it's needed and available
    if formula.name == "ca-certificates" &&
       !DevelopmentTools.ca_file_handles_most_https_certificates?
      ENV["SSL_CERT_FILE"] = ENV["GIT_SSL_CAINFO"] = formula.pkgetc/"cert.pem"
      ENV["GIT_SSL_CAPATH"] = formula.pkgetc
    end

    # use installed curl when it's needed and available
    if formula.name == "curl" &&
       !DevelopmentTools.curl_handles_most_https_certificates?
      ENV["HOMEBREW_CURL"] = formula.opt_bin/"curl"
      Utils::Curl.clear_path_cache
    end

    caveats

    ohai "Summary" if verbose? || show_summary_heading?
    puts summary

    self.class.installed << formula
  ensure
    unlock
  end

  sig { returns(String) }
  def summary
    s = +""
    s << "#{Homebrew::EnvConfig.install_badge}  " unless Homebrew::EnvConfig.no_emoji?
    s << "#{formula.prefix.resolved_path}: #{formula.prefix.abv}"
    s << ", built in #{pretty_duration build_time}" if build_time
    s.freeze
  end

  def build_time
    @build_time ||= Time.now - @start_time if @start_time && !interactive?
  end

  sig { returns(T::Array[String]) }
  def sanitized_argv_options
    args = []
    args << "--ignore-dependencies" if ignore_deps?

    if build_bottle?
      args << "--build-bottle"
      args << "--bottle-arch=#{@bottle_arch}" if @bottle_arch
    end

    args << "--git" if git?
    args << "--interactive" if interactive?
    args << "--verbose" if verbose?
    args << "--debug" if debug?
    args << "--cc=#{@cc}" if @cc
    args << "--keep-tmp" if keep_tmp?

    if debug_symbols?
      args << "--debug-symbols"
      args << "--build-from-source"
    end

    if @env.present?
      args << "--env=#{@env}"
    elsif formula.env.std? || formula.deps.select(&:build?).any? { |d| d.name == "scons" }
      args << "--env=std"
    end

    args << "--HEAD" if formula.head?

    args
  end

  sig { returns(T::Array[String]) }
  def build_argv
    sanitized_argv_options + options.as_flags
  end

  sig { void }
  def build
    FileUtils.rm_rf(formula.logs)

    @start_time = Time.now

    # 1. formulae can modify ENV, so we must ensure that each
    #    installation has a pristine ENV when it starts, forking now is
    #    the easiest way to do this
    args = [
      "nice",
      *HOMEBREW_RUBY_EXEC_ARGS,
      "--",
      HOMEBREW_LIBRARY_PATH/"build.rb",
      formula.specified_path,
    ].concat(build_argv)

    Utils.safe_fork do
      if Sandbox.available?
        sandbox = Sandbox.new
        formula.logs.mkpath
        sandbox.record_log(formula.logs/"build.sandbox.log")
        sandbox.allow_write_path(Dir.home) if interactive?
        sandbox.allow_write_temp_and_cache
        sandbox.allow_write_log(formula)
        sandbox.allow_cvs
        sandbox.allow_fossil
        sandbox.allow_write_xcode
        sandbox.allow_write_cellar(formula)
        sandbox.exec(*args)
      else
        exec(*args)
      end
    end

    formula.update_head_version

    raise "Empty installation" if !formula.prefix.directory? || Keg.new(formula.prefix).empty_installation?
  rescue Exception => e # rubocop:disable Lint/RescueException
    if e.is_a? BuildError
      e.formula = formula
      e.options = display_options(formula)
    end

    ignore_interrupts do
      # any exceptions must leave us with nothing installed
      formula.update_head_version
      formula.prefix.rmtree if formula.prefix.directory?
      formula.rack.rmdir_if_possible
    end
    raise e
  end

  sig { params(keg: Keg).void }
  def link(keg)
    Formula.clear_cache

    unless link_keg
      begin
        keg.optlink(verbose: verbose?, overwrite: overwrite?)
      rescue Keg::LinkError => e
        ofail "Failed to create #{formula.opt_prefix}"
        puts "Things that depend on #{formula.full_name} will probably not build."
        puts e
      end
      return
    end

    cask_installed_with_formula_name = begin
      Cask::CaskLoader.load(formula.name).installed?
    rescue Cask::CaskUnavailableError, Cask::CaskInvalidError
      false
    end

    if cask_installed_with_formula_name
      ohai "#{formula.name} cask is installed, skipping link."
      return
    end

    if keg.linked?
      opoo "This keg was marked linked already, continuing anyway"
      keg.remove_linked_keg_record
    end

    Homebrew::Unlink.unlink_versioned_formulae(formula, verbose: verbose?)

    link_overwrite_backup = {} # Hash: conflict file -> backup file
    backup_dir = HOMEBREW_CACHE/"Backup"

    begin
      keg.link(verbose: verbose?, overwrite: overwrite?)
    rescue Keg::ConflictError => e
      conflict_file = e.dst
      if formula.link_overwrite?(conflict_file) && !link_overwrite_backup.key?(conflict_file)
        backup_file = backup_dir/conflict_file.relative_path_from(HOMEBREW_PREFIX).to_s
        backup_file.parent.mkpath
        FileUtils.mv conflict_file, backup_file
        link_overwrite_backup[conflict_file] = backup_file
        retry
      end
      ofail "The `brew link` step did not complete successfully"
      puts "The formula built, but is not symlinked into #{HOMEBREW_PREFIX}"
      puts e
      puts
      puts "Possible conflicting files are:"
      keg.link(dry_run: true, overwrite: true, verbose: verbose?)
      @show_summary_heading = true
    rescue Keg::LinkError => e
      ofail "The `brew link` step did not complete successfully"
      puts "The formula built, but is not symlinked into #{HOMEBREW_PREFIX}"
      puts e
      puts
      puts "You can try again using:"
      puts "  brew link #{formula.name}"
      @show_summary_heading = true
    rescue Exception => e # rubocop:disable Lint/RescueException
      ofail "An unexpected error occurred during the `brew link` step"
      puts "The formula built, but is not symlinked into #{HOMEBREW_PREFIX}"
      puts e
      puts Utils::Backtrace.clean(e) if debug?
      @show_summary_heading = true
      ignore_interrupts do
        keg.unlink
        link_overwrite_backup.each do |origin, backup|
          origin.parent.mkpath
          FileUtils.mv backup, origin
        end
      end
      raise
    end

    return if link_overwrite_backup.empty?

    opoo "These files were overwritten during the `brew link` step:"
    puts link_overwrite_backup.keys
    puts
    puts "They have been backed up to: #{backup_dir}"
    @show_summary_heading = true
  end

  sig { void }
  def install_service
    if formula.service? && formula.plist
      ofail "Formula specified both service and plist"
      return
    end

    if formula.service? && formula.service.command?
      service_path = formula.systemd_service_path
      service_path.atomic_write(formula.service.to_systemd_unit)
      service_path.chmod 0644

      if formula.service.timed?
        timer_path = formula.systemd_timer_path
        timer_path.atomic_write(formula.service.to_systemd_timer)
        timer_path.chmod 0644
      end
    end

    service = if formula.service? && formula.service.command?
      formula.service.to_plist
    elsif formula.plist
      formula.plist
    end

    return unless service

    launchd_service_path = formula.launchd_service_path
    launchd_service_path.atomic_write(service)
    launchd_service_path.chmod 0644
    log = formula.var/"log"
    log.mkpath if service.include? log.to_s
  rescue Exception => e # rubocop:disable Lint/RescueException
    puts e
    ofail "Failed to install service files"
    odebug e, Utils::Backtrace.clean(e)
  end

  sig { params(keg: Keg).void }
  def fix_dynamic_linkage(keg)
    keg.fix_dynamic_linkage
  rescue Exception => e # rubocop:disable Lint/RescueException
    ofail "Failed to fix install linkage"
    puts "The formula built, but you may encounter issues using it or linking other"
    puts "formulae against it."
    odebug e, Utils::Backtrace.clean(e)
    @show_summary_heading = true
  end

  sig { void }
  def clean
    ohai "Cleaning" if verbose?
    Cleaner.new(formula).clean
  rescue Exception => e # rubocop:disable Lint/RescueException
    opoo "The cleaning step did not complete successfully"
    puts "Still, the installation was successful, so we will link it into your prefix."
    odebug e, Utils::Backtrace.clean(e)
    Homebrew.failed = true
    @show_summary_heading = true
  end

  sig { returns(Pathname) }
  def post_install_formula_path
    # Use the formula from the keg when any of the following is true:
    # * We're installing from the JSON API
    # * We're installing a local bottle file
    # * The formula doesn't exist in the tap (or the tap isn't installed)
    # * The formula in the tap has a different `pkg_version``.
    #
    # In all other cases, including if the formula from the keg is unreadable
    # (third-party taps may `require` some of their own libraries) or if there
    # is no formula present in the keg (as is the case with very old bottles),
    # use the formula from the tap.
    keg_formula_path = formula.opt_prefix/".brew/#{formula.name}.rb"
    return keg_formula_path if formula.loaded_from_api?
    return keg_formula_path if formula.local_bottle_path.present?

    tap_formula_path = formula.specified_path
    return keg_formula_path unless tap_formula_path.exist?

    begin
      keg_formula = Formulary.factory(keg_formula_path)
      tap_formula = Formulary.factory(tap_formula_path)
      return keg_formula_path if keg_formula.pkg_version != tap_formula.pkg_version

      tap_formula_path
    rescue FormulaUnavailableError, FormulaUnreadableError
      tap_formula_path
    end
  end

  sig { void }
  def post_install
    args = [
      "nice",
      *HOMEBREW_RUBY_EXEC_ARGS,
      "-I", $LOAD_PATH.join(File::PATH_SEPARATOR),
      "--",
      HOMEBREW_LIBRARY_PATH/"postinstall.rb"
    ]

    args << post_install_formula_path

    Utils.safe_fork do
      if Sandbox.available?
        sandbox = Sandbox.new
        formula.logs.mkpath
        sandbox.record_log(formula.logs/"postinstall.sandbox.log")
        sandbox.allow_write_temp_and_cache
        sandbox.allow_write_log(formula)
        sandbox.allow_write_xcode
        sandbox.deny_write_homebrew_repository
        sandbox.allow_write_cellar(formula)
        Keg::KEG_LINK_DIRECTORIES.each do |dir|
          sandbox.allow_write_path "#{HOMEBREW_PREFIX}/#{dir}"
        end
        sandbox.exec(*args)
      else
        exec(*args)
      end
    end
  rescue Exception => e # rubocop:disable Lint/RescueException
    opoo "The post-install step did not complete successfully"
    puts "You can try again using:"
    puts "  brew postinstall #{formula.full_name}"
    odebug e, Utils::Backtrace.clean(e), always_display: Homebrew::EnvConfig.developer?
    Homebrew.failed = true
    @show_summary_heading = true
  end

  sig { void }
  def fetch_dependencies
    return if ignore_deps?

    # Don't output dependencies if we're explicitly installing them.
    deps = compute_dependencies.reject do |(dep, _options)|
      self.class.fetched.include?(dep.to_formula)
    end

    return if deps.empty?

    oh1 "Fetching dependencies for #{formula.full_name}: " \
        "#{deps.map(&:first).map { Formatter.identifier(_1) }.to_sentence}",
        truncate: false

    deps.each { |(dep, _options)| fetch_dependency(dep) }
  end

  sig { returns(T.nilable(Formula)) }
  def previously_fetched_formula
    # We intentionally don't compare classes here:
    # from-API-JSON and from-source formula classes are not equal but we
    # want to equate them to be the same thing here given mixing bottle and
    # from-source installs of the same formula within the same operation
    # doesn't make sense.
    self.class.fetched.find do |fetched_formula|
      fetched_formula.full_name == formula.full_name && fetched_formula.active_spec_sym == formula.active_spec_sym
    end
  end

  sig { void }
  def fetch_bottle_tab
    @fetch_bottle_tab ||= begin
      formula.fetch_bottle_tab
      @bottle_tab_runtime_dependencies = formula.bottle_tab_attributes
                                                .fetch("runtime_dependencies", [])
                                                .each_with_object({}) { |dep, h| h[dep["full_name"]] = dep }
                                                .freeze
      true
    rescue DownloadError, ArgumentError
      @fetch_bottle_tab = true
    end
  end

  sig { void }
  def fetch
    return if previously_fetched_formula

    fetch_dependencies

    return if only_deps?

    oh1 "Fetching #{Formatter.identifier(formula.full_name)}".strip

    if pour_bottle?(output_warning: true)
      fetch_bottle_tab
    else
      @formula = Homebrew::API::Formula.source_download(formula) if formula.loaded_from_api?

      formula.fetch_patches
      formula.resources.each(&:fetch)
    end
    downloader.fetch

    self.class.fetched << formula
  end

  def downloader
    if (bottle_path = formula.local_bottle_path)
      LocalBottleDownloadStrategy.new(bottle_path)
    elsif pour_bottle?
      formula.bottle
    else
      formula
    end
  end

  sig { void }
  def pour
    HOMEBREW_CELLAR.cd do
      downloader.stage
    end

    Tab.clear_cache

    tab = Utils::Bottles.load_tab(formula)

    # fill in missing/outdated parts of the tab
    # keep in sync with Tab#to_bottle_json
    tab.used_options = []
    tab.unused_options = []
    tab.built_as_bottle = true
    tab.poured_from_bottle = true
    tab.loaded_from_api = formula.loaded_from_api?
    tab.installed_as_dependency = installed_as_dependency?
    tab.installed_on_request = installed_on_request?
    tab.time = Time.now.to_i
    tab.aliases = formula.aliases
    tab.arch = Hardware::CPU.arch
    tab.source["versions"]["stable"] = formula.stable.version&.to_s
    tab.source["versions"]["version_scheme"] = formula.version_scheme
    tab.source["path"] = formula.specified_path.to_s
    tab.source["tap_git_head"] = formula.tap&.installed? ? formula.tap&.git_head : nil
    tab.tap = formula.tap
    tab.write

    keg = Keg.new(formula.prefix)
    skip_linkage = formula.bottle_specification.skip_relocation?
    keg.replace_placeholders_with_locations(tab.changed_files, skip_linkage:)

    cellar = formula.bottle_specification.tag_to_cellar(Utils::Bottles.tag)
    return if [:any, :any_skip_relocation].include?(cellar)

    prefix = Pathname(cellar).parent.to_s
    return if cellar == HOMEBREW_CELLAR.to_s && prefix == HOMEBREW_PREFIX.to_s

    return unless ENV["HOMEBREW_RELOCATE_BUILD_PREFIX"]

    keg.relocate_build_prefix(keg, prefix, HOMEBREW_PREFIX)
  end

  sig { override.params(output: T.nilable(String)).void }
  def problem_if_output(output)
    return unless output

    opoo output
    @show_summary_heading = true
  end

  def audit_installed
    unless formula.keg_only?
      problem_if_output(check_env_path(formula.bin))
      problem_if_output(check_env_path(formula.sbin))
    end
    super
  end

  def self.locked
    @locked ||= []
  end

  private

  attr_predicate :hold_locks?

  sig { void }
  def lock
    return unless self.class.locked.empty?

    unless ignore_deps?
      formula.recursive_dependencies.each do |dep|
        self.class.locked << dep.to_formula
      end
    end
    self.class.locked.unshift(formula)
    self.class.locked.uniq!
    self.class.locked.each(&:lock)
    @hold_locks = true
  end

  sig { void }
  def unlock
    return unless hold_locks?

    self.class.locked.each(&:unlock)
    self.class.locked.clear
    @hold_locks = false
  end

  def puts_requirement_messages
    return unless @requirement_messages
    return if @requirement_messages.empty?

    $stderr.puts @requirement_messages
  end

  sig { void }
  def forbidden_license_check
    forbidden_licenses = Homebrew::EnvConfig.forbidden_licenses.to_s.dup
    SPDX::ALLOWED_LICENSE_SYMBOLS.each do |s|
      pattern = /#{s.to_s.tr("_", " ")}/i
      forbidden_licenses.sub!(pattern, s.to_s)
    end
    forbidden_licenses = forbidden_licenses.split.to_h do |license|
      [license, SPDX.license_version_info(license)]
    end

    return if forbidden_licenses.blank?
    return if ignore_deps?

    compute_dependencies.each do |(dep, _options)|
      dep_f = dep.to_formula
      next unless SPDX.licenses_forbid_installation? dep_f.license, forbidden_licenses

      raise CannotInstallFormulaError, <<~EOS
        The installation of #{formula.name} has a dependency on #{dep.name} where all
        its licenses are forbidden by HOMEBREW_FORBIDDEN_LICENSES:
          #{SPDX.license_expression_to_string dep_f.license}.
      EOS
    end

    return if only_deps?

    return unless SPDX.licenses_forbid_installation? formula.license, forbidden_licenses

    raise CannotInstallFormulaError, <<~EOS
      #{formula.name}'s licenses are all forbidden by HOMEBREW_FORBIDDEN_LICENSES:
        #{SPDX.license_expression_to_string formula.license}.
    EOS
  end
end
