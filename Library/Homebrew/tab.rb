# typed: strict
# frozen_string_literal: true

require "cxxstdlib"
require "options"
require "json"
require "development_tools"
require "cachable"

# Rather than calling `new` directly, use one of the class methods like {Tab.create}.
class AbstractTab
  extend T::Generic
  extend Cachable
  extend T::Helpers

  Cache = type_template { { fixed: T::Hash[T.any(Pathname, String), T.untyped] } }

  FILENAME = "INSTALL_RECEIPT.json"

  RuntimeDependencies = T.type_alias do
    T.nilable(T.any(T::Array[String], T::Array[T::Hash[String, T.untyped]], T::Hash[String, T.untyped],
                    T::Hash[Symbol, T.untyped]))
  end

  # Check whether the formula or cask was installed on request.
  #
  # @api internal
  sig { returns(T::Boolean) }
  attr_accessor :installed_on_request

  sig { returns(T.nilable(String)) }
  attr_accessor :homebrew_version

  sig { returns(T.nilable(Pathname)) }
  attr_accessor :tabfile

  sig { returns(T.nilable(T::Boolean)) }
  attr_accessor :loaded_from_api

  sig { returns(T.nilable(T::Boolean)) }
  attr_accessor :loaded_from_internal_api

  sig { returns(T.nilable(Integer)) }
  attr_accessor :time

  sig { returns(T.nilable(T.any(String, Symbol))) }
  attr_accessor :arch

  sig { returns(T::Hash[String, T.untyped]) }
  attr_accessor :source

  sig { returns(T.nilable(T::Hash[String, T.untyped])) }
  attr_accessor :built_on

  # Returns the formula or cask runtime dependencies.
  #
  # @api internal
  sig { returns(RuntimeDependencies) }
  attr_accessor :runtime_dependencies

  # TODO: Update attributes to only accept symbol keys (kwargs style).
  sig { params(attributes: T.any(T::Hash[String, T.untyped], T::Hash[Symbol, T.untyped])).void }
  def initialize(attributes = {})
    @installed_on_request = T.let(false, T::Boolean)
    @installed_on_request_present = T.let(false, T::Boolean)
    @homebrew_version = T.let(nil, T.nilable(String))
    @tabfile = T.let(nil, T.nilable(Pathname))
    @loaded_from_api = T.let(nil, T.nilable(T::Boolean))
    @loaded_from_internal_api = T.let(nil, T.nilable(T::Boolean))
    @time = T.let(nil, T.nilable(Integer))
    @arch = T.let(nil, T.nilable(T.any(String, Symbol)))
    @source = T.let({}, T::Hash[String, T.untyped])
    @built_on = T.let(nil, T.nilable(T::Hash[String, T.untyped]))
    @runtime_dependencies = T.let(nil, RuntimeDependencies)

    attributes.each do |key, value|
      case key.to_sym
      when :installed_on_request
        @installed_on_request = value.nil? ? false : value
        @installed_on_request_present = true
      when :changed_files
        @changed_files = T.let(value&.map { |f| Pathname(f) }, T.nilable(T::Array[Pathname]))
      else
        instance_variable_set(:"@#{key}", value)
      end
    end
  end

  # Instantiates a {Tab} for a new installation of a formula or cask.
  sig { params(formula_or_cask: T.any(Formula, Cask::Cask)).returns(T.attached_class) }
  def self.create(formula_or_cask)
    attributes = {
      "homebrew_version"         => HOMEBREW_VERSION,
      "installed_on_request"     => false,
      "loaded_from_api"          => formula_or_cask.loaded_from_api?,
      "loaded_from_internal_api" => formula_or_cask.loaded_from_internal_api?,
      "time"                     => Time.now.to_i,
      "arch"                     => Hardware::CPU.arch,
      "source"                   => {
        "tap"          => formula_or_cask.tap&.name,
        "tap_git_head" => formula_or_cask.tap_git_head,
      },
      "built_on"                 => DevelopmentTools.build_system_info,
    }

    new(attributes)
  end

  # Returns the {Tab} for a formula or cask install receipt at `path`.
  #
  # NOTE: Results are cached.
  sig { params(path: T.any(Pathname, String)).returns(T.attached_class) }
  def self.from_file(path)
    cache.fetch(path) do |p|
      content = File.read(p)
      return empty if content.blank?

      cache[p] = from_file_content(content, p)
    end
  end

  # Like {from_file}, but bypass the cache.
  sig { params(content: String, path: T.any(Pathname, String)).returns(T.attached_class) }
  def self.from_file_content(content, path)
    attributes = begin
      JSON.parse(content)
    rescue JSON::ParserError => e
      raise e, "Cannot parse #{path}: #{e}", e.backtrace
    end
    attributes["tabfile"] = path

    new(attributes)
  end

  sig { returns(T.attached_class) }
  def self.empty
    attributes = {
      "homebrew_version"         => HOMEBREW_VERSION,
      "installed_on_request"     => false,
      "loaded_from_api"          => false,
      "loaded_from_internal_api" => false,
      "time"                     => nil,
      "runtime_dependencies"     => nil,
      "arch"                     => nil,
      "source"                   => {
        "path"         => nil,
        "tap"          => nil,
        "tap_git_head" => nil,
      },
      "built_on"                 => DevelopmentTools.build_system_info,
    }

    new(attributes)
  end

  sig { params(formula: Formula, declared_deps: T::Array[String]).returns(T::Hash[String, T.untyped]) }
  def self.formula_to_dep_hash(formula, declared_deps)
    {
      "full_name"             => formula.full_name,
      "version"               => formula.version.to_s,
      "revision"              => formula.revision,
      "bottle_rebuild"        => formula.bottle&.rebuild,
      "pkg_version"           => formula.pkg_version.to_s,
      "declared_directly"     => declared_deps.include?(formula.full_name),
      "compatibility_version" => formula.compatibility_version,
    }.compact
  end
  private_class_method :formula_to_dep_hash

  sig { returns(Version) }
  def parsed_homebrew_version
    homebrew_version = self.homebrew_version
    return Version::NULL if homebrew_version.nil?

    Version.new(homebrew_version)
  end

  sig { returns(T::Boolean) }
  def installed_on_request_present? = @installed_on_request_present

  sig { returns(T.nilable(Tap)) }
  def tap
    tap_name = source["tap"]
    Tap.fetch(tap_name) if tap_name
  end

  sig { params(tap: T.nilable(T.any(Tap, String))).void }
  def tap=(tap)
    tap_name = tap.is_a?(Tap) ? tap.name : tap
    source["tap"] = tap_name
  end

  sig { void }
  def write
    tfile = tabfile
    raise "No tabfile to write to" unless tfile

    self.class.cache[tfile] = self
    tfile.atomic_write(to_json)
  end
end
require "tab/tab"
