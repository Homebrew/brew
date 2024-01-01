# typed: true
# frozen_string_literal: true

require "requirement"

# A requirement on macOS.
#
# @api private
class MacOSRequirement < Requirement
  fatal true

  attr_reader :comparator, :version

  # TODO: when Yosemite is removed here, keep these around as empty arrays so we
  # can keep the deprecation/disabling code the same.
  DISABLED_MACOS_VERSIONS = [
    :yosemite,
  ].freeze
  DEPRECATED_MACOS_VERSIONS = [].freeze

  def initialize(tags = [], comparator: ">=")
    @version = begin
      if comparator == "==" && tags.first.respond_to?(:map)
        tags.first.map { |s| MacOSVersion.from_symbol(s) }
      else
        MacOSVersion.from_symbol(tags.first) unless tags.empty?
      end
    rescue MacOSVersion::Error => e
      if DISABLED_MACOS_VERSIONS.include?(e.version)
        # This odisabled should stick around indefinitely.
        odisabled "`depends_on macos: :#{e.version}`"
      elsif DEPRECATED_MACOS_VERSIONS.include?(e.version)
        # This odeprecated should stick around indefinitely.
        odeprecated "`depends_on macos: :#{e.version}`"
      else
        raise
      end

      # Array of versions: remove the bad ones and try again.
      if tags.first.respond_to?(:reject)
        tags = [tags.first.reject { |s| s == e.version }, tags[1..]]
        retry
      end

      # Otherwise fallback to the oldest allowed if comparator is >=.
      MacOSVersion.new(HOMEBREW_MACOS_OLDEST_ALLOWED) if comparator == ">="
    end

    @comparator = comparator
    super(tags.drop(1))
  end

  def version_specified?
    @version.present?
  end

  satisfy(build_env: false) do
    T.bind(self, MacOSRequirement)
    next Array(@version).any? { |v| OS::Mac.version.compare(@comparator, v) } if OS.mac? && version_specified?
    next true if OS.mac?
    next true if @version

    false
  end

  def message(type: :formula)
    return "macOS is required for this software." unless version_specified?

    case @comparator
    when ">="
      "This software does not run on macOS versions older than #{@version.pretty_name}."
    when "<="
      case type
      when :formula
        <<~EOS
          This formula either does not compile or function as expected on macOS
          versions newer than #{@version.pretty_name} due to an upstream incompatibility.
        EOS
      when :cask
        "This cask does not run on macOS versions newer than #{@version.pretty_name}."
      end
    else
      if @version.respond_to?(:to_ary)
        *versions, last = @version.map(&:pretty_name)
        return "This software does not run on macOS versions other than #{versions.join(", ")} and #{last}."
      end

      "This software does not run on macOS versions other than #{@version.pretty_name}."
    end
  end

  def ==(other)
    super(other) && comparator == other.comparator && version == other.version
  end
  alias eql? ==

  def hash
    [super, comparator, version].hash
  end

  sig { returns(String) }
  def inspect
    "#<#{self.class.name}: version#{@comparator}#{@version.to_s.inspect} #{tags.inspect}>"
  end

  sig { returns(String) }
  def display_s
    if version_specified?
      if @version.respond_to?(:to_ary)
        "macOS #{@comparator} #{version.join(" / ")} (or Linux)"
      else
        "macOS #{@comparator} #{@version} (or Linux)"
      end
    else
      "macOS"
    end
  end

  def to_json(options)
    comp = @comparator.to_s
    return { comp => @version.map(&:to_s) }.to_json(options) if @version.is_a?(Array)

    { comp => [@version.to_s] }.to_json(options)
  end
end
