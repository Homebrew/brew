# typed: strict
# frozen_string_literal: true

require "dependable"
require "utils"

# A dependency on another Homebrew formula.
#
# @api internal
class Dependency
  include Dependable

  sig { returns(String) }
  attr_reader :name

  sig { returns(T.nilable(Tap)) }
  attr_reader :tap

  sig { override.returns(T::Array[T.any(Symbol, String, T::Array[T.untyped])]) }
  attr_reader :tags

  sig { params(name: String, tags: T.any(String, Symbol, T::Array[T.untyped], T::Hash[Symbol, T.anything])).void }
  def initialize(name, tags = [])
    @name = name
    @tags = T.let(Array(tags), T::Array[T.any(Symbol, String)])
    @tap = T.let(nil, T.nilable(Tap))

    return unless (tap_with_name = Tap.with_formula_name(name))

    @tap, = tap_with_name
  end

  sig { override.params(other: BasicObject).returns(T::Boolean) }
  def ==(other)
    case other
    when Dependency
      name == other.name && tags == other.tags
    else false
    end
  end
  alias eql? ==

  sig { override.returns(Integer) }
  def hash
    [name, tags].hash
  end

  sig { returns(Formula) }
  def to_installed_formula
    formula = Formulary.resolve(name)
    formula.build = BuildOptions.new(options, formula.options)
    formula
  end

  sig { returns(Formula) }
  def to_formula
    formula = Formulary.factory(name, warn: false)
    formula.build = BuildOptions.new(options, formula.options)
    formula
  end

  sig {
    params(
      minimum_version:               T.nilable(Version),
      minimum_revision:              T.nilable(Integer),
      minimum_compatibility_version: T.nilable(Integer),
      bottle_os_version:             T.nilable(String),
    ).returns(T::Boolean)
  }
  def installed?(minimum_version: nil, minimum_revision: nil, minimum_compatibility_version: nil,
                 bottle_os_version: nil)
    formula = begin
      to_installed_formula
    rescue FormulaUnavailableError
      nil
    end
    return false unless formula

    # If the opt prefix doesn't exist: we likely have an incomplete installation.
    return false unless formula.opt_prefix.exist?

    return true if formula.latest_version_installed?

    return false if minimum_version.blank?

    installed_keg = formula.any_installed_keg
    return false unless installed_keg

    # If the keg name doesn't match, we may have moved from an alias to a full formula and need to upgrade.
    return false unless formula.possible_names.include?(installed_keg.name)

    installed_version = installed_keg.version

    # If both the formula and minimum dependency have a compatibility_version set,
    # and they match, the dependency is satisfied regardless of version/revision.
    if minimum_compatibility_version.present? && formula.compatibility_version.present?
      installed_tab = Tab.for_keg(installed_keg)
      installed_compatibility_version = installed_tab.source.dig("versions", "compatibility_version")

      # If installed version has same compatibility_version as required, it's compatible
      return true if installed_compatibility_version == minimum_compatibility_version &&
                     formula.compatibility_version == minimum_compatibility_version
    end

    # Tabs prior to 4.1.18 did not have revision or pkg_version fields.
    # As a result, we have to be more conversative when we do not have
    # a minimum revision from the tab and assume that if the formula has a
    # the same version and a non-zero revision that it needs upgraded.
    if minimum_revision.present?
      minimum_pkg_version = PkgVersion.new(minimum_version, minimum_revision)
      installed_version >= minimum_pkg_version
    elsif installed_version.version == minimum_version
      formula.revision.zero?
    else
      installed_version.version > minimum_version
    end
  end

  sig {
    params(
      minimum_version:               T.nilable(Version),
      minimum_revision:              T.nilable(Integer),
      minimum_compatibility_version: T.nilable(Integer),
      bottle_os_version:             T.nilable(String),
    ).returns(T::Boolean)
  }
  def satisfied?(minimum_version: nil, minimum_revision: nil,
                 minimum_compatibility_version: nil, bottle_os_version: nil)
    installed?(minimum_version:, minimum_revision:, minimum_compatibility_version:, bottle_os_version:) &&
      missing_options.empty?
  end

  sig { returns(Options) }
  def missing_options
    formula = to_installed_formula
    required = options
    required &= formula.options.to_a
    required -= Tab.for_formula(formula).used_options
    required
  end

  sig { override.returns(T::Array[String]) }
  def option_names
    [Utils.name_from_full_name(name)].freeze
  end

  sig { overridable.returns(T::Boolean) }
  def uses_from_macos?
    false
  end

  sig { returns(String) }
  def to_s = name

  sig { returns(String) }
  def inspect
    "#<#{self.class.name}: #{name.inspect} #{tags.inspect}>"
  end

  sig { params(formula: Formula).returns(T.self_type) }
  def dup_with_formula_name(formula)
    self.class.new(formula.full_name.to_s, tags)
  end

  class << self
    # Expand the dependencies of each dependent recursively, optionally yielding
    # `[dependent, dep]` pairs to allow callers to apply arbitrary filters to
    # the list.
    # The default filter, which is applied when a block is not given, omits
    # optionals and recommends based on what the dependent has asked for
    #
    # @api internal
    T::Sig::WithoutRuntime.sig {
      params(
        # CaskDependent may not be initialized yet, so we don't use a runtime sig
        dependent:       T.any(Formula, CaskDependent),
        deps:            T::Array[Dependency],
        cache_key:       T.nilable(String),
        cache_timestamp: T.nilable(Time),
        block:           T.nilable(T.proc.params(arg0: T.any(Formula, CaskDependent),
                                                 arg1: Dependency).returns(T.nilable(Symbol))),
      ).returns(T::Array[Dependency])
    }
    def expand(dependent, deps = dependent.deps, cache_key: nil, cache_timestamp: nil, &block)
      # Keep track dependencies to avoid infinite cyclic dependency recursion.
      @expand_stack ||= T.let([], T.nilable(T::Array[T.any(String, Symbol)]))
      @expand_stack.push dependent.name

      begin
        if cache_key.present?
          cache_key = "#{cache_key}-#{cache_timestamp}" if cache_timestamp

          if (entry = cache(cache_key, cache_timestamp:)[cache_id dependent])
            return entry.dup
          end
        end

        expanded_deps = []

        deps.each do |dep|
          next if dependent.name == dep.name

          case action(dependent, dep, &block)
          when Dependable::PRUNE
            next
          when Dependable::SKIP
            next if @expand_stack.include? dep.name

            expanded_deps.concat(expand(dep.to_formula, cache_key:, &block))
          when Dependable::KEEP_BUT_PRUNE_RECURSIVE_DEPS
            expanded_deps << dep
          else
            next if @expand_stack.include? dep.name

            dep_formula = dep.to_formula
            expanded_deps.concat(expand(dep_formula, cache_key:, &block))

            # Fixes names for renamed/aliased formulae.
            dep = dep.dup_with_formula_name(dep_formula)
            expanded_deps << dep
          end
        end

        expanded_deps = merge_repeats(expanded_deps)
        cache(cache_key, cache_timestamp:)[cache_id dependent] = expanded_deps.dup if cache_key.present?
        expanded_deps
      ensure
        @expand_stack.pop
      end
    end

    # CaskDependent may not be initialized yet, so we don't use a runtime sig
    T::Sig::WithoutRuntime.sig {
      params(
        dependent: T.any(Formula, CaskDependent),
        dep:       Dependency,
        block:     T.nilable(T.proc.params(arg0: T.any(Formula, CaskDependent),
                                           arg1: Dependency).returns(T.nilable(Symbol))),
      ).returns(T.nilable(Symbol))
    }
    def action(dependent, dep, &block)
      if block
        yield dependent, dep
      elsif dep.optional? || dep.recommended?
        Dependable::PRUNE unless T.cast(dependent, Formula).build.with?(dep)
      end
    end

    sig { params(all: T::Array[Dependency]).returns(T::Array[Dependency]) }
    def merge_repeats(all)
      grouped = all.group_by(&:name)

      all.map(&:name).uniq.filter_map do |name|
        deps = grouped.fetch(name)
        dep  = deps.first
        next unless dep

        tags = merge_tags(deps)
        kwargs = {}
        kwargs[:bounds] = T.cast(dep, UsesFromMacOSDependency).bounds if dep.uses_from_macos?
        dep.class.new(name, tags, **kwargs)
      end
    end

    sig { params(key: T.nilable(String), cache_timestamp: T.nilable(Time)).returns(T::Hash[T.any(String, Symbol), T.untyped]) }
    def cache(key, cache_timestamp: nil)
      @cache = T.let(@cache, T.nilable(T::Hash[Symbol, T.untyped]))
      @cache ||= { timestamped: {}, not_timestamped: {} }

      if cache_timestamp
        @cache[:timestamped][cache_timestamp] ||= {}
        @cache[:timestamped][cache_timestamp][key] ||= {}
      else
        @cache[:not_timestamped][key] ||= {}
      end
    end

    sig { void }
    def clear_cache
      return unless @cache

      # No need to clear the timestamped cache as it's timestamped, and doing so causes problems in `expand`.
      # See https://github.com/Homebrew/brew/pull/20896#issuecomment-3419257460
      @cache[:not_timestamped].clear
    end

    sig { params(key: T.nilable(String), cache_timestamp: T.nilable(Time)).void }
    def delete_timestamped_cache_entry(key, cache_timestamp)
      return unless @cache
      return unless (timestamp_entry = @cache[:timestamped][cache_timestamp])

      timestamp_entry.delete(key)
      @cache[:timestamped].delete(cache_timestamp) if timestamp_entry.empty?
    end

    private

    # CaskDependent may not be initialized yet, so we don't use a runtime sig
    T::Sig::WithoutRuntime.sig { params(dependent: T.any(Formula, CaskDependent)).returns(String) }
    def cache_id(dependent)
      "#{dependent.full_name}_#{dependent.class}"
    end

    sig { params(deps: T::Array[Dependency]).returns(T::Array[T.any(String, Symbol)]) }
    def merge_tags(deps)
      other_tags = T.let(deps.flat_map(&:option_tags).uniq, T::Array[T.any(String, Symbol)])
      other_tags << :test if deps.flat_map(&:tags).include?(:test)
      merge_necessity(deps) + merge_temporality(deps) + other_tags
    end

    sig { params(deps: T::Array[Dependency]).returns(T::Array[Symbol]) }
    def merge_necessity(deps)
      # Cannot use `deps.any?(&:required?)` here due to its definition.
      if deps.any? { |dep| !dep.recommended? && !dep.optional? }
        [] # Means required dependency.
      elsif deps.any?(&:recommended?)
        [:recommended]
      else # deps.all?(&:optional?)
        [:optional]
      end
    end

    sig { params(deps: T::Array[Dependency]).returns(T::Array[Symbol]) }
    def merge_temporality(deps)
      new_tags = []
      new_tags << :build if deps.all?(&:build?)
      new_tags << :implicit if deps.all?(&:implicit?)
      new_tags
    end
  end
end

# A dependency that's marked as "installed" on macOS
class UsesFromMacOSDependency < Dependency # rubocop:todo Style/OneClassPerFile
  sig { returns(T::Hash[Symbol, Symbol]) }
  attr_reader :bounds

  sig { params(name: String, tags: T::Array[T.any(String, Symbol, T::Array[T.untyped])], bounds: T::Hash[Symbol, Symbol]).void }
  def initialize(name, tags = [], bounds:)
    super(name, tags)

    @bounds = bounds
  end

  sig { override.params(other: BasicObject).returns(T::Boolean) }
  def ==(other)
    case other
    when UsesFromMacOSDependency
      name == other.name && tags == other.tags && bounds == other.bounds
    else false
    end
  end

  sig { override.returns(Integer) }
  def hash
    [name, tags, bounds].hash
  end

  sig {
    params(
      minimum_version:               T.nilable(Version),
      minimum_revision:              T.nilable(Integer),
      minimum_compatibility_version: T.nilable(Integer),
      bottle_os_version:             T.nilable(String),
    ).returns(T::Boolean)
  }
  def installed?(minimum_version: nil, minimum_revision: nil, minimum_compatibility_version: nil,
                 bottle_os_version: nil)
    use_macos_install?(bottle_os_version:) || super
  end

  sig { params(bottle_os_version: T.nilable(String)).returns(T::Boolean) }
  def use_macos_install?(bottle_os_version: nil)
    # Check whether macOS is new enough for dependency to not be required.
    if Homebrew::SimulateSystem.simulating_or_running_on_macos?
      # If there's no since bound, the dependency is always available from macOS
      since_os_bounds = bounds[:since]
      return true if since_os_bounds.blank?

      # When installing a bottle built on an older macOS version, use that version
      # to determine if the dependency should come from macOS or Homebrew
      effective_os = if bottle_os_version.present? &&
                        bottle_os_version.start_with?("macOS ")
        # bottle_os_version is a string like "14" for Sonoma, "15" for Sequoia
        # Convert it to a MacOS version symbol for comparison
        MacOSVersion.new(bottle_os_version.delete_prefix("macOS "))
      elsif Homebrew::SimulateSystem.current_os == :macos
        # Assume the oldest macOS version when simulating a generic macOS version
        # Version::NULL is always treated as less than any other version.
        Version::NULL
      else
        MacOSVersion.from_symbol(Homebrew::SimulateSystem.current_os)
      end

      since_os = begin
        MacOSVersion.from_symbol(since_os_bounds)
      rescue MacOSVersion::Error
        # If we can't parse the bound, it means it's an unsupported macOS version
        # so let's default to the oldest possible macOS version
        Version::NULL
      end
      return true if effective_os >= since_os
    end

    false
  end

  sig { override.returns(T::Boolean) }
  def uses_from_macos?
    true
  end

  sig { override.params(formula: Formula).returns(T.self_type) }
  def dup_with_formula_name(formula)
    self.class.new(formula.full_name.to_s, tags, bounds:)
  end

  sig { returns(String) }
  def inspect
    "#<#{self.class.name}: #{name.inspect} #{tags.inspect} #{bounds.inspect}>"
  end
end
