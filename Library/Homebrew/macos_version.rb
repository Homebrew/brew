# typed: strong
# frozen_string_literal: true

require "version"

# A macOS version.
class MacOSVersion < Version
  # Raised when a macOS version is unsupported.
  class Error < RuntimeError
    sig { returns(T.nilable(T.any(String, Symbol))) }
    attr_reader :version

    sig { params(version: T.nilable(T.any(String, Symbol))).void }
    def initialize(version)
      @version = version
      super "unknown or unsupported macOS version: #{version.inspect}"
    end
  end

  # NOTE: When removing symbols here, ensure that they are added
  #       to `DEPRECATED_MACOS_VERSIONS` in `MacOSRequirement`.
  SYMBOLS = T.let({
    tahoe:       "26",
    sequoia:     "15",
    sonoma:      "14",
    ventura:     "13",
    monterey:    "12",
    big_sur:     "11",
    catalina:    "10.15",
    mojave:      "10.14",
    high_sierra: "10.13",
    sierra:      "10.12",
    el_capitan:  "10.11",
  }.freeze, T::Hash[Symbol, String])

  sig { params(macos_version: MacOSVersion).returns(Version) }
  def self.kernel_major_version(macos_version)
    version_major = macos_version.major.to_i
    if version_major >= 26
      Version.new((version_major - 1).to_s)
    elsif version_major > 10
      Version.new((version_major + 9).to_s)
    else
      version_minor = macos_version.minor.to_i
      Version.new((version_minor + 4).to_s)
    end
  end

  sig { params(version: Symbol).returns(T.attached_class) }
  def self.from_symbol(version)
    str = SYMBOLS.fetch(version) { raise MacOSVersion::Error, version }
    new(str)
  end

  sig { params(version: T.nilable(String)).void }
  def initialize(version)
    raise MacOSVersion::Error, version unless /\A\d{2,}(?:\.\d+){0,2}\z/.match?(version)

    super(T.must(version))

    @comparison_cache = T.let({}, T::Hash[T.untyped, T.nilable(Integer)])
    @pretty_name = T.let(nil, T.nilable(String))
    @sym = T.let(nil, T.nilable(Symbol))
  end

  sig { override.params(other: T.untyped).returns(T.nilable(Integer)) }
  def <=>(other)
    return @comparison_cache[other] if @comparison_cache.key?(other)

    result = case other
    when Symbol
      if SYMBOLS.key?(other) && to_sym == other
        0
      else
        v = SYMBOLS.fetch(other) { other.to_s }
        super(v)
      end
    else
      super
    end

    @comparison_cache[other] = result unless frozen?

    result
  end

  sig { returns(T.self_type) }
  def strip_patch
    return self if null?

    # Big Sur is 11.x but Catalina is 10.15.x.
    if T.must(major) >= 11
      self.class.new(major.to_s)
    else
      major_minor
    end
  end

  sig { returns(Symbol) }
  def to_sym
    return @sym if @sym

    sym = SYMBOLS.invert.fetch(strip_patch.to_s, :dunno)

    @sym = sym unless frozen?

    sym
  end

  sig { returns(String) }
  def pretty_name
    return @pretty_name if @pretty_name

    pretty_name = to_sym.to_s.split("_").map(&:capitalize).join(" ").freeze

    @pretty_name = pretty_name unless frozen?

    pretty_name
  end

  sig { returns(String) }
  def inspect
    "#<#{self.class.name}: #{to_s.inspect}>"
  end

  sig { returns(T::Boolean) }
  def outdated_release?
    self < HOMEBREW_MACOS_OLDEST_SUPPORTED
  end

  sig { returns(T::Boolean) }
  def prerelease?
    self >= HOMEBREW_MACOS_NEWEST_UNSUPPORTED
  end

  sig { returns(T::Boolean) }
  def unsupported_release?
    outdated_release? || prerelease?
  end

  sig { returns(T::Boolean) }
  def requires_nehalem_cpu?
    return false if null?

    require "hardware"

    return Hardware.oldest_cpu(self) == :nehalem if Hardware::CPU.intel?

    raise ArgumentError, "Unexpected architecture: #{Hardware::CPU.arch}. This only works with Intel architecture."
  end
  # https://en.wikipedia.org/wiki/Nehalem_(microarchitecture)
  alias requires_sse4? requires_nehalem_cpu?
  alias requires_sse41? requires_nehalem_cpu?
  alias requires_sse42? requires_nehalem_cpu?
  alias requires_popcnt? requires_nehalem_cpu?

  # Represents the absence of a version.
  #
  # NOTE: Constructor needs to called with an arbitrary macOS-like version which is then set to `nil`.
  NULL = T.let(MacOSVersion.new("10.0").tap do |v|
    T.let(v, MacOSVersion).instance_variable_set(:@version, nil)
  end.freeze, MacOSVersion)
end
