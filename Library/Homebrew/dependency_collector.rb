# typed: strict
# frozen_string_literal: true

require "dependency"
require "dependencies"
require "requirement"
require "requirements"
require "cachable"

# A dependency is a formula that another formula needs to install.
# A requirement is something other than a formula that another formula
# needs to be present. This includes external language modules,
# command-line tools in the path, or any arbitrary predicate.
#
# The `depends_on` method in the formula DSL is used to declare
# dependencies and requirements.

# This class is used by `depends_on` in the formula DSL to turn dependency
# specifications into the proper kinds of dependencies and requirements.
class DependencyCollector
  extend Cachable

  sig { returns(Dependencies) }
  attr_reader :deps

  sig { returns(Requirements) }
  attr_reader :requirements

  sig { void }
  def initialize
    # Ensure this is synced with `initialize_dup` and `freeze` (excluding simple objects like integers and booleans)
    @deps = T.let(Dependencies.new, Dependencies)
    @requirements = T.let(Requirements.new, Requirements)

    init_global_dep_tree_if_needed!
  end

  sig { override.params(other: DependencyCollector).void }
  def initialize_dup(other)
    super
    @deps = @deps.dup
    @requirements = @requirements.dup
  end

  sig { void }
  def freeze
    @deps.freeze
    @requirements.freeze
    super
  end

  sig { params(spec: T.untyped).returns(T.untyped) }
  def add(spec)
    case dep = fetch(spec)
    when Array
      dep.compact.each { |dep| @deps << dep }
    when Dependency
      @deps << dep
    when Requirement
      @requirements << dep
    when nil
      # no-op when we have a nil value
      nil
    else
      raise ArgumentError, "DependencyCollector#add passed something that isn't a Dependency or Requirement!"
    end
    dep
  end

  sig { params(spec: T.untyped).returns(T.untyped) }
  def fetch(spec)
    self.class.cache.fetch(cache_key(spec)) { |key| self.class.cache[key] = build(spec) }
  end

  sig { params(spec: T.untyped).returns(T.untyped) }
  def cache_key(spec)
    if spec.is_a?(Resource)
      if spec.download_strategy <= CurlDownloadStrategy
        return "#{spec.download_strategy}#{File.extname(T.must(spec.url)).split("?").first}"
      end

      return spec.download_strategy
    end
    spec
  end

  sig { params(spec: T.untyped).returns(T.untyped) }
  def build(spec)
    spec, tags = spec.is_a?(Hash) ? spec.first : spec
    parse_spec(spec, Array(tags))
  end

  sig { params(related_formula_names: T::Set[String]).returns(T.nilable(Dependency)) }
  def gcc_dep_if_needed(related_formula_names); end

  sig { params(related_formula_names: T::Set[String]).returns(T.nilable(Dependency)) }
  def glibc_dep_if_needed(related_formula_names); end

  sig { params(tags: T::Array[T.any(String, Symbol)]).returns(T.nilable(Dependency)) }
  def git_dep_if_needed(tags)
    require "utils/git"
    return if Utils::Git.available?

    Dependency.new("git", [*tags, :implicit])
  end

  sig { params(tags: T::Array[T.any(String, Symbol)]).returns(Dependency) }
  def curl_dep_if_needed(tags)
    Dependency.new("curl", [*tags, :implicit])
  end

  sig { params(tags: T::Array[T.any(String, Symbol)]).returns(T.nilable(Dependency)) }
  def subversion_dep_if_needed(tags)
    require "utils/svn"
    return if Utils::Svn.available?

    Dependency.new("subversion", [*tags, :implicit])
  end

  sig { params(tags: T::Array[T.any(String, Symbol)]).returns(T.nilable(Dependency)) }
  def cvs_dep_if_needed(tags)
    Dependency.new("cvs", [*tags, :implicit]) unless which("cvs")
  end

  sig { params(tags: T::Array[T.any(String, Symbol)]).returns(T.nilable(Dependency)) }
  def xz_dep_if_needed(tags)
    Dependency.new("xz", [*tags, :implicit]) unless which("xz")
  end

  sig { params(tags: T::Array[T.any(String, Symbol)]).returns(T.nilable(Dependency)) }
  def zstd_dep_if_needed(tags)
    Dependency.new("zstd", [*tags, :implicit]) unless which("zstd")
  end

  sig { params(tags: T::Array[T.any(String, Symbol)]).returns(T.nilable(Dependency)) }
  def unzip_dep_if_needed(tags)
    Dependency.new("unzip", [*tags, :implicit]) unless which("unzip")
  end

  sig { params(tags: T::Array[T.any(String, Symbol)]).returns(T.nilable(Dependency)) }
  def bzip2_dep_if_needed(tags)
    Dependency.new("bzip2", [*tags, :implicit]) unless which("bzip2")
  end

  sig { returns(T::Boolean) }
  def self.tar_needs_xz_dependency?
    !new.xz_dep_if_needed([]).nil?
  end

  private

  sig { void }
  def init_global_dep_tree_if_needed!; end

  sig {
    params(spec: T.any(String, Resource, Symbol, Requirement, Dependency, T::Class[Requirement]),
           tags: T::Array[T.any(String, Symbol)]).returns(T.nilable(T.any(Dependency, Requirement, T::Array[T.untyped])))
  }
  def parse_spec(spec, tags)
    raise ArgumentError, "Implicit dependencies cannot be manually specified" if tags.include?(:implicit)

    case spec
    when String
      parse_string_spec(spec, tags)
    when Resource
      resource_dep(spec, tags)
    when Symbol
      parse_symbol_spec(spec, tags)
    when Requirement, Dependency
      spec
    when Class
      parse_class_spec(spec, tags)
    end
  end

  sig { params(spec: String, tags: T::Array[T.any(String, Symbol)]).returns(Dependency) }
  def parse_string_spec(spec, tags)
    Dependency.new(spec, tags)
  end

  sig { params(spec: Symbol, tags: T::Array[T.any(String, Symbol)]).returns(Requirement) }
  def parse_symbol_spec(spec, tags)
    # When modifying this list of supported requirements, consider
    # whether `Homebrew::API::Formula::FormulaStructGenerator::API_SUPPORTED_REQUIREMENTS` should also be changed.
    case spec
    when :arch          then ArchRequirement.new(T.cast(tags, T::Array[Symbol]))
    when :codesign      then CodesignRequirement.new(tags)
    when :linux         then LinuxRequirement.new(tags)
    when :macos         then MacOSRequirement.new(tags)
    when :maximum_macos then MacOSRequirement.new(tags, comparator: "<=")
    when :xcode         then XcodeRequirement.new(tags)
    else
      raise ArgumentError, "Unsupported special dependency: #{spec.inspect}"
    end
  end

  sig { params(spec: T::Class[Requirement], tags: T::Array[T.any(String, Symbol)]).returns(Requirement) }
  def parse_class_spec(spec, tags)
    raise TypeError, "#{spec.inspect} is not a Requirement subclass" unless spec < Requirement

    spec.new(tags)
  end

  sig { params(spec: Resource, tags: T::Array[T.any(String, Symbol)]).returns(T.nilable(T.any(Dependency, T::Array[T.nilable(Dependency)]))) }
  def resource_dep(spec, tags)
    tags << :build << :test
    strategy = spec.download_strategy
    return if strategy.nil?

    if strategy <= HomebrewCurlDownloadStrategy
      [curl_dep_if_needed(tags), parse_url_spec(T.must(spec.url), tags)]
    elsif strategy <= NoUnzipCurlDownloadStrategy
      # ensure NoUnzip never adds any dependencies
    elsif strategy <= CurlDownloadStrategy
      parse_url_spec(T.must(spec.url), tags)
    elsif strategy <= GitDownloadStrategy
      git_dep_if_needed(tags)
    elsif strategy <= SubversionDownloadStrategy
      subversion_dep_if_needed(tags)
    elsif strategy <= MercurialDownloadStrategy
      Dependency.new("mercurial", [*tags, :implicit])
    elsif strategy <= FossilDownloadStrategy
      Dependency.new("fossil", [*tags, :implicit])
    elsif strategy <= BazaarDownloadStrategy
      Dependency.new("breezy", [*tags, :implicit])
    elsif strategy <= CVSDownloadStrategy
      cvs_dep_if_needed(tags)
    elsif strategy < AbstractDownloadStrategy
      # allow unknown strategies to pass through
    else
      raise TypeError, "#{strategy.inspect} is not an AbstractDownloadStrategy subclass"
    end
  end

  sig { params(url: String, tags: T::Array[T.any(String, Symbol)]).returns(T.nilable(Dependency)) }
  def parse_url_spec(url, tags)
    case File.extname(url)
    when ".xz"          then xz_dep_if_needed(tags)
    when ".zst"         then zstd_dep_if_needed(tags)
    when ".zip"         then unzip_dep_if_needed(tags)
    when ".bz2"         then bzip2_dep_if_needed(tags)
    when ".lha", ".lzh" then Dependency.new("lha", [*tags, :implicit])
    when ".lz"          then Dependency.new("lzip", [*tags, :implicit])
    when ".rar"         then Dependency.new("libarchive", [*tags, :implicit])
    when ".7z"          then Dependency.new("p7zip", [*tags, :implicit])
    end
  end
end

require "extend/os/dependency_collector"
