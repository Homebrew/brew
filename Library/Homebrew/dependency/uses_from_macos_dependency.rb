# typed: strict
# frozen_string_literal: true

# A dependency that's marked as "installed" on macOS
class UsesFromMacOSDependency < Dependency
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
  alias eql? ==

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
