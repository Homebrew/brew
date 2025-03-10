# typed: strict
# frozen_string_literal: true

require "cache_store"
require "did_you_mean"
require "formula_support"
require "lock_file"
require "formula_pin"
require "hardware"
require "utils"
require "utils/bottles"
require "utils/gzip"
require "utils/inreplace"
require "utils/shebang"
require "utils/shell"
require "utils/git_repository"
require "build_environment"
require "build_options"
require "formulary"
require "software_spec"
require "bottle"
require "pour_bottle_check"
require "head_software_spec"
require "bottle_specification"
require "livecheck"
require "service"
require "install_renamed"
require "pkg_version"
require "keg"
require "migrator"
require "linkage_checker"
require "extend/ENV"
require "language/java"
require "language/python"
require "tab"
require "mktemp"
require "find"
require "utils/spdx"
require "extend/on_system"
require "api"
require "extend/api_hashable"

# A formula provides instructions and metadata for Homebrew to install a piece
# of software. Every Homebrew formula is a {Formula}.
# All subclasses of {Formula} (and all Ruby classes) have to be named
# `UpperCase` and `not-use-dashes`.
# A formula specified in `this-formula.rb` should have a class named
# `ThisFormula`. Homebrew does enforce that the name of the file and the class
# correspond.
# Make sure you check with `brew search` that the name is free!
# @abstract
# @see SharedEnvExtension
# @see Pathname
# @see https://www.rubydoc.info/stdlib/fileutils FileUtils
# @see https://docs.brew.sh/Formula-Cookbook Formula Cookbook
# @see https://rubystyle.guide Ruby Style Guide
#
# ### Example
#
# ```ruby
# class Wget < Formula
#   homepage "https://www.gnu.org/software/wget/"
#   url "https://ftp.gnu.org/gnu/wget/wget-1.15.tar.gz"
#   sha256 "52126be8cf1bddd7536886e74c053ad7d0ed2aa89b4b630f76785bac21695fcd"
#
#   def install
#     system "./configure", "--prefix=#{prefix}"
#     system "make", "install"
#   end
# end
# ```
class Formula
  include FileUtils
  include Utils::Shebang
  include Utils::Shell
  include Context
  include OnSystem::MacOSAndLinux
  include Homebrew::Livecheck::Constants
  extend Forwardable
  extend Cachable
  extend APIHashable
  extend T::Helpers

  abstract!

  SUPPORTED_NETWORK_ACCESS_PHASES = [:build, :test, :postinstall].freeze
  private_constant :SUPPORTED_NETWORK_ACCESS_PHASES
  DEFAULT_NETWORK_ACCESS_ALLOWED = true
  private_constant :DEFAULT_NETWORK_ACCESS_ALLOWED

  # The name of this {Formula}.
  # e.g. `this-formula`
  #
  # @api public
  sig { returns(String) }
  attr_reader :name

  # The path to the alias that was used to identify this {Formula}.
  # e.g. `/usr/local/Library/Taps/homebrew/homebrew-core/Aliases/another-name-for-this-formula`
  sig { returns(T.nilable(Pathname)) }
  attr_reader :alias_path

  # The name of the alias that was used to identify this {Formula}.
  # e.g. `another-name-for-this-formula`
  sig { returns(T.nilable(String)) }
  attr_reader :alias_name

  # The fully-qualified name of this {Formula}.
  # For core formulae it's the same as {#name}.
  # e.g. `homebrew/tap-name/this-formula`
  #
  # @api public
  sig { returns(String) }
  attr_reader :full_name

  # The fully-qualified alias referring to this {Formula}.
  # For core formulae it's the same as {#alias_name}.
  # e.g. `homebrew/tap-name/another-name-for-this-formula`
  sig { returns(T.nilable(String)) }
  attr_reader :full_alias_name

  # The full path to this {Formula}.
  # e.g. `/usr/local/Library/Taps/homebrew/homebrew-core/Formula/t/this-formula.rb`
  #
  # @api public
  sig { returns(Pathname) }
  attr_reader :path

  # The {Tap} instance associated with this {Formula}.
  # If it's `nil`, then this formula is loaded from a path or URL.
  #
  # @api internal
  sig { returns(T.nilable(Tap)) }
  attr_reader :tap

  # The stable (and default) {SoftwareSpec} for this {Formula}.
  # This contains all the attributes (e.g. URL, checksum) that apply to the
  # stable version of this formula.
  #
  # @api internal
  sig { returns(T.nilable(SoftwareSpec)) }
  attr_reader :stable

  # The HEAD {SoftwareSpec} for this {Formula}.
  # Installed when using `brew install --HEAD`.
  # This is always installed with the version `HEAD` and taken from the latest
  # commit in the version control system.
  # `nil` if there is no HEAD version.
  #
  # @see #stable
  sig { returns(T.nilable(SoftwareSpec)) }
  attr_reader :head

  # The currently active {SoftwareSpec}.
  # @see #determine_active_spec
  sig { returns(SoftwareSpec) }
  attr_reader :active_spec

  protected :active_spec

  # A symbol to indicate currently active {SoftwareSpec}.
  # It's either :stable or :head
  # @see #active_spec
  sig { returns(Symbol) }
  attr_reader :active_spec_sym

  # most recent modified time for source files
  sig { returns(T.nilable(Time)) }
  attr_reader :source_modified_time

  # Used for creating new Homebrew versions of software without new upstream
  # versions.
  # @see .revision=
  sig { returns(Integer) }
  attr_reader :revision

  # Used to change version schemes for packages.
  # @see .version_scheme=
  sig { returns(Integer) }
  attr_reader :version_scheme

  # The current working directory during builds.
  # Will only be non-`nil` inside {#install}.
  sig { returns(T.nilable(Pathname)) }
  attr_reader :buildpath

  # The current working directory during tests.
  # Will only be non-`nil` inside {.test}.
  sig { returns(T.nilable(Pathname)) }
  attr_reader :testpath

  # When installing a bottle (binary package) from a local path this will be
  # set to the full path to the bottle tarball. If not, it will be `nil`.
  sig { returns(T.nilable(Pathname)) }
  attr_accessor :local_bottle_path

  # When performing a build, test, or other loggable action, indicates which
  # log file location to use.
  sig { returns(T.nilable(String)) }
  attr_reader :active_log_type

  # The {BuildOptions} or {Tab} for this {Formula}. Lists the arguments passed
  # and any {.option}s in the {Formula}. Note that these may differ at
  # different times during the installation of a {Formula}. This is annoying
  # but the result of state that we're trying to eliminate.
  sig { returns(T.any(BuildOptions, Tab)) }
  attr_reader :build

  # Whether this formula should be considered outdated
  # if the target of the alias it was installed with has since changed.
  # Defaults to true.
  sig { returns(T::Boolean) }
  attr_accessor :follow_installed_alias

  alias follow_installed_alias? follow_installed_alias

  # Whether or not to force the use of a bottle.
  sig { returns(T::Boolean) }
  attr_accessor :force_bottle

  sig {
    params(name: String, path: Pathname, spec: Symbol, alias_path: T.nilable(Pathname),
           tap: T.nilable(Tap), force_bottle: T::Boolean).void
  }
  def initialize(name, path, spec, alias_path: nil, tap: nil, force_bottle: false)
    # Only allow instances of subclasses. The base class does not hold any spec information (URLs etc).
    raise "Do not call `Formula.new' directly without a subclass." unless self.class < Formula

    # Stop any subsequent modification of a formula's definition.
    # Changes do not propagate to existing instances of formulae.
    # Now that we have an instance, it's too late to make any changes to the class-level definition.
    self.class.freeze

    @name = T.let(name, String)
    @unresolved_path = T.let(path, Pathname)
    @path = T.let(path.resolved_path, Pathname)
    @alias_path = T.let(alias_path, T.nilable(Pathname))
    @alias_name = T.let((File.basename(alias_path) if alias_path), T.nilable(String))
    @revision = T.let(self.class.revision || 0, Integer)
    @version_scheme = T.let(self.class.version_scheme || 0, Integer)
    @head = T.let(nil, T.nilable(SoftwareSpec))
    @stable = T.let(nil, T.nilable(SoftwareSpec))

    @force_bottle = T.let(force_bottle, T::Boolean)

    @tap = T.let(tap, T.nilable(Tap))
    @tap ||= if path == Formulary.core_path(name)
      CoreTap.instance
    else
      Tap.from_path(path)
    end

    @full_name = T.let(T.must(full_name_with_optional_tap(name)), String)
    @full_alias_name = T.let(full_name_with_optional_tap(@alias_name), T.nilable(String))

    self.class.spec_syms.each do |sym|
      spec_eval sym
    end

    @active_spec = T.let(determine_active_spec(spec), SoftwareSpec)
    @active_spec_sym = T.let(head? ? :head : :stable, Symbol)
    validate_attributes!
    @build = T.let(active_spec.build, T.any(BuildOptions, Tab))
    @pin = T.let(FormulaPin.new(self), FormulaPin)
    @follow_installed_alias = T.let(true, T::Boolean)
    @prefix_returns_versioned_prefix = T.let(false, T.nilable(T::Boolean))
    @oldname_locks = T.let([], T::Array[FormulaLock])
    @on_system_blocks_exist = T.let(false, T::Boolean)
  end

  sig { params(spec_sym: Symbol).void }
  def active_spec=(spec_sym)
    spec = send(spec_sym)
    raise FormulaSpecificationError, "#{spec_sym} spec is not available for #{full_name}" unless spec

    old_spec_sym = @active_spec_sym
    @active_spec = spec
    @active_spec_sym = spec_sym
    validate_attributes!
    @build = active_spec.build

    return if spec_sym == old_spec_sym

    Dependency.clear_cache
    Requirement.clear_cache
  end

  sig { params(build_options: T.any(BuildOptions, Tab)).void }
  def build=(build_options)
    old_options = @build
    @build = build_options

    return if old_options.used_options == build_options.used_options &&
              old_options.unused_options == build_options.unused_options

    Dependency.clear_cache
    Requirement.clear_cache
  end

  private

  # Allow full name logic to be re-used between names, aliases and installed aliases.
  sig { params(name: T.nilable(String)).returns(T.nilable(String)) }
  def full_name_with_optional_tap(name)
    if name.nil? || @tap.nil? || @tap.core_tap?
      name
    else
      "#{@tap}/#{name}"
    end
  end

  sig { params(name: T.any(String, Symbol)).void }
  def spec_eval(name)
    spec = self.class.send(name).dup
    return unless spec.url

    spec.owner = self
    add_global_deps_to_spec(spec)
    instance_variable_set(:"@#{name}", spec)
  end

  sig { params(spec: SoftwareSpec).void }
  def add_global_deps_to_spec(spec); end

  sig { params(requested: T.any(String, Symbol)).returns(SoftwareSpec) }
  def determine_active_spec(requested)
    spec = send(requested) || stable || head
    spec || raise(FormulaSpecificationError, "#{full_name}: formula requires at least a URL")
  end

  sig { void }
  def validate_attributes!
    if name.blank? || name.match?(/\s/) || !Utils.safe_filename?(name)
      raise FormulaValidationError.new(full_name, :name, name)
    end

    url = active_spec.url
    raise FormulaValidationError.new(full_name, :url, url) if url.blank? || url.match?(/\s/)

    val = version.respond_to?(:to_str) ? version.to_str : version
    return if val.present? && !val.match?(/\s/) && Utils.safe_filename?(val)

    raise FormulaValidationError.new(full_name, :version, val)
  end

  public

  # The alias path that was used to install this formula, if it exists.
  # Can differ from {#alias_path}, which is the alias used to find the formula,
  # and is specified to this instance.
  sig { returns(T.nilable(Pathname)) }
  def installed_alias_path
    build_tab = build
    path = build_tab.source["path"] if build_tab.is_a?(Tab)

    return unless path&.match?(%r{#{HOMEBREW_TAP_DIR_REGEX}/Aliases}o)

    path = Pathname(path)
    return unless path.symlink?

    path
  end

  sig { returns(T.nilable(String)) }
  def installed_alias_name = installed_alias_path&.basename&.to_s

  sig { returns(T.nilable(String)) }
  def full_installed_alias_name = full_name_with_optional_tap(installed_alias_name)

  # The path that was specified to find this formula.
  sig { returns(T.nilable(Pathname)) }
  def specified_path
    return Homebrew::API::Formula.cached_json_file_path if loaded_from_api?
    return alias_path if alias_path&.exist?

    return @unresolved_path if @unresolved_path.exist?

    return local_bottle_path if local_bottle_path.presence&.exist?

    alias_path || @unresolved_path
  end

  # The name specified to find this formula.
  sig { returns(String) }
  def specified_name
    alias_name || name
  end

  # The name (including tap) specified to find this formula.
  sig { returns(String) }
  def full_specified_name
    full_alias_name || full_name
  end

  # The name specified to install this formula.
  sig { returns(String) }
  def installed_specified_name
    installed_alias_name || name
  end

  # The name (including tap) specified to install this formula.
  sig { returns(String) }
  def full_installed_specified_name
    full_installed_alias_name || full_name
  end

  # Is the currently active {SoftwareSpec} a {#stable} build?
  sig { returns(T::Boolean) }
  def stable?
    active_spec == stable
  end

  # Is the currently active {SoftwareSpec} a {#head} build?
  sig { returns(T::Boolean) }
  def head?
    active_spec == head
  end

  # Is this formula HEAD-only?
  sig { returns(T::Boolean) }
  def head_only?
    !!head && !stable
  end

  # Stop RuboCop from erroneously indenting hash target
  delegate [ # rubocop:disable Layout/HashAlignment
    :bottle_defined?,
    :bottle_tag?,
    :bottled?,
    :bottle_specification,
    :downloader,
  ] => :active_spec

  # The Bottle object for the currently active {SoftwareSpec}.
  sig { returns(T.nilable(Bottle)) }
  def bottle
    @bottle ||= T.let(Bottle.new(self, bottle_specification), T.nilable(Bottle)) if bottled?
  end

  # The Bottle object for given tag.
  sig { params(tag: T.nilable(Utils::Bottles::Tag)).returns(T.nilable(Bottle)) }
  def bottle_for_tag(tag = nil)
    Bottle.new(self, bottle_specification, tag) if bottled?(tag)
  end

  # The description of the software.
  # @!method desc
  # @see .desc
  delegate desc: :"self.class"

  # The SPDX ID of the software license.
  # @!method license
  # @see .license
  delegate license: :"self.class"

  # The homepage for the software.
  # @!method homepage
  # @see .homepage
  delegate homepage: :"self.class"

  # The livecheck specification for the software.
  # @!method livecheck
  # @see .livecheck
  delegate livecheck: :"self.class"

  # Is a livecheck specification defined for the software?
  # @!method livecheck_defined?
  # @see .livecheck_defined?
  delegate livecheck_defined?: :"self.class"

  # Is a livecheck specification defined for the software?
  # @!method livecheckable?
  # @see .livecheckable?
  delegate livecheckable?: :"self.class"

  # Is a service specification defined for the software?
  # @!method service?
  # @see .service?
  delegate service?: :"self.class"

  # The version for the currently active {SoftwareSpec}.
  # The version is autodetected from the URL and/or tag so only needs to be
  # declared if it cannot be autodetected correctly.
  # @!method version
  # @see .version
  delegate version: :active_spec

  # Stop RuboCop from erroneously indenting hash target
  delegate [ # rubocop:disable Layout/HashAlignment
    :allow_network_access!,
    :deny_network_access!,
    :network_access_allowed?,
  ] => :"self.class"

  # Whether this formula was loaded using the formulae.brew.sh API
  # @!method loaded_from_api?
  # @see .loaded_from_api?
  delegate loaded_from_api?: :"self.class"

  sig { void }
  def update_head_version
    return unless head?

    head_spec = T.must(head)
    return unless head_spec.downloader.is_a?(VCSDownloadStrategy)
    return unless head_spec.downloader.cached_location.exist?

    path = if ENV["HOMEBREW_ENV"]
      ENV.fetch("PATH")
    else
      PATH.new(ORIGINAL_PATHS)
    end

    with_env(PATH: path) do
      head_spec.version.update_commit(head_spec.downloader.last_commit)
    end
  end

  # The {PkgVersion} for this formula with {version} and {#revision} information.
  sig { returns(PkgVersion) }
  def pkg_version = PkgVersion.new(version, revision)

  # If this is a `@`-versioned formula.
  sig { returns(T::Boolean) }
  def versioned_formula? = name.include?("@")

  # Returns any other `@`-versioned formulae names for any formula (including versioned formulae).
  sig { returns(T::Array[String]) }
  def versioned_formulae_names
    versioned_names = if tap
      name_prefix = name.gsub(/(@[\d.]+)?$/, "")
      T.must(tap).prefix_to_versioned_formulae_names.fetch(name_prefix, [])
    elsif path.exist?
      Pathname.glob(path.to_s.gsub(/(@[\d.]+)?\.rb$/, "@*.rb"))
              .map { |path| path.basename(".rb").to_s }
              .sort
    else
      raise "Either tap or path is required to list versioned formulae"
    end

    versioned_names.reject do |versioned_name|
      versioned_name == name
    end
  end

  # Returns any `@`-versioned Formula objects for any Formula (including versioned formulae).
  sig { returns(T::Array[Formula]) }
  def versioned_formulae
    versioned_formulae_names.filter_map do |name|
      Formula[name]
    rescue FormulaUnavailableError
      nil
    end.sort_by(&:version).reverse
  end

  # Whether this {Formula} is version-synced with other formulae.
  sig { returns(T::Boolean) }
  def synced_with_other_formulae?
    return false if @tap.nil?

    @tap.synced_versions_formulae.any? { |synced_formulae| synced_formulae.include?(name) }
  end

  # A named {Resource} for the currently active {SoftwareSpec}.
  # Additional downloads can be defined as {#resource}s.
  # {Resource#stage} will create a temporary directory and yield to a block.
  #
  # ### Example
  #
  # ```ruby
  # resource("additional_files").stage { bin.install "my/extra/tool" }
  # ```
  #
  # FIXME: This should not actually take a block. All resources should be defined
  #        at the top-level using {Formula.resource} instead
  #        (see https://github.com/Homebrew/brew/issues/17203#issuecomment-2093654431).
  #
  # @api public
  sig {
    params(name: String, klass: T.class_of(Resource), block: T.nilable(T.proc.bind(Resource).void))
      .returns(T.nilable(Resource))
  }
  def resource(name = T.unsafe(nil), klass = T.unsafe(nil), &block)
    if klass.nil?
      active_spec.resource(*name, &block)
    else
      active_spec.resource(name, klass, &block)
    end
  end

  # Old names for the formula.
  #
  # @api internal
  sig { returns(T::Array[String]) }
  def oldnames
    @oldnames ||= T.let(
      if (tap = self.tap)
        Tap.tap_migration_oldnames(tap, name) + tap.formula_reverse_renames.fetch(name, [])
      else
        []
      end, T.nilable(T::Array[String])
    )
  end

  # All aliases for the formula.
  #
  # @api internal
  sig { returns(T::Array[String]) }
  def aliases
    @aliases ||= T.let(
      if (tap = self.tap)
        tap.alias_reverse_table.fetch(full_name, []).map { _1.split("/").fetch(-1) }
      else
        []
      end, T.nilable(T::Array[String])
    )
  end

  # The {Resource}s for the currently active {SoftwareSpec}.
  # @!method resources
  def_delegator :"active_spec.resources", :values, :resources

  # The {Dependency}s for the currently active {SoftwareSpec}.
  #
  # @api internal
  delegate deps: :active_spec

  # The declared {Dependency}s for the currently active {SoftwareSpec} (i.e. including those provided by macOS)
  delegate declared_deps: :active_spec

  # The {Requirement}s for the currently active {SoftwareSpec}.
  delegate requirements: :active_spec

  # The cached download for the currently active {SoftwareSpec}.
  delegate cached_download: :active_spec

  # Deletes the download for the currently active {SoftwareSpec}.
  delegate clear_cache: :active_spec

  # The list of patches for the currently active {SoftwareSpec}.
  def_delegator :active_spec, :patches, :patchlist

  # The options for the currently active {SoftwareSpec}.
  delegate options: :active_spec

  # The deprecated options for the currently active {SoftwareSpec}.
  delegate deprecated_options: :active_spec

  # The deprecated option flags for the currently active {SoftwareSpec}.
  delegate deprecated_flags: :active_spec

  # If a named option is defined for the currently active {SoftwareSpec}.
  # @!method option_defined?
  delegate option_defined?: :active_spec

  # All the {.fails_with} for the currently active {SoftwareSpec}.
  delegate compiler_failures: :active_spec

  # If this {Formula} is installed.
  # This is actually just a check for if the {#latest_installed_prefix} directory
  # exists and is not empty.
  sig { returns(T::Boolean) }
  def latest_version_installed?
    (dir = latest_installed_prefix).directory? && !dir.children.empty?
  end

  # If at least one version of {Formula} is installed.
  #
  # @api public
  sig { returns(T::Boolean) }
  def any_version_installed?
    installed_prefixes.any? { |keg| (keg/AbstractTab::FILENAME).file? }
  end

  # The link status symlink directory for this {Formula}.
  # You probably want {#opt_prefix} instead.
  #
  # @api internal
  sig { returns(Pathname) }
  def linked_keg
    linked_keg = possible_names.map { |name| HOMEBREW_LINKED_KEGS/name }
                               .find(&:directory?)
    return linked_keg if linked_keg.present?

    HOMEBREW_LINKED_KEGS/name
  end

  sig { returns(T.nilable(PkgVersion)) }
  def latest_head_version
    head_versions = installed_prefixes.filter_map do |pn|
      pn_pkgversion = PkgVersion.parse(pn.basename.to_s)
      pn_pkgversion if pn_pkgversion.head?
    end

    head_versions.max_by do |pn_pkgversion|
      [Keg.new(prefix(pn_pkgversion)).tab.source_modified_time, pn_pkgversion.revision]
    end
  end

  sig { returns(T.nilable(Pathname)) }
  def latest_head_prefix
    head_version = latest_head_version
    prefix(head_version) if head_version
  end

  sig { params(version: PkgVersion, fetch_head: T::Boolean).returns(T::Boolean) }
  def head_version_outdated?(version, fetch_head: false)
    tab = Tab.for_keg(prefix(version))

    return true if tab.version_scheme < version_scheme
    return true if stable && tab.stable_version && tab.stable_version < T.must(stable).version
    return false unless fetch_head
    return false unless head&.downloader.is_a?(VCSDownloadStrategy)

    downloader = T.must(head).downloader

    with_context quiet: true do
      downloader.commit_outdated?(version.version.commit)
    end
  end

  # The latest prefix for this formula. Checks for {#head} and then {#stable}'s {#prefix}
  sig { returns(Pathname) }
  def latest_installed_prefix
    if head && (head_version = latest_head_version) && !head_version_outdated?(head_version)
      T.must(latest_head_prefix)
    elsif stable && (stable_prefix = prefix(PkgVersion.new(T.must(stable).version, revision))).directory?
      stable_prefix
    else
      prefix
    end
  end

  # The directory in the cellar that the formula is installed to.
  # This directory points to {#opt_prefix} if it exists and if {#prefix} is not
  # called from within the same formula's {#install} or {#post_install} methods.
  # Otherwise, return the full path to the formula's versioned cellar.
  sig { params(version: T.any(String, PkgVersion)).returns(Pathname) }
  def prefix(version = pkg_version)
    versioned_prefix = versioned_prefix(version)
    version = PkgVersion.parse(version) if version.is_a?(String)
    if !@prefix_returns_versioned_prefix && version == pkg_version &&
       versioned_prefix.directory? && Keg.new(versioned_prefix).optlinked?
      opt_prefix
    else
      versioned_prefix
    end
  end

  # Is the formula linked?
  #
  # @api internal
  sig { returns(T::Boolean) }
  def linked? = linked_keg.symlink?

  # Is the formula linked to `opt`?
  sig { returns(T::Boolean) }
  def optlinked? = opt_prefix.symlink?

  # If a formula's linked keg points to the prefix.
  sig { params(version: T.any(String, PkgVersion)).returns(T::Boolean) }
  def prefix_linked?(version = pkg_version)
    return false unless linked?

    linked_keg.resolved_path == versioned_prefix(version)
  end

  # {PkgVersion} of the linked keg for the formula.
  sig { returns(T.nilable(PkgVersion)) }
  def linked_version
    return unless linked?

    Keg.for(linked_keg).version
  end

  # The parent of the prefix; the named directory in the cellar containing all
  # installed versions of this software.
  sig { returns(Pathname) }
  def rack = HOMEBREW_CELLAR/name

  # All currently installed prefix directories.
  sig { returns(T::Array[Pathname]) }
  def installed_prefixes
    possible_names.map { |name| HOMEBREW_CELLAR/name }
                  .select(&:directory?)
                  .flat_map(&:subdirs)
                  .sort_by(&:basename)
  end

  # All currently installed kegs.
  sig { returns(T::Array[Keg]) }
  def installed_kegs
    installed_prefixes.map { |dir| Keg.new(dir) }
  end

  # The directory where the formula's binaries should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  #
  # ### Examples
  #
  # Need to install into the {.bin} but the makefile doesn't `mkdir -p prefix/bin`?
  #
  # ```ruby
  # bin.mkpath
  # ```
  #
  # No `make install` available?
  #
  # ```ruby
  # bin.install "binary1"
  # ```
  #
  # @api public
  sig { returns(Pathname) }
  def bin = prefix/"bin"

  # The directory where the formula's documentation should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  #
  # @api public
  sig { returns(Pathname) }
  def doc = share/"doc"/name

  # The directory where the formula's headers should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  #
  # ### Example
  #
  # No `make install` available?
  #
  # ```ruby
  # include.install "example.h"
  # ```
  #
  # @api public
  sig { returns(Pathname) }
  def include = prefix/"include"

  # The directory where the formula's info files should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  #
  # @api public
  sig { returns(Pathname) }
  def info = share/"info"

  # The directory where the formula's libraries should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  #
  # ### Example
  #
  # No `make install` available?
  #
  # ```ruby
  # lib.install "example.dylib"
  # ```
  #
  # @api public
  sig { returns(Pathname) }
  def lib = prefix/"lib"

  # The directory where the formula's binaries should be installed.
  # This is not symlinked into `HOMEBREW_PREFIX`.
  # It is commonly used to install files that we do not wish to be
  # symlinked into `HOMEBREW_PREFIX` from one of the other directories and
  # instead manually create symlinks or wrapper scripts into e.g. {#bin}.
  #
  # ### Example
  #
  # ```ruby
  # libexec.install "foo.jar"
  # bin.write_jar_script libexec/"foo.jar", "foo"
  # ```
  #
  # @api public
  sig { returns(Pathname) }
  def libexec = prefix/"libexec"

  # The root directory where the formula's manual pages should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  # Often one of the more specific `man` functions should be used instead,
  # e.g. {#man1}.
  #
  # @api public
  sig { returns(Pathname) }
  def man = share/"man"

  # The directory where the formula's man1 pages should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  #
  # ### Example
  #
  # No `make install` available?
  #
  # ```ruby
  # man1.install "example.1"
  # ```
  #
  # @api public
  sig { returns(Pathname) }
  def man1 = man/"man1"

  # The directory where the formula's man2 pages should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  #
  # @api public
  sig { returns(Pathname) }
  def man2 = man/"man2"

  # The directory where the formula's man3 pages should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  #
  # ### Example
  #
  # No `make install` available?
  #
  # ```ruby
  # man3.install "man.3"
  # ```
  #
  # @api public
  sig { returns(Pathname) }
  def man3 = man/"man3"

  # The directory where the formula's man4 pages should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  #
  # @api public
  sig { returns(Pathname) }
  def man4 = man/"man4"

  # The directory where the formula's man5 pages should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  #
  # @api public
  sig { returns(Pathname) }
  def man5 = man/"man5"

  # The directory where the formula's man6 pages should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  #
  # @api public
  sig { returns(Pathname) }
  def man6 = man/"man6"

  # The directory where the formula's man7 pages should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  #
  # @api public
  sig { returns(Pathname) }
  def man7 = man/"man7"

  # The directory where the formula's man8 pages should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  #
  # @api public
  sig { returns(Pathname) }
  def man8 = man/"man8"

  # The directory where the formula's `sbin` binaries should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  # Generally we try to migrate these to {#bin} instead.
  #
  # @api public
  sig { returns(Pathname) }
  def sbin = prefix/"sbin"

  # The directory where the formula's shared files should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  #
  # ### Examples
  #
  # Need a custom directory?
  #
  # ```ruby
  # (share/"concept").mkpath
  # ```
  #
  # Installing something into another custom directory?
  #
  # ```ruby
  # (share/"concept2").install "ducks.txt"
  # ```
  #
  # Install `./example_code/simple/ones` to `share/demos`:
  #
  # ```ruby
  # (share/"demos").install "example_code/simple/ones"
  # ```
  #
  # Install `./example_code/simple/ones` to `share/demos/examples`:
  #
  # ```ruby
  # (share/"demos").install "example_code/simple/ones" => "examples"
  # ```
  #
  # @api public
  sig { returns(Pathname) }
  def share = prefix/"share"

  # The directory where the formula's shared files should be installed,
  # with the name of the formula appended to avoid linking conflicts.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  #
  # ### Example
  #
  # No `make install` available?
  #
  # ```ruby
  # pkgshare.install "examples"
  # ```
  #
  # @api public
  sig { returns(Pathname) }
  def pkgshare = prefix/"share"/name

  # The directory where Emacs Lisp files should be installed, with the
  # formula name appended to avoid linking conflicts.
  #
  # ### Example
  #
  # To install an Emacs mode included with a software package:
  #
  # ```ruby
  # elisp.install "contrib/emacs/example-mode.el"
  # ```
  #
  # @api public
  sig { returns(Pathname) }
  def elisp = prefix/"share/emacs/site-lisp"/name

  # The directory where the formula's Frameworks should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  # This is not symlinked into `HOMEBREW_PREFIX`.
  #
  # @api public
  sig { returns(Pathname) }
  def frameworks = prefix/"Frameworks"

  # The directory where the formula's kernel extensions should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  # This is not symlinked into `HOMEBREW_PREFIX`.
  #
  # @api public
  sig { returns(Pathname) }
  def kext_prefix = prefix/"Library/Extensions"

  # The directory where the formula's configuration files should be installed.
  # Anything using `etc.install` will not overwrite other files on e.g. upgrades
  # but will write a new file named `*.default`.
  # This directory is not inside the `HOMEBREW_CELLAR` so it persists
  # across upgrades.
  #
  # @api public
  sig { returns(Pathname) }
  def etc = (HOMEBREW_PREFIX/"etc").extend(InstallRenamed)

  # A subdirectory of `etc` with the formula name suffixed.
  # e.g. `$HOMEBREW_PREFIX/etc/openssl@1.1`
  # Anything using `pkgetc.install` will not overwrite other files on
  # e.g. upgrades but will write a new file named `*.default`.
  #
  # @api public
  sig { returns(Pathname) }
  def pkgetc = (HOMEBREW_PREFIX/"etc"/name).extend(InstallRenamed)

  # The directory where the formula's variable files should be installed.
  # This directory is not inside the `HOMEBREW_CELLAR` so it persists
  # across upgrades.
  #
  # @api public
  sig { returns(Pathname) }
  def var = HOMEBREW_PREFIX/"var"

  # The directory where the formula's zsh function files should be
  # installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  #
  # @api public
  sig { returns(Pathname) }
  def zsh_function = share/"zsh/site-functions"

  # The directory where the formula's fish function files should be
  # installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  #
  # @api public
  sig { returns(Pathname) }
  def fish_function = share/"fish/vendor_functions.d"

  # The directory where the formula's Bash completion files should be
  # installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  #
  # @api public
  sig { returns(Pathname) }
  def bash_completion = prefix/"etc/bash_completion.d"

  # The directory where the formula's zsh completion files should be
  # installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  #
  # @api public
  sig { returns(Pathname) }
  def zsh_completion = share/"zsh/site-functions"

  # The directory where the formula's fish completion files should be
  # installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  #
  # @api public
  sig { returns(Pathname) }
  def fish_completion = share/"fish/vendor_completions.d"

  # The directory where formula's powershell completion files should be
  # installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  sig { returns(Pathname) }
  def pwsh_completion = share/"pwsh/completions"

  # The directory used for as the prefix for {#etc} and {#var} files on
  # installation so, despite not being in `HOMEBREW_CELLAR`, they are installed
  # there after pouring a bottle.
  sig { returns(Pathname) }
  def bottle_prefix = prefix/".bottle"

  # The directory where the formula's installation or test logs will be written.
  sig { returns(Pathname) }
  def logs = HOMEBREW_LOGS + name

  # The prefix, if any, to use in filenames for logging current activity.
  sig { returns(String) }
  def active_log_prefix
    if active_log_type
      "#{active_log_type}."
    else
      ""
    end
  end

  # Runs a block with the given log type in effect for its duration.
  sig { params(log_type: String, _block: T.proc.void).void }
  def with_logging(log_type, &_block)
    old_log_type = @active_log_type
    @active_log_type = T.let(log_type, T.nilable(String))
    yield
  ensure
    @active_log_type = old_log_type
  end

  # This method can be overridden to provide a plist.
  #
  # ### Example
  #
  # ```ruby
  # def plist; <<~EOS
  #   <?xml version="1.0" encoding="UTF-8"?>
  #   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  #   <plist version="1.0">
  #   <dict>
  #     <key>Label</key>
  #       <string>#{plist_name}</string>
  #     <key>ProgramArguments</key>
  #     <array>
  #       <string>#{opt_bin}/example</string>
  #       <string>--do-this</string>
  #     </array>
  #     <key>RunAtLoad</key>
  #     <true/>
  #     <key>KeepAlive</key>
  #     <true/>
  #     <key>StandardErrorPath</key>
  #     <string>/dev/null</string>
  #     <key>StandardOutPath</key>
  #     <string>/dev/null</string>
  #   </dict>
  #   </plist>
  #   EOS
  # end
  # ```
  #
  # @see https://www.unix.com/man-page/all/5/plist/ <code>plist(5)</code> man page
  sig { returns(NilClass) }
  def plist
    odisabled "`Formula#plist`", "`Homebrew::Service`"
    nil
  end

  # The generated launchd {.plist} service name.
  sig { returns(String) }
  def plist_name = service.plist_name

  # The generated service name.
  sig { returns(String) }
  def service_name = service.service_name

  # The generated launchd {.service} file path.
  sig { returns(Pathname) }
  def launchd_service_path = opt_prefix/"#{plist_name}.plist"

  # The generated systemd {.service} file path.
  sig { returns(Pathname) }
  def systemd_service_path = opt_prefix/"#{service_name}.service"

  # The generated systemd {.timer} file path.
  sig { returns(Pathname) }
  def systemd_timer_path = opt_prefix/"#{service_name}.timer"

  # The service specification of the software.
  sig { returns(Homebrew::Service) }
  def service
    @service ||= T.let(Homebrew::Service.new(self, &self.class.service), T.nilable(Homebrew::Service))
  end

  # A stable path for this formula, when installed. Contains the formula name
  # but no version number. Only the active version will be linked here if
  # multiple versions are installed.
  #
  # This is the preferred way to refer to a formula in plists or from another
  # formula, as the path is stable even when the software is updated.
  #
  # ### Example
  #
  # ```ruby
  # args << "--with-readline=#{Formula["readline"].opt_prefix}" if build.with? "readline"
  # ```
  #
  # @api public
  sig { returns(Pathname) }
  def opt_prefix = HOMEBREW_PREFIX/"opt"/name

  # Same as {#bin}, but relative to {#opt_prefix} instead of {#prefix}.
  #
  # @api public
  sig { returns(Pathname) }
  def opt_bin = opt_prefix/"bin"

  # Same as {#include}, but relative to {#opt_prefix} instead of {#prefix}.
  #
  # @api public
  sig { returns(Pathname) }
  def opt_include = opt_prefix/"include"

  # Same as {#lib}, but relative to {#opt_prefix} instead of {#prefix}.
  #
  # @api public
  sig { returns(Pathname) }
  def opt_lib = opt_prefix/"lib"

  # Same as {#libexec}, but relative to {#opt_prefix} instead of {#prefix}.
  #
  # @api public
  sig { returns(Pathname) }
  def opt_libexec = opt_prefix/"libexec"

  # Same as {#sbin}, but relative to {#opt_prefix} instead of {#prefix}.
  #
  # @api public
  sig { returns(Pathname) }
  def opt_sbin = opt_prefix/"sbin"

  # Same as {#share}, but relative to {#opt_prefix} instead of {#prefix}.
  #
  # @api public
  sig { returns(Pathname) }
  def opt_share = opt_prefix/"share"

  # Same as {#pkgshare}, but relative to {#opt_prefix} instead of {#prefix}.
  #
  # @api public
  sig { returns(Pathname) }
  def opt_pkgshare = opt_prefix/"share"/name

  # Same as {#elisp}, but relative to {#opt_prefix} instead of {#prefix}.
  #
  # @api public
  sig { returns(Pathname) }
  def opt_elisp = opt_prefix/"share/emacs/site-lisp"/name

  # Same as {#frameworks}, but relative to {#opt_prefix} instead of {#prefix}.
  #
  # @api public
  sig { returns(Pathname) }
  def opt_frameworks = opt_prefix/"Frameworks"

  # Indicates that this formula supports bottles. (Not necessarily that one
  # should be used in the current installation run.)
  # Can be overridden to selectively disable bottles from formulae.
  # Defaults to true so overridden version does not have to check if bottles
  # are supported.
  # Replaced by {.pour_bottle?}'s `satisfy` method if it is specified.
  sig { returns(T::Boolean) }
  def pour_bottle? = true

  delegate pour_bottle_check_unsatisfied_reason: :"self.class"

  # Can be overridden to run commands on both source and bottle installation.
  sig { overridable.void }
  def post_install; end

  sig { returns(T::Boolean) }
  def post_install_defined?
    method(:post_install).owner != Formula
  end

  sig { void }
  def install_etc_var
    etc_var_dirs = [bottle_prefix/"etc", bottle_prefix/"var"]
    Find.find(*etc_var_dirs.select(&:directory?)) do |path|
      path = Pathname.new(path)
      path.extend(InstallRenamed)
      path.cp_path_sub(bottle_prefix, HOMEBREW_PREFIX)
    end
  end

  sig { void }
  def run_post_install
    @prefix_returns_versioned_prefix = T.let(true, T.nilable(T::Boolean))
    build = self.build

    begin
      self.build = Tab.for_formula(self)

      new_env = {
        TMPDIR:        HOMEBREW_TEMP,
        TEMP:          HOMEBREW_TEMP,
        TMP:           HOMEBREW_TEMP,
        _JAVA_OPTIONS: "-Djava.io.tmpdir=#{HOMEBREW_TEMP}",
        HOMEBREW_PATH: nil,
        PATH:          PATH.new(ORIGINAL_PATHS),
      }

      with_env(new_env) do
        ENV.clear_sensitive_environment!
        ENV.activate_extensions!

        with_logging("post_install") do
          post_install
        end
      end
    ensure
      self.build = build
      @prefix_returns_versioned_prefix = T.let(false, T.nilable(T::Boolean))
    end
  end

  # Warn the user about any Homebrew-specific issues or quirks for this package.
  # These should not contain setup instructions that would apply to installation
  # through a different package manager on a different OS.
  #
  # ### Example
  #
  # ```ruby
  # def caveats
  #   <<~EOS
  #     Are optional. Something the user must be warned about?
  #   EOS
  # end
  # ```
  #
  # ```ruby
  # def caveats
  #   s = <<~EOS
  #     Print some important notice to the user when `brew info [formula]` is
  #     called or when brewing a formula.
  #     This is optional. You can use all the vars like #{version} here.
  #   EOS
  #   s += "Some issue only on older systems" if MacOS.version < :el_capitan
  #   s
  # end
  # ```
  sig { overridable.returns(T.nilable(String)) }
  def caveats = nil

  # Rarely, you don't want your library symlinked into the main prefix.
  # See `gettext.rb` for an example.
  # @see .keg_only
  #
  # @api internal
  sig { returns(T::Boolean) }
  def keg_only?
    return false unless keg_only_reason

    keg_only_reason.applicable?
  end

  delegate keg_only_reason: :"self.class"

  # @see .skip_clean
  sig { params(path: Pathname).returns(T::Boolean) }
  def skip_clean?(path)
    return true if path.extname == ".la" && T.must(self.class.skip_clean_paths).include?(:la)

    to_check = path.relative_path_from(prefix).to_s
    T.must(self.class.skip_clean_paths).include? to_check
  end

  # @see .link_overwrite
  sig { params(path: Pathname).returns(T::Boolean) }
  def link_overwrite?(path)
    # Don't overwrite files not created by Homebrew.
    return false if path.stat.uid != HOMEBREW_ORIGINAL_BREW_FILE.stat.uid

    # Don't overwrite files belong to other keg except when that
    # keg's formula is deleted.
    begin
      keg = Keg.for(path)
    rescue NotAKegError, Errno::ENOENT
      # file doesn't belong to any keg.
    else
      tab_tap = keg.tab.tap
      # this keg doesn't below to any core/tap formula, most likely coming from a DIY install.
      return false if tab_tap.nil?

      begin
        f = Formulary.factory(keg.name)
      rescue FormulaUnavailableError
        # formula for this keg is deleted, so defer to allowlist
      rescue TapFormulaAmbiguityError
        return false # this keg belongs to another formula
      else
        # this keg belongs to another unrelated formula
        return false unless f.possible_names.include?(keg.name)
      end
    end
    to_check = path.relative_path_from(HOMEBREW_PREFIX).to_s
    T.must(self.class.link_overwrite_paths).any? do |p|
      p.to_s == to_check ||
        to_check.start_with?("#{p.to_s.chomp("/")}/") ||
        /^#{Regexp.escape(p.to_s).gsub('\*', ".*?")}$/.match?(to_check)
    end
  end

  # Whether this {Formula} is deprecated (i.e. warns on installation).
  # Defaults to false.
  # @!method deprecated?
  # @return [Boolean]
  # @see .deprecate!
  delegate deprecated?: :"self.class"

  # The date that this {Formula} was or becomes deprecated.
  # Returns `nil` if no date is specified.
  # @!method deprecation_date
  # @return Date
  # @see .deprecate!
  delegate deprecation_date: :"self.class"

  # The reason this {Formula} is deprecated.
  # Returns `nil` if no reason is specified or the formula is not deprecated.
  # @!method deprecation_reason
  # @return [String, Symbol]
  # @see .deprecate!
  delegate deprecation_reason: :"self.class"

  # The replacement for this deprecated {Formula}.
  # Returns `nil` if no replacement is specified or the formula is not deprecated.
  # @!method deprecation_replacement
  # @return [String]
  # @see .deprecate!
  delegate deprecation_replacement: :"self.class"

  # Whether this {Formula} is disabled (i.e. cannot be installed).
  # Defaults to false.
  # @!method disabled?
  # @return [Boolean]
  # @see .disable!
  delegate disabled?: :"self.class"

  # The date that this {Formula} was or becomes disabled.
  # Returns `nil` if no date is specified.
  # @!method disable_date
  # @return Date
  # @see .disable!
  delegate disable_date: :"self.class"

  # The reason this {Formula} is disabled.
  # Returns `nil` if no reason is specified or the formula is not disabled.
  # @!method disable_reason
  # @return [String, Symbol]
  # @see .disable!
  delegate disable_reason: :"self.class"

  # The replacement for this disabled {Formula}.
  # Returns `nil` if no replacement is specified or the formula is not disabled.
  # @!method disable_replacement
  # @return [String]
  # @see .disable!
  delegate disable_replacement: :"self.class"

  sig { returns(T::Boolean) }
  def skip_cxxstdlib_check? = false

  sig { returns(T::Boolean) }
  def require_universal_deps? = false

  sig { void }
  def patch
    return if patchlist.empty?

    ohai "Patching"
    patchlist.each(&:apply)
  end

  sig { params(is_data: T::Boolean).void }
  def selective_patch(is_data: false)
    patches = patchlist.select { |p| p.is_a?(DATAPatch) == is_data }
    return if patches.empty?

    patchtype = if is_data
      "DATA"
    else
      "non-DATA"
    end
    ohai "Applying #{patchtype} patches"
    patches.each(&:apply)
  end

  # Yields |self,staging| with current working directory set to the uncompressed tarball
  # where staging is a {Mktemp} staging context.
  sig(:final) {
    params(fetch: T::Boolean, keep_tmp: T::Boolean, debug_symbols: T::Boolean, interactive: T::Boolean,
           _blk: T.proc.params(arg0: Formula, arg1: Mktemp).void).void
  }
  def brew(fetch: true, keep_tmp: false, debug_symbols: false, interactive: false, &_blk)
    @prefix_returns_versioned_prefix = T.let(true, T.nilable(T::Boolean))
    active_spec.fetch if fetch
    stage(interactive:, debug_symbols:) do |staging|
      staging.retain! if keep_tmp || debug_symbols

      prepare_patches
      fetch_patches if fetch

      begin
        yield self, staging
      rescue
        staging.retain! if interactive || debug?
        raise
      ensure
        %w[
          config.log
          CMakeCache.txt
          CMakeConfigureLog.yaml
          meson-log.txt
        ].each do |logfile|
          Dir["**/#{logfile}"].each do |logpath|
            destdir = logs/File.dirname(logpath)
            mkdir_p destdir
            cp logpath, destdir
          end
        end
      end
    end
  ensure
    @prefix_returns_versioned_prefix = T.let(false, T.nilable(T::Boolean))
  end

  sig { returns(T::Array[String]) }
  def lock
    @lock = T.let(FormulaLock.new(name), T.nilable(FormulaLock))
    T.must(@lock).lock

    oldnames.each do |oldname|
      next unless (oldname_rack = HOMEBREW_CELLAR/oldname).exist?
      next if oldname_rack.resolved_path != rack

      oldname_lock = FormulaLock.new(oldname)
      oldname_lock.lock
      @oldname_locks << oldname_lock
    end
  end

  sig { returns(T::Array[FormulaLock]) }
  def unlock
    @lock&.unlock
    @oldname_locks.each(&:unlock)
  end

  sig { returns(T::Array[String]) }
  def oldnames_to_migrate
    oldnames.select do |oldname|
      old_rack = HOMEBREW_CELLAR/oldname
      next false unless old_rack.directory?
      next false if old_rack.subdirs.empty?

      tap == Tab.for_keg(old_rack.subdirs.min).tap
    end
  end

  sig { returns(T::Boolean) }
  def migration_needed?
    !oldnames_to_migrate.empty? && !rack.exist?
  end

  sig { params(fetch_head: T::Boolean).returns(T::Array[Keg]) }
  def outdated_kegs(fetch_head: false)
    raise Migrator::MigrationNeededError.new(oldnames_to_migrate.first, name) if migration_needed?

    cache_key = "#{full_name}-#{fetch_head}"
    Formula.cache[:outdated_kegs] ||= {}
    Formula.cache[:outdated_kegs][cache_key] ||= begin
      all_kegs = []
      current_version = T.let(false, T::Boolean)

      installed_kegs.each do |keg|
        all_kegs << keg
        version = keg.version
        next if version.head?

        next if version_scheme > keg.version_scheme && pkg_version != version
        next if version_scheme == keg.version_scheme && pkg_version > version

        # don't consider this keg current if there's a newer formula available
        next if follow_installed_alias? && new_formula_available?

        # this keg is the current version of the formula, so it's not outdated
        current_version = true
        break
      end

      if current_version ||
         ((head_version = latest_head_version) && !head_version_outdated?(head_version, fetch_head:))
        []
      else
        all_kegs += old_installed_formulae.flat_map(&:installed_kegs)
        all_kegs.sort_by(&:scheme_and_version)
      end
    end
  end

  sig { returns(T::Boolean) }
  def new_formula_available?
    installed_alias_target_changed? && !latest_formula.latest_version_installed?
  end

  sig { returns(T.nilable(Formula)) }
  def current_installed_alias_target
    Formulary.factory(T.must(installed_alias_name)) if installed_alias_path
  end

  # Has the target of the alias used to install this formula changed?
  # Returns false if the formula wasn't installed with an alias.
  sig { returns(T::Boolean) }
  def installed_alias_target_changed?
    target = current_installed_alias_target
    return false unless target

    target.name != name
  end

  # Is this formula the target of an alias used to install an old formula?
  sig { returns(T::Boolean) }
  def supersedes_an_installed_formula? = old_installed_formulae.any?

  # Has the alias used to install the formula changed, or are different
  # formulae already installed with this alias?
  sig { returns(T::Boolean) }
  def alias_changed?
    installed_alias_target_changed? || supersedes_an_installed_formula?
  end

  # If the alias has changed value, return the new formula.
  # Otherwise, return self.
  sig { returns(Formula) }
  def latest_formula
    installed_alias_target_changed? ? T.must(current_installed_alias_target) : self
  end

  sig { returns(T::Array[Formula]) }
  def old_installed_formulae
    # If this formula isn't the current target of the alias,
    # it doesn't make sense to say that other formulae are older versions of it
    # because we don't know which came first.
    return [] if alias_path.nil? || installed_alias_target_changed?

    self.class.installed_with_alias_path(alias_path).reject { |f| f.name == name }
  end

  # Check whether the installed formula is outdated.
  #
  # @api internal
  sig { params(fetch_head: T::Boolean).returns(T::Boolean) }
  def outdated?(fetch_head: false)
    !outdated_kegs(fetch_head:).empty?
  rescue Migrator::MigrationNeededError
    true
  end

  def_delegators :@pin, :pinnable?, :pinned_version, :pin, :unpin

  # !attr[r] pinned?
  # @api internal
  delegate pinned?: :@pin

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
    self.class == other.class &&
      name == other.name &&
      active_spec_sym == other.active_spec_sym
  end
  alias eql? ==

  sig { returns(Integer) }
  def hash = name.hash

  sig { params(other: BasicObject).returns(T.nilable(Integer)) }
  def <=>(other)
    case other
    when Formula then name <=> other.name
    end
  end

  sig { returns(T::Array[String]) }
  def possible_names
    [name, *oldnames, *aliases].compact
  end

  # @api public
  sig { returns(String) }
  def to_s = name

  sig { returns(String) }
  def inspect
    "#<Formula #{name} (#{active_spec_sym}) #{path}>"
  end

  # Standard parameters for cabal-v2 builds.
  #
  # @api public
  sig { returns(T::Array[String]) }
  def std_cabal_v2_args
    # cabal-install's dependency-resolution backtracking strategy can
    # easily need more than the default 2,000 maximum number of
    # "backjumps," since Hackage is a fast-moving, rolling-release
    # target. The highest known needed value by a formula was 43,478
    # for git-annex, so 100,000 should be enough to avoid most
    # gratuitous backjumps build failures.
    ["--jobs=#{ENV.make_jobs}", "--max-backjumps=100000", "--install-method=copy", "--installdir=#{bin}"]
  end

  # Standard parameters for cargo builds.
  #
  # @api public
  sig {
    params(root: T.any(String, Pathname), path: T.any(String, Pathname)).returns(T::Array[String])
  }
  def std_cargo_args(root: prefix, path: ".")
    ["--jobs", ENV.make_jobs.to_s, "--locked", "--root=#{root}", "--path=#{path}"]
  end

  # Standard parameters for CMake builds.
  #
  # Setting `CMAKE_FIND_FRAMEWORK` to "LAST" tells CMake to search for our
  # libraries before trying to utilize Frameworks, many of which will be from
  # 3rd party installs.
  #
  # @api public
  sig {
    params(
      install_prefix: T.any(String, Pathname),
      install_libdir: T.any(String, Pathname),
      find_framework: String,
    ).returns(T::Array[String])
  }
  def std_cmake_args(install_prefix: prefix, install_libdir: "lib", find_framework: "LAST")
    %W[
      -DCMAKE_INSTALL_PREFIX=#{install_prefix}
      -DCMAKE_INSTALL_LIBDIR=#{install_libdir}
      -DCMAKE_BUILD_TYPE=Release
      -DCMAKE_FIND_FRAMEWORK=#{find_framework}
      -DCMAKE_VERBOSE_MAKEFILE=ON
      -DCMAKE_PROJECT_TOP_LEVEL_INCLUDES=#{HOMEBREW_LIBRARY_PATH}/cmake/trap_fetchcontent_provider.cmake
      -Wno-dev
      -DBUILD_TESTING=OFF
    ]
  end

  # Standard parameters for configure builds.
  #
  # @api public
  sig {
    params(
      prefix: T.any(String, Pathname),
      libdir: T.any(String, Pathname),
    ).returns(T::Array[String])
  }
  def std_configure_args(prefix: self.prefix, libdir: "lib")
    libdir = Pathname(libdir).expand_path(prefix)
    ["--disable-debug", "--disable-dependency-tracking", "--prefix=#{prefix}", "--libdir=#{libdir}"]
  end

  # Standard parameters for Go builds.
  #
  # @api public
  sig {
    params(
      output:  T.any(String, Pathname),
      ldflags: T.nilable(T.any(String, T::Array[String])),
      gcflags: T.nilable(T.any(String, T::Array[String])),
    ).returns(T::Array[String])
  }
  def std_go_args(output: bin/name, ldflags: nil, gcflags: nil)
    args = ["-trimpath", "-o=#{output}"]
    args += ["-ldflags=#{Array(ldflags).join(" ")}"] if ldflags
    args += ["-gcflags=#{Array(gcflags).join(" ")}"] if gcflags
    args
  end

  # Standard parameters for meson builds.
  #
  # @api public
  sig { returns(T::Array[String]) }
  def std_meson_args
    ["--prefix=#{prefix}", "--libdir=#{lib}", "--buildtype=release", "--wrap-mode=nofallback"]
  end

  # Standard parameters for npm builds.
  #
  # @api public
  sig { params(prefix: T.any(String, Pathname, FalseClass)).returns(T::Array[String]) }
  def std_npm_args(prefix: libexec)
    require "language/node"

    return Language::Node.std_npm_install_args(Pathname(prefix)) if prefix

    Language::Node.local_npm_install_args
  end

  # Standard parameters for pip builds.
  #
  # @api public
  sig {
    params(prefix:          T.any(FalseClass, String, Pathname),
           build_isolation: T::Boolean).returns(T::Array[String])
  }
  def std_pip_args(prefix: self.prefix, build_isolation: false)
    args = ["--verbose", "--no-deps", "--no-binary=:all:", "--ignore-installed", "--no-compile"]
    args << "--prefix=#{prefix}" if prefix
    args << "--no-build-isolation" unless build_isolation
    args
  end

  # Standard parameters for zig builds.
  #
  # `release_mode` can be set to either `:safe`, `:fast`, or `:small`
  # with `:fast` being the default value
  #
  # @api public
  sig {
    params(prefix:       T.any(String, Pathname),
           release_mode: Symbol).returns(T::Array[String])
  }
  def std_zig_args(prefix: self.prefix, release_mode: :fast)
    raise ArgumentError, "Invalid Zig release mode: #{release_mode}" if [:safe, :fast, :small].exclude?(release_mode)

    release_mode_downcased = release_mode.to_s.downcase
    release_mode_capitalized = release_mode.to_s.capitalize
    [
      "--prefix", prefix.to_s,
      "--release=#{release_mode_downcased}",
      "-Doptimize=Release#{release_mode_capitalized}",
      "--summary", "all"
    ]
  end

  # Shared library names according to platform conventions.
  #
  # Optionally specify a `version` to restrict the shared library to a specific
  # version. The special string "*" matches any version.
  #
  # If `name` is specified as "*", match any shared library of any version.
  #
  # ### Example
  #
  # ```ruby
  # shared_library("foo")      #=> foo.dylib
  # shared_library("foo", 1)   #=> foo.1.dylib
  # shared_library("foo", "*") #=> foo.2.dylib, foo.1.dylib, foo.dylib
  # shared_library("*")        #=> foo.dylib, bar.dylib
  # ```
  #
  # @api public
  sig { params(name: String, version: T.nilable(T.any(String, Integer))).returns(String) }
  def shared_library(name, version = nil)
    return "*.dylib" if name == "*" && (version.blank? || version == "*")

    infix = if version == "*"
      "{,.*}"
    elsif version.present?
      ".#{version}"
    end
    "#{name}#{infix}.dylib"
  end

  # Executable/Library RPATH according to platform conventions.
  #
  # Optionally specify a `source` or `target` depending on the location
  # of the file containing the RPATH command and where its target is located.
  #
  # ### Example
  #
  # ```ruby
  # rpath #=> "@loader_path/../lib"
  # rpath(target: frameworks) #=> "@loader_path/../Frameworks"
  # rpath(source: libexec/"bin") #=> "@loader_path/../../lib"
  # ```
  #
  # @api public
  sig { params(source: Pathname, target: Pathname).returns(String) }
  def rpath(source: bin, target: lib)
    unless target.to_s.start_with?(HOMEBREW_PREFIX)
      raise "rpath `target` should only be used for paths inside HOMEBREW_PREFIX!"
    end

    "#{loader_path}/#{target.relative_path_from(source)}"
  end

  # Linker variable for the directory containing the program or shared object.
  #
  # @api public
  sig { returns(String) }
  def loader_path = "@loader_path"

  # Creates a new `Time` object for use in the formula as the build time.
  #
  # @see https://www.rubydoc.info/stdlib/time/Time Time
  sig { returns(Time) }
  def time
    if ENV["SOURCE_DATE_EPOCH"].present?
      Time.at(ENV["SOURCE_DATE_EPOCH"].to_i).utc
    else
      Time.now.utc
    end
  end

  # Replaces a universal binary with its native slice.
  #
  # If called with no parameters, does this with all compatible
  # universal binaries in a {Formula}'s {Keg}.
  #
  # Raises an error if no universal binaries are found to deuniversalize.
  #
  # @api public
  sig { params(targets: T.nilable(T.any(Pathname, String))).void }
  def deuniversalize_machos(*targets)
    if targets.none?
      targets = any_installed_keg&.mach_o_files&.select do |file|
        file.arch == :universal && file.archs.include?(Hardware::CPU.arch)
      end
    end

    raise "No universal binaries found to deuniversalize" if targets.blank?

    targets&.each do |target|
      extract_macho_slice_from(Pathname(target), Hardware::CPU.arch)
    end
  end

  sig { params(file: Pathname, arch: T.nilable(Symbol)).void }
  def extract_macho_slice_from(file, arch = Hardware::CPU.arch)
    odebug "Extracting #{arch} slice from #{file}"
    file.ensure_writable do
      macho = MachO::FatFile.new(file)
      native_slice = macho.extract(Hardware::CPU.arch)
      native_slice.write file
      MachO.codesign! file if Hardware::CPU.arm?
    rescue MachO::MachOBinaryError
      onoe "#{file} is not a universal binary"
      raise
    rescue NoMethodError
      onoe "#{file} does not contain an #{arch} slice"
      raise
    end
  end
  private :extract_macho_slice_from

  # Generate shell completions for a formula for `bash`, `zsh`, `fish`, and
  # optionally `pwsh` using the formula's executable.
  #
  # ### Examples
  #
  # Using default values for optional arguments.
  #
  # ```ruby
  # generate_completions_from_executable(bin/"foo", "completions")
  #
  # # translates to
  # (bash_completion/"foo").write Utils.safe_popen_read({ "SHELL" => "bash" }, bin/"foo", "completions", "bash")
  # (zsh_completion/"_foo").write Utils.safe_popen_read({ "SHELL" => "zsh" }, bin/"foo", "completions", "zsh")
  # (fish_completion/"foo.fish").write Utils.safe_popen_read({ "SHELL" => "fish" }, bin/"foo",
  #                                                          "completions", "fish")
  # ```
  #
  # If your executable can generate completions for PowerShell,
  # you must pass ":pwsh" explicitly along with any other supported shells.
  # This will pass "powershell" as the completion argument.
  #
  # ```ruby
  # generate_completions_from_executable(bin/"foo", "completions", shells: [:bash, :pwsh])
  #
  # # translates to
  # (bash_completion/"foo").write Utils.safe_popen_read({ "SHELL" => "bash" }, bin/"foo", "completions", "bash")
  # (pwsh_completion/"foo").write Utils.safe_popen_read({ "SHELL" => "pwsh" }, bin/"foo",
  #                                                           "completions", "powershell")
  # ```
  #
  # Selecting shells and using a different `base_name`.
  #
  # ```ruby
  # generate_completions_from_executable(bin/"foo", "completions", shells: [:bash, :zsh], base_name: "bar")
  #
  # # translates to
  # (bash_completion/"bar").write Utils.safe_popen_read({ "SHELL" => "bash" }, bin/"foo", "completions", "bash")
  # (zsh_completion/"_bar").write Utils.safe_popen_read({ "SHELL" => "zsh" }, bin/"foo", "completions", "zsh")
  # ```
  #
  # Using predefined `shell_parameter_format :flag`.
  #
  # ```ruby
  # generate_completions_from_executable(bin/"foo", "completions", shell_parameter_format: :flag, shells: [:bash])
  #
  # # translates to
  # (bash_completion/"foo").write Utils.safe_popen_read({ "SHELL" => "bash" }, bin/"foo", "completions", "--bash")
  # ```
  #
  # Using predefined `shell_parameter_format :arg`.
  #
  # ```ruby
  # generate_completions_from_executable(bin/"foo", "completions", shell_parameter_format: :arg, shells: [:bash])
  #
  # # translates to
  # (bash_completion/"foo").write Utils.safe_popen_read({ "SHELL" => "bash" }, bin/"foo",
  #                                                     "completions", "--shell=bash")
  # ```
  #
  # Using predefined `shell_parameter_format :none`.
  #
  # ```ruby
  # generate_completions_from_executable(bin/"foo", "completions", shell_parameter_format: :none, shells: [:bash])
  #
  # # translates to
  # (bash_completion/"foo").write Utils.safe_popen_read({ "SHELL" => "bash" }, bin/"foo", "completions")
  # ```
  #
  # Using predefined `shell_parameter_format :click`.
  #
  # ```ruby
  # generate_completions_from_executable(bin/"foo", shell_parameter_format: :click, shells: [:zsh])
  #
  # # translates to
  # (zsh_completion/"_foo").write Utils.safe_popen_read({ "SHELL" => "zsh", "_FOO_COMPLETE" => "zsh_source" },
  #                                                     bin/"foo")
  # ```
  #
  # Using predefined `shell_parameter_format :clap`.
  #
  # ```ruby
  # generate_completions_from_executable(bin/"foo", shell_parameter_format: :clap, shells: [:zsh])
  #
  # # translates to
  # (zsh_completion/"_foo").write Utils.safe_popen_read({ "SHELL" => "zsh", "COMPLETE" => "zsh" }, bin/"foo")
  # ```
  #
  # Using custom `shell_parameter_format`.
  #
  # ```ruby
  # generate_completions_from_executable(bin/"foo", "completions", shell_parameter_format: "--selected-shell=",
  #                                      shells: [:bash])
  #
  # # translates to
  # (bash_completion/"foo").write Utils.safe_popen_read({ "SHELL" => "bash" }, bin/"foo",
  #                                                     "completions", "--selected-shell=bash")
  # ```
  #
  # @api public
  # @param commands
  #   the path to the executable and any passed subcommand(s) to use for generating the completion scripts.
  # @param base_name
  #   the base name of the generated completion script. Defaults to the name of the executable if installed
  #   within formula's bin or sbin. Otherwise falls back to the formula name.
  # @param shells
  #   the shells to generate completion scripts for. Defaults to `[:bash, :zsh, :fish]`.
  # @param shell_parameter_format
  #   specify how `shells` should each be passed to the `executable`. Takes either a String representing a
  #   prefix, or one of `[:flag, :arg, :none, :click, :clap]`. Defaults to plainly passing the shell.
  sig {
    params(
      commands:               T.any(Pathname, String),
      base_name:              T.nilable(String),
      shells:                 T::Array[Symbol],
      shell_parameter_format: T.nilable(T.any(Symbol, String)),
    ).void
  }
  def generate_completions_from_executable(*commands,
                                           base_name: nil,
                                           shells: [:bash, :zsh, :fish],
                                           shell_parameter_format: nil)
    executable = commands.first.to_s
    base_name ||= File.basename(executable) if executable.start_with?(bin.to_s, sbin.to_s)
    base_name ||= name

    completion_script_path_map = {
      bash: bash_completion/base_name,
      zsh:  zsh_completion/"_#{base_name}",
      fish: fish_completion/"#{base_name}.fish",
      pwsh: pwsh_completion/"#{base_name}.ps1",
    }

    shells.each do |shell|
      popen_read_env = { "SHELL" => shell.to_s }
      script_path = completion_script_path_map[shell]
      # Go's cobra and Rust's clap accept "powershell".
      shell_argument = (shell == :pwsh) ? "powershell" : shell.to_s
      shell_parameter = if shell_parameter_format.nil?
        shell_argument.to_s
      elsif shell_parameter_format == :flag
        "--#{shell_argument}"
      elsif shell_parameter_format == :arg
        "--shell=#{shell_argument}"
      elsif shell_parameter_format == :none
        nil
      elsif shell_parameter_format == :click
        prog_name = File.basename(executable).upcase.tr("-", "_")
        popen_read_env["_#{prog_name}_COMPLETE"] = "#{shell_argument}_source"
        nil
      elsif shell_parameter_format == :clap
        popen_read_env["COMPLETE"] = shell_argument.to_s
        nil
      else
        "#{shell_parameter_format}#{shell_argument}"
      end

      popen_read_args = %w[]
      popen_read_args << commands
      popen_read_args << shell_parameter if shell_parameter.present?
      popen_read_args.flatten!

      popen_read_options = {}
      popen_read_options[:err] = :err unless ENV["HOMEBREW_STDERR"]

      script_path.dirname.mkpath
      script_path.write Utils.safe_popen_read(popen_read_env, *popen_read_args, **popen_read_options)
    end
  end

  # an array of all core {Formula} names
  sig { returns(T::Array[String]) }
  def self.core_names
    CoreTap.instance.formula_names
  end

  # an array of all tap {Formula} names
  sig { returns(T::Array[String]) }
  def self.tap_names
    @tap_names ||= T.let(Tap.reject(&:core_tap?).flat_map(&:formula_names).sort, T.nilable(T::Array[String]))
  end

  # an array of all tap {Formula} files
  sig { returns(T::Array[Pathname]) }
  def self.tap_files
    @tap_files ||= T.let(Tap.reject(&:core_tap?).flat_map(&:formula_files), T.nilable(T::Array[Pathname]))
  end

  # an array of all {Formula} names
  sig { returns(T::Array[String]) }
  def self.names
    @names ||= T.let((core_names + tap_names.map do |name|
      name.split("/").fetch(-1)
    end).uniq.sort, T.nilable(T::Array[String]))
  end

  # an array of all {Formula} names, which the tap formulae have the fully-qualified name
  sig { returns(T::Array[String]) }
  def self.full_names
    @full_names ||= T.let(core_names + tap_names, T.nilable(T::Array[String]))
  end

  # an array of all {Formula}
  # this should only be used when users specify `--all` to a command
  sig { params(eval_all: T::Boolean).returns(T::Array[Formula]) }
  def self.all(eval_all: false)
    if !eval_all && !Homebrew::EnvConfig.eval_all?
      raise ArgumentError, "Formula#all without `--eval-all` or HOMEBREW_EVAL_ALL"
    end

    (core_names + tap_files).filter_map do |name_or_file|
      Formulary.factory(name_or_file)
    rescue FormulaUnavailableError, FormulaUnreadableError => e
      # Don't let one broken formula break commands. But do complain.
      onoe "Failed to import: #{name_or_file}"
      $stderr.puts e

      nil
    end
  end

  # An array of all racks currently installed.
  sig { returns(T::Array[Pathname]) }
  def self.racks
    Formula.cache[:racks] ||= if HOMEBREW_CELLAR.directory?
      HOMEBREW_CELLAR.subdirs.reject do |rack|
        rack.symlink? || rack.basename.to_s.start_with?(".") || rack.subdirs.empty?
      end
    else
      []
    end
  end

  # An array of all currently installed formula names.
  sig { returns(T::Array[String]) }
  def self.installed_formula_names
    racks.map { |rack| rack.basename.to_s }
  end

  # An array of all installed {Formula}
  sig { returns(T::Array[Formula]) }
  def self.installed
    Formula.cache[:installed] ||= racks.flat_map do |rack|
      Formulary.from_rack(rack)
    rescue
      []
    end.uniq(&:name)
  end

  sig { params(alias_path: T.nilable(Pathname)).returns(T::Array[Formula]) }
  def self.installed_with_alias_path(alias_path)
    return [] if alias_path.nil?

    installed.select { |f| f.installed_alias_path == alias_path }
  end

  # an array of all alias files of core {Formula}
  sig { returns(T::Array[Pathname]) }
  def self.core_alias_files
    CoreTap.instance.alias_files
  end

  # an array of all core aliases
  sig { returns(T::Array[String]) }
  def self.core_aliases
    CoreTap.instance.aliases
  end

  # an array of all tap aliases
  sig { returns(T::Array[String]) }
  def self.tap_aliases
    @tap_aliases ||= T.let(Tap.reject(&:core_tap?).flat_map(&:aliases).sort, T.nilable(T::Array[String]))
  end

  # an array of all aliases
  sig { returns(T::Array[String]) }
  def self.aliases
    @aliases ||= T.let((core_aliases + tap_aliases.map do |name|
      name.split("/").fetch(-1)
    end).uniq.sort, T.nilable(T::Array[String]))
  end

  # an array of all aliases as fully-qualified names
  sig { returns(T::Array[String]) }
  def self.alias_full_names
    @alias_full_names ||= T.let(core_aliases + tap_aliases, T.nilable(T::Array[String]))
  end

  # Returns a list of approximately matching formula names, but not the complete match
  sig { params(name: String).returns(T::Array[String]) }
  def self.fuzzy_search(name)
    @spell_checker ||= T.let(DidYouMean::SpellChecker.new(dictionary: Set.new(names + full_names).to_a),
                             T.nilable(DidYouMean::SpellChecker))
    T.cast(@spell_checker.correct(name), T::Array[String])
  end

  sig { params(name: T.any(Pathname, String)).returns(Formula) }
  def self.[](name)
    Formulary.factory(name)
  end

  # True if this formula is provided by Homebrew itself
  sig { returns(T::Boolean) }
  def core_formula?
    !!tap&.core_tap?
  end

  # True if this formula is provided by external Tap
  sig { returns(T::Boolean) }
  def tap?
    return false unless tap

    !T.must(tap).core_tap?
  end

  # True if this formula can be installed on this platform
  # Redefined in extend/os.
  sig { returns(T::Boolean) }
  def valid_platform?
    requirements.none?(MacOSRequirement) && requirements.none?(LinuxRequirement)
  end

  sig { params(options: T::Hash[Symbol, String]).void }
  def print_tap_action(options = {})
    return unless tap?

    verb = options[:verb] || "Installing"
    ohai "#{verb} #{name} from #{tap}"
  end

  sig { returns(T.nilable(String)) }
  def tap_git_head
    tap&.git_head
  rescue TapUnavailableError
    nil
  end

  delegate env: :"self.class"

  # !attr[r] conflicts
  # @api internal
  sig { returns(T::Array[FormulaConflict]) }
  def conflicts = T.must(self.class.conflicts)

  # Returns a list of Dependency objects in an installable order, which
  # means if a depends on b then b will be ordered before a in this list
  #
  # @api internal
  sig { params(block: T.nilable(T.proc.params(arg0: Formula, arg1: Dependency).void)).returns(T::Array[Dependency]) }
  def recursive_dependencies(&block)
    cache_key = "Formula#recursive_dependencies" unless block
    Dependency.expand(self, cache_key:, &block)
  end

  # The full set of Requirements for this formula's dependency tree.
  #
  # @api internal
  sig { params(block: T.nilable(T.proc.params(arg0: Formula, arg1: Requirement).void)).returns(Requirements) }
  def recursive_requirements(&block)
    cache_key = "Formula#recursive_requirements" unless block
    Requirement.expand(self, cache_key:, &block)
  end

  # Returns a Keg for the opt_prefix or installed_prefix if they exist.
  # If not, return `nil`.
  sig { returns(T.nilable(Keg)) }
  def any_installed_keg
    Formula.cache[:any_installed_keg] ||= {}
    Formula.cache[:any_installed_keg][full_name] ||= if (installed_prefix = any_installed_prefix)
      Keg.new(installed_prefix)
    end
  end

  # Get the path of any installed prefix.
  #
  # @api internal
  sig { returns(T.nilable(Pathname)) }
  def any_installed_prefix
    if optlinked? && opt_prefix.exist?
      opt_prefix
    elsif (latest_installed_prefix = installed_prefixes.last)
      latest_installed_prefix
    end
  end

  # Returns the {PkgVersion} for this formula if it is installed.
  # If not, return `nil`.
  sig { returns(T.nilable(PkgVersion)) }
  def any_installed_version
    any_installed_keg&.version
  end

  # Returns a list of Dependency objects that are required at runtime.
  #
  # @api internal
  sig { params(read_from_tab: T::Boolean, undeclared: T::Boolean).returns(T::Array[Dependency]) }
  def runtime_dependencies(read_from_tab: true, undeclared: true)
    deps = if read_from_tab && undeclared &&
              (tab_deps = any_installed_keg&.runtime_dependencies)
      tab_deps.filter_map do |d|
        full_name = d["full_name"]
        next unless full_name

        Dependency.new full_name
      end
    end
    begin
      deps ||= declared_runtime_dependencies unless undeclared
      deps ||= (declared_runtime_dependencies | undeclared_runtime_dependencies)
    rescue FormulaUnavailableError
      onoe "Could not get runtime dependencies from #{path}!"
      deps ||= []
    end
    deps
  end

  # Returns a list of {Formula} objects that are required at runtime.
  sig { params(read_from_tab: T::Boolean, undeclared: T::Boolean).returns(T::Array[Formula]) }
  def runtime_formula_dependencies(read_from_tab: true, undeclared: true)
    cache_key = "#{full_name}-#{read_from_tab}-#{undeclared}"

    Formula.cache[:runtime_formula_dependencies] ||= {}
    Formula.cache[:runtime_formula_dependencies][cache_key] ||= runtime_dependencies(
      read_from_tab:,
      undeclared:,
    ).filter_map do |d|
      d.to_formula
    rescue FormulaUnavailableError
      nil
    end
  end

  sig { returns(T::Array[Formula]) }
  def runtime_installed_formula_dependents
    # `any_installed_keg` and `runtime_dependencies` `select`s ensure
    # that we don't end up with something `Formula#runtime_dependencies` can't
    # read from a `Tab`.
    Formula.cache[:runtime_installed_formula_dependents] ||= {}
    Formula.cache[:runtime_installed_formula_dependents][full_name] ||= Formula.installed
                                                                               .select(&:any_installed_keg)
                                                                               .select(&:runtime_dependencies)
                                                                               .select do |f|
      f.runtime_formula_dependencies.any? do |dep|
        full_name == dep.full_name
      rescue
        name == dep.name
      end
    end
  end

  # Returns a list of formulae depended on by this formula that aren't
  # installed.
  sig { params(hide: T::Array[String]).returns(T::Array[Formula]) }
  def missing_dependencies(hide: [])
    runtime_formula_dependencies.select do |f|
      hide.include?(f.name) || f.installed_prefixes.empty?
    end
  # If we're still getting unavailable formulae at this stage the best we can
  # do is just return no results.
  rescue FormulaUnavailableError
    []
  end

  sig { returns(T.nilable(String)) }
  def ruby_source_path
    path.relative_path_from(T.must(tap).path).to_s if tap && path.exist?
  end

  sig { returns(T.nilable(Checksum)) }
  def ruby_source_checksum
    Checksum.new(Digest::SHA256.file(path).hexdigest) if path.exist?
  end

  sig { params(dependables: T::Hash[Symbol, T.untyped]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def merge_spec_dependables(dependables)
    # We have a hash of specs names (stable/head) to dependency lists.
    # Merge all of the dependency lists together, removing any duplicates.
    all_dependables = [].union(*dependables.values.map(&:to_a))

    all_dependables.map do |dependable|
      {
        dependable:,
        # Now find the list of specs each dependency was a part of.
        specs:      dependables.filter_map { |spec, spec_deps| spec if spec_deps&.include?(dependable) },
      }
    end
  end
  private :merge_spec_dependables

  sig { returns(T::Hash[String, T.untyped]) }
  def to_hash
    hsh = {
      "name"                     => name,
      "full_name"                => full_name,
      "tap"                      => tap&.name,
      "oldnames"                 => oldnames,
      "aliases"                  => aliases.sort,
      "versioned_formulae"       => versioned_formulae.map(&:name),
      "desc"                     => desc,
      "license"                  => SPDX.license_expression_to_string(license),
      "homepage"                 => homepage,
      "versions"                 => {
        "stable" => stable&.version&.to_s,
        "head"   => head&.version&.to_s,
        "bottle" => bottle_defined?,
      },
      "urls"                     => urls_hash,
      "revision"                 => revision,
      "version_scheme"           => version_scheme,
      "bottle"                   => {},
      "pour_bottle_only_if"      => self.class.pour_bottle_only_if&.to_s,
      "keg_only"                 => keg_only?,
      "keg_only_reason"          => keg_only_reason&.to_hash,
      "options"                  => [],
      "build_dependencies"       => [],
      "dependencies"             => [],
      "test_dependencies"        => [],
      "recommended_dependencies" => [],
      "optional_dependencies"    => [],
      "uses_from_macos"          => [],
      "uses_from_macos_bounds"   => [],
      "requirements"             => serialized_requirements,
      "conflicts_with"           => conflicts.map(&:name),
      "conflicts_with_reasons"   => conflicts.map(&:reason),
      "link_overwrite"           => self.class.link_overwrite_paths.to_a,
      "caveats"                  => caveats_with_placeholders,
      "installed"                => T.let([], T::Array[T::Hash[String, T.untyped]]),
      "linked_keg"               => linked_version&.to_s,
      "pinned"                   => pinned?,
      "outdated"                 => outdated?,
      "deprecated"               => deprecated?,
      "deprecation_date"         => deprecation_date,
      "deprecation_reason"       => deprecation_reason,
      "deprecation_replacement"  => deprecation_replacement,
      "disabled"                 => disabled?,
      "disable_date"             => disable_date,
      "disable_reason"           => disable_reason,
      "disable_replacement"      => disable_replacement,
      "post_install_defined"     => post_install_defined?,
      "service"                  => (service.to_hash if service?),
      "tap_git_head"             => tap_git_head,
      "ruby_source_path"         => ruby_source_path,
      "ruby_source_checksum"     => {},
    }

    hsh["bottle"]["stable"] = bottle_hash if stable && bottle_defined?

    hsh["options"] = options.map do |opt|
      { "option" => opt.flag, "description" => opt.description }
    end

    hsh.merge!(dependencies_hash)

    hsh["installed"] = installed_kegs.sort_by(&:scheme_and_version).map do |keg|
      tab = keg.tab
      {
        "version"                 => keg.version.to_s,
        "used_options"            => tab.used_options.as_flags,
        "built_as_bottle"         => tab.built_as_bottle,
        "poured_from_bottle"      => tab.poured_from_bottle,
        "time"                    => tab.time,
        "runtime_dependencies"    => tab.runtime_dependencies,
        "installed_as_dependency" => tab.installed_as_dependency,
        "installed_on_request"    => tab.installed_on_request,
      }
    end

    if (source_checksum = ruby_source_checksum)
      hsh["ruby_source_checksum"] = {
        "sha256" => source_checksum.hexdigest,
      }
    end

    hsh
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def to_hash_with_variations
    hash = to_hash

    # Take from API, merging in local install status.
    if loaded_from_api? && !Homebrew::EnvConfig.no_install_from_api?
      json_formula = Homebrew::API::Formula.all_formulae.fetch(name).dup
      return json_formula.merge(
        hash.slice("name", "installed", "linked_keg", "pinned", "outdated"),
      )
    end

    variations = {}

    if path.exist? && on_system_blocks_exist?
      formula_contents = path.read
      OnSystem::ALL_OS_ARCH_COMBINATIONS.each do |os, arch|
        bottle_tag = Utils::Bottles::Tag.new(system: os, arch:)
        next unless bottle_tag.valid_combination?

        Homebrew::SimulateSystem.with(os:, arch:) do
          variations_namespace = Formulary.class_s("Variations#{bottle_tag.to_sym.capitalize}")
          variations_formula_class = Formulary.load_formula(name, path, formula_contents, variations_namespace,
                                                            flags: self.class.build_flags, ignore_errors: true)
          variations_formula = variations_formula_class.new(name, path, :stable,
                                                            alias_path:, force_bottle:)

          variations_formula.to_hash.each do |key, value|
            next if value.to_s == hash[key].to_s

            variations[bottle_tag.to_sym] ||= {}
            variations[bottle_tag.to_sym][key] = value
          end
        end
      end
    end

    hash["variations"] = variations
    hash
  end

  # Returns the bottle information for a formula.
  sig { returns(T::Hash[String, T.untyped]) }
  def bottle_hash
    hash = {}
    stable_spec = stable
    return hash unless stable_spec
    return hash unless bottle_defined?

    bottle_spec = stable_spec.bottle_specification

    hash["rebuild"] = bottle_spec.rebuild
    hash["root_url"] = bottle_spec.root_url
    hash["files"] = {}

    bottle_spec.collector.each_tag do |tag|
      tag_spec = bottle_spec.collector.specification_for(tag, no_older_versions: true)
      os_cellar = tag_spec.cellar
      os_cellar = os_cellar.inspect if os_cellar.is_a?(Symbol)
      checksum = tag_spec.checksum.hexdigest

      file_hash = {}
      file_hash["cellar"] = os_cellar
      filename = Bottle::Filename.create(self, tag, bottle_spec.rebuild)
      path, = Utils::Bottles.path_resolved_basename(bottle_spec.root_url, name, checksum, filename)
      file_hash["url"] = "#{bottle_spec.root_url}/#{path}"
      file_hash["sha256"] = checksum

      hash["files"][tag.to_sym] = file_hash
    end
    hash
  end

  sig { returns(T::Hash[String, T::Hash[String, T.untyped]]) }
  def urls_hash
    hash = {}

    if stable
      stable_spec = T.must(stable)
      hash["stable"] = {
        "url"      => stable_spec.url,
        "tag"      => stable_spec.specs[:tag],
        "revision" => stable_spec.specs[:revision],
        "using"    => (stable_spec.using if stable_spec.using.is_a?(Symbol)),
        "checksum" => stable_spec.checksum&.to_s,
      }
    end

    if head
      hash["head"] = {
        "url"    => T.must(head).url,
        "branch" => T.must(head).specs[:branch],
        "using"  => (T.must(head).using if T.must(head).using.is_a?(Symbol)),
      }
    end

    hash
  end

  sig { returns(T::Array[T::Hash[String, T.untyped]]) }
  def serialized_requirements
    requirements = self.class.spec_syms.to_h do |sym|
      [sym, send(sym)&.requirements]
    end

    merge_spec_dependables(requirements).map do |data|
      req = data[:dependable]
      req_name = req.name.dup
      req_name.prepend("maximum_") if req.respond_to?(:comparator) && req.comparator == "<="
      req_version = if req.respond_to?(:version)
        req.version
      elsif req.respond_to?(:arch)
        req.arch
      end
      {
        "name"     => req_name,
        "cask"     => req.cask,
        "download" => req.download,
        "version"  => req_version,
        "contexts" => req.tags,
        "specs"    => data[:specs],
      }
    end
  end

  sig { returns(T.nilable(String)) }
  def caveats_with_placeholders
    caveats&.gsub(HOMEBREW_PREFIX, HOMEBREW_PREFIX_PLACEHOLDER)
           &.gsub(HOMEBREW_CELLAR, HOMEBREW_CELLAR_PLACEHOLDER)
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def dependencies_hash
    # Create a hash of spec names (stable/head) to the list of dependencies under each
    dependencies = self.class.spec_syms.to_h do |sym|
      [sym, send(sym)&.declared_deps]
    end

    # Implicit dependencies are only needed when installing from source
    # since they are only used to download and unpack source files.
    # @see DependencyCollector
    dependencies.transform_values! { |deps| deps&.reject(&:implicit?) }

    hash = {}

    dependencies.each do |spec_sym, spec_deps|
      next if spec_deps.nil?

      dep_hash = if spec_sym == :stable
        hash
      else
        next if spec_deps == dependencies[:stable]

        hash["#{spec_sym}_dependencies"] ||= {}
      end

      dep_hash["build_dependencies"] = spec_deps.select(&:build?)
                                                .reject(&:uses_from_macos?)
                                                .map(&:name)
                                                .uniq
      dep_hash["dependencies"] = spec_deps.reject(&:optional?)
                                          .reject(&:recommended?)
                                          .reject(&:build?)
                                          .reject(&:test?)
                                          .reject(&:uses_from_macos?)
                                          .map(&:name)
                                          .uniq
      dep_hash["test_dependencies"] = spec_deps.select(&:test?)
                                               .reject(&:uses_from_macos?)
                                               .map(&:name)
                                               .uniq
      dep_hash["recommended_dependencies"] = spec_deps.select(&:recommended?)
                                                      .reject(&:uses_from_macos?)
                                                      .map(&:name)
                                                      .uniq
      dep_hash["optional_dependencies"] = spec_deps.select(&:optional?)
                                                   .reject(&:uses_from_macos?)
                                                   .map(&:name)
                                                   .uniq

      uses_from_macos_deps = spec_deps.select(&:uses_from_macos?).uniq
      dep_hash["uses_from_macos"] = uses_from_macos_deps.map do |dep|
        if dep.tags.length >= 2
          { dep.name => dep.tags }
        elsif dep.tags.present?
          { dep.name => dep.tags.first }
        else
          dep.name
        end
      end
      dep_hash["uses_from_macos_bounds"] = uses_from_macos_deps.map(&:bounds)
    end

    hash
  end

  sig { params(spec_symbol: Symbol).returns(T.nilable(T::Hash[String, T.untyped])) }
  def internal_dependencies_hash(spec_symbol)
    raise ArgumentError, "Unsupported spec: #{spec_symbol}" unless [:stable, :head].include?(spec_symbol)
    return unless (spec = public_send(spec_symbol))

    spec.declared_deps.each_with_object({}) do |dep, dep_hash|
      # Implicit dependencies are only needed when installing from source
      # since they are only used to download and unpack source files.
      # @see DependencyCollector
      next if dep.implicit?

      metadata_hash = {}
      metadata_hash[:tags] = dep.tags if dep.tags.present?
      metadata_hash[:uses_from_macos] = dep.bounds.presence if dep.uses_from_macos?

      dep_hash[dep.name] = metadata_hash.presence
    end
  end

  sig { returns(T.nilable(T::Boolean)) }
  def on_system_blocks_exist?
    self.class.on_system_blocks_exist? || @on_system_blocks_exist
  end

  sig {
    params(
      verify_download_integrity: T::Boolean,
      timeout:                   T.nilable(T.any(Integer, Float)),
      quiet:                     T::Boolean,
    ).returns(Pathname)
  }
  def fetch(verify_download_integrity: true, timeout: nil, quiet: false)
    odeprecated "Formula#fetch", "Resource#fetch on Formula#resource"
    active_spec.fetch(verify_download_integrity:, timeout:, quiet:)
  end

  sig { params(filename: T.any(Pathname, String)).void }
  def verify_download_integrity(filename)
    odeprecated "Formula#verify_download_integrity", "Resource#verify_download_integrity on Formula#resource"
    active_spec.verify_download_integrity(filename)
  end

  sig { params(keep_tmp: T::Boolean).returns(T.untyped) }
  def run_test(keep_tmp: false)
    @prefix_returns_versioned_prefix = T.let(true, T.nilable(T::Boolean))

    test_env = {
      TMPDIR:        HOMEBREW_TEMP,
      TEMP:          HOMEBREW_TEMP,
      TMP:           HOMEBREW_TEMP,
      TERM:          "dumb",
      PATH:          PATH.new(ENV.fetch("PATH"), HOMEBREW_PREFIX/"bin"),
      HOMEBREW_PATH: nil,
    }.merge(common_stage_test_env)
    test_env[:_JAVA_OPTIONS] += " -Djava.io.tmpdir=#{HOMEBREW_TEMP}"

    ENV.clear_sensitive_environment!
    Utils::Git.set_name_email!

    mktemp("#{name}-test") do |staging|
      staging.retain! if keep_tmp
      @testpath = T.let(staging.tmpdir, T.nilable(Pathname))
      test_env[:HOME] = @testpath
      setup_home T.must(@testpath)
      begin
        with_logging("test") do
          with_env(test_env) do
            test
          end
        end
      # Handle all possible exceptions running formula tests.
      rescue Exception # rubocop:disable Lint/RescueException
        staging.retain! if debug?
        raise
      end
    end
  ensure
    @prefix_returns_versioned_prefix = T.let(false, T.nilable(T::Boolean))
    @testpath = T.let(nil, T.nilable(Pathname))
  end

  sig { returns(T::Boolean) }
  def test_defined?
    method(:test).owner != Formula
  end

  sig { returns(T.nilable(T::Boolean)) }
  def test; end

  sig { params(file: T.any(Pathname, String)).returns(Pathname) }
  def test_fixtures(file)
    HOMEBREW_LIBRARY_PATH/"test/support/fixtures"/file
  end

  # This method is overridden in {Formula} subclasses to provide the
  # installation instructions. The sources (from {.url}) are downloaded,
  # hash-checked and then Homebrew changes into a temporary directory where the
  # archive is unpacked or repository cloned.
  #
  # ### Example
  #
  # ```ruby
  # def install
  #   system "./configure", "--prefix=#{prefix}"
  #   system "make", "install"
  # end
  # ```
  sig { void }
  def install; end

  # Sometimes we have to change a bit before we install. Mostly we
  # prefer a patch, but if you need the {Formula#prefix prefix} of
  # this formula in the patch you have to resort to `inreplace`,
  # because in the patch you don't have access to any variables
  # defined by the formula, as only `HOMEBREW_PREFIX` is available
  # in the {DATAPatch embedded patch}.
  #
  # ### Examples
  #
  # `inreplace` supports regular expressions:
  #
  # ```ruby
  # inreplace "somefile.cfg", /look[for]what?/, "replace by #{bin}/tool"
  # ```
  #
  # `inreplace` supports blocks:
  #
  # ```ruby
  # inreplace "Makefile" do |s|
  #   s.gsub! "/usr/local", HOMEBREW_PREFIX.to_s
  # end
  # ```
  #
  # @see Utils::Inreplace.inreplace
  # @api public
  sig {
    params(
      paths:            T.any(T::Enumerable[T.any(String, Pathname)], String, Pathname),
      before:           T.nilable(T.any(Pathname, Regexp, String)),
      after:            T.nilable(T.any(Pathname, String, Symbol)),
      old_audit_result: T.nilable(T::Boolean),
      audit_result:     T::Boolean,
      global:           T::Boolean,
      block:            T.nilable(T.proc.params(s: StringInreplaceExtension).void),
    ).void
  }
  def inreplace(paths, before = nil, after = nil, old_audit_result = nil, audit_result: true, global: true, &block)
    # NOTE: must check for `#nil?` and not `#blank?`, or else `old_audit_result = false` will not call `odeprecated`.
    unless old_audit_result.nil?
      odeprecated "inreplace(paths, before, after, #{old_audit_result})",
                  "inreplace(paths, before, after, audit_result: #{old_audit_result})"
      audit_result = old_audit_result
    end
    Utils::Inreplace.inreplace(paths, before, after, audit_result:, global:, &block)
  rescue Utils::Inreplace::Error => e
    onoe e.to_s
    raise BuildError.new(self, "inreplace", Array(paths), {})
  end

  protected

  sig { params(home: Pathname).void }
  def setup_home(home)
    # Don't let bazel write to tmp directories we don't control or clean.
    (home/".bazelrc").write "startup --output_user_root=#{home}/_bazel"
  end

  # Returns a list of Dependency objects that are declared in the formula.
  sig { returns(T::Array[Dependency]) }
  def declared_runtime_dependencies
    cache_key = "Formula#declared_runtime_dependencies" unless build.any_args_or_options?
    Dependency.expand(self, cache_key:) do |_, dependency|
      Dependency.prune if dependency.build?
      next if dependency.required?

      if build.any_args_or_options?
        Dependency.prune if build.without?(dependency)
      elsif !dependency.recommended?
        Dependency.prune
      end
    end
  end

  # Returns a list of Dependency objects that are not declared in the formula
  # but the formula links to.
  sig { returns(T::Array[Dependency]) }
  def undeclared_runtime_dependencies
    keg = any_installed_keg
    return [] unless keg

    CacheStoreDatabase.use(:linkage) do |db|
      linkage_checker = LinkageChecker.new(keg, self, cache_db: db)
      linkage_checker.undeclared_deps.map { |n| Dependency.new(n) }
    end
  end

  public

  # To call out to the system, we use the `system` method and we prefer
  # you give the args separately as in the line below, otherwise a subshell
  # has to be opened first.
  #
  # ### Examples
  #
  # ```ruby
  # system "./bootstrap.sh", "--arg1", "--prefix=#{prefix}"
  # ```
  #
  # For CMake and other build systems we have some necessary defaults in e.g.
  # {#std_cmake_args}:
  #
  # ```ruby
  # system "cmake", ".", *std_cmake_args
  # ```
  #
  # If the arguments given to `configure` (or `make` or `cmake`) are depending
  # on options defined above, we usually make a list first and then
  # use the `args << if <condition>` to append each:
  #
  # ```ruby
  # args = ["--with-option1", "--with-option2"]
  # args << "--without-gcc" if ENV.compiler == :clang
  # ```
  #
  # Most software still uses `configure` and `make`.
  # Check with `./configure --help` for what our options are.
  #
  # ```ruby
  # system "./configure", "--disable-debug", "--disable-dependency-tracking",
  #                       "--disable-silent-rules", "--prefix=#{prefix}",
  #                       *args # our custom arg list (needs `*` to unpack)
  # ```
  #
  # If there is a "make install" available, please use it!
  #
  # ```ruby
  # system "make", "install"
  # ```
  #
  # @api public
  sig { params(cmd: T.any(String, Pathname), args: T.any(String, Integer, Pathname, Symbol)).void }
  def system(cmd, *args)
    verbose_using_dots = Homebrew::EnvConfig.verbose_using_dots?

    # remove "boring" arguments so that the important ones are more likely to
    # be shown considering that we trim long ohai lines to the terminal width
    pretty_args = args.dup
    unless verbose?
      case cmd
      when "./configure"
        pretty_args -= std_configure_args
      when "cabal"
        pretty_args -= std_cabal_v2_args
      when "cargo"
        pretty_args -= std_cargo_args
      when "cmake"
        pretty_args -= std_cmake_args
      when "go"
        pretty_args -= std_go_args
      when "meson"
        pretty_args -= std_meson_args
      when "zig"
        pretty_args -= std_zig_args
      when %r{(^|/)(pip|python)(?:[23](?:\.\d{1,2})?)?$}
        pretty_args -= std_pip_args
      end
    end
    pretty_args.each_index do |i|
      pretty_args[i] = "import setuptools..." if pretty_args[i].to_s.start_with? "import setuptools"
    end
    ohai "#{cmd} #{pretty_args * " "}".strip

    @exec_count ||= T.let(0, T.nilable(Integer))
    @exec_count += 1
    logfn = format("#{logs}/#{active_log_prefix}%02<exec_count>d.%<cmd_base>s",
                   exec_count: @exec_count,
                   cmd_base:   File.basename(cmd).split.first)
    logs.mkpath

    File.open(logfn, "w") do |log|
      log.puts Time.now, "", cmd, args, ""
      log.flush

      if verbose?
        rd, wr = IO.pipe
        begin
          pid = fork do
            rd.close
            log.close
            exec_cmd(cmd, args, wr, logfn)
          end
          wr.close

          if verbose_using_dots
            last_dot = Time.at(0)
            while (buf = rd.gets)
              log.puts buf
              # make sure dots printed with interval of at least 1 min.
              next if (Time.now - last_dot) <= 60

              print "."
              $stdout.flush
              last_dot = Time.now
            end
            puts
          else
            while (buf = rd.gets)
              log.puts buf
              puts buf
            end
          end
        ensure
          rd.close
        end
      else
        pid = fork do
          exec_cmd(cmd, args, log, logfn)
        end
      end

      Process.wait(pid)

      $stdout.flush

      unless $CHILD_STATUS.success?
        log_lines = Homebrew::EnvConfig.fail_log_lines

        log.flush
        if !verbose? || verbose_using_dots
          puts "Last #{log_lines} lines from #{logfn}:"
          Kernel.system "/usr/bin/tail", "-n", log_lines.to_s, logfn
        end
        log.puts

        require "system_config"
        require "build_environment"

        env = ENV.to_hash

        SystemConfig.dump_verbose_config(log)
        log.puts
        BuildEnvironment.dump env, log

        raise BuildError.new(self, cmd, args, env)
      end
    end
  end

  sig { params(quiet: T::Boolean).returns(T::Array[Keg]) }
  def eligible_kegs_for_cleanup(quiet: false)
    eligible_for_cleanup = []
    if latest_version_installed?
      eligible_kegs = if head? && (head_prefix = latest_head_prefix)
        head, stable = installed_kegs.partition { |keg| keg.version.head? }

        # Remove newest head and stable kegs.
        head - [Keg.new(head_prefix)] + T.must(stable.sort_by(&:scheme_and_version).slice(0...-1))
      else
        installed_kegs.select do |keg|
          tab = keg.tab
          if version_scheme > tab.version_scheme
            true
          elsif version_scheme == tab.version_scheme
            pkg_version > keg.version
          else
            false
          end
        end
      end

      unless eligible_kegs.empty?
        eligible_kegs.each do |keg|
          if keg.linked?
            opoo "Skipping (old) #{keg} due to it being linked" unless quiet
          elsif pinned? && keg == Keg.new(@pin.path.resolved_path)
            opoo "Skipping (old) #{keg} due to it being pinned" unless quiet
          elsif (keepme = keg/".keepme") && keepme.exist? && keepme.readable? &&
                (keepme_refs = keepme.readlines.map(&:strip).select { |ref| Pathname(ref).exist? }.presence)
            opoo "Skipping #{keg} as it needed by #{keepme_refs.join(", ")}" unless quiet
          else
            eligible_for_cleanup << keg
          end
        end
      end
    elsif !installed_prefixes.empty? && !pinned?
      # If the cellar only has one version installed, don't complain
      # that we can't tell which one to keep. Don't complain at all if the
      # only installed version is a pinned formula.
      opoo "Skipping #{full_name}: most recent version #{pkg_version} not installed" unless quiet
    end
    eligible_for_cleanup
  end

  # Create a temporary directory then yield. When the block returns,
  # recursively delete the temporary directory. Passing `opts[:retain]`
  # or calling `do |staging| ... staging.retain!` in the block will skip
  # the deletion and retain the temporary directory's contents.
  sig {
    params(
      prefix:          String,
      retain:          T::Boolean,
      retain_in_cache: T::Boolean,
      block:           T.proc.params(arg0: Mktemp).void,
    ).void
  }
  def mktemp(prefix = name, retain: false, retain_in_cache: false, &block)
    Mktemp.new(prefix, retain:, retain_in_cache:).run(&block)
  end

  # A version of `FileUtils.mkdir` that also changes to that folder in
  # a block.
  sig { params(name: T.any(String, Pathname), block: T.nilable(T.proc.void)).returns(T.untyped) }
  def mkdir(name, &block)
    result = FileUtils.mkdir_p(name)
    return result unless block

    FileUtils.chdir(name, &block)
  end

  # Runs `xcodebuild` without Homebrew's compiler environment variables set.
  sig { params(args: T.any(String, Integer, Pathname, Symbol)).void }
  def xcodebuild(*args)
    removed = ENV.remove_cc_etc

    begin
      self.system("xcodebuild", *args)
    ensure
      ENV.update(removed)
    end
  end

  sig { void }
  def fetch_patches
    patchlist.select(&:external?).each(&:fetch)
  end

  sig { void }
  def fetch_bottle_tab
    return unless bottled?

    T.must(bottle).fetch_tab
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def bottle_tab_attributes
    return {} unless bottled?

    T.must(bottle).tab_attributes
  end

  private

  sig { void }
  def prepare_patches
    patchlist.grep(DATAPatch) { |p| p.path = path }
  end

  # Returns the prefix for a given formula version number.
  sig { params(version: T.any(String, Pathname, PkgVersion)).returns(Pathname) }
  def versioned_prefix(version) = rack/version.to_s

  sig {
    params(
      cmd:   T.any(String, Pathname),
      args:  T::Array[T.any(String, Integer, Pathname, Symbol)],
      out:   IO,
      logfn: T.nilable(String),
    ).void
  }
  def exec_cmd(cmd, args, out, logfn)
    ENV["HOMEBREW_CC_LOG_PATH"] = logfn

    ENV.remove_cc_etc if cmd.to_s.start_with? "xcodebuild"

    # Turn on argument filtering in the superenv compiler wrapper.
    # We should probably have a better mechanism for this than adding
    # special cases to this method.
    if cmd == "python"
      setup_py_in_args = %w[setup.py build.py].include?(args.first)
      setuptools_shim_in_args = args.any? { |a| a.to_s.start_with? "import setuptools" }
      ENV.refurbish_args if setup_py_in_args || setuptools_shim_in_args
    end

    $stdout.reopen(out)
    $stderr.reopen(out)
    out.close
    args.map!(&:to_s)
    begin
      Kernel.exec(cmd, *args)
    rescue
      nil
    end
    puts "Failed to execute: #{cmd}"
    exit! 1 # never gets here unless exec threw or failed
  end

  # Common environment variables used at both build and test time.
  sig { returns(T::Hash[Symbol, String]) }
  def common_stage_test_env
    {
      _JAVA_OPTIONS:           "-Duser.home=#{HOMEBREW_CACHE}/java_cache",
      GOCACHE:                 "#{HOMEBREW_CACHE}/go_cache",
      GOPATH:                  "#{HOMEBREW_CACHE}/go_mod_cache",
      CARGO_HOME:              "#{HOMEBREW_CACHE}/cargo_cache",
      PIP_CACHE_DIR:           "#{HOMEBREW_CACHE}/pip_cache",
      CURL_HOME:               ENV.fetch("CURL_HOME") { Dir.home },
      PYTHONDONTWRITEBYTECODE: "1",
    }
  end

  sig { params(interactive: T::Boolean, debug_symbols: T::Boolean, _block: T.proc.params(arg0: Mktemp).void).void }
  def stage(interactive: false, debug_symbols: false, &_block)
    active_spec.stage(debug_symbols:) do |staging|
      @source_modified_time = T.let(active_spec.source_modified_time, T.nilable(Time))
      @buildpath = T.let(Pathname.pwd, T.nilable(Pathname))
      env_home = T.must(buildpath)/".brew_home"
      mkdir_p env_home

      stage_env = {
        HOMEBREW_PATH: nil,
      }

      unless interactive
        stage_env[:HOME] = env_home
        stage_env.merge!(common_stage_test_env)
      end

      setup_home env_home
      # Don't dirty the git tree for git clones.
      (env_home/".gitignore").write "*"

      ENV.clear_sensitive_environment!

      begin
        with_env(stage_env) do
          yield staging
        end
      ensure
        @buildpath = T.let(nil, T.nilable(Pathname))
      end
    end
  end

  # The methods below define the formula DSL.
  class << self
    include BuildEnvironment::DSL
    include OnSystem::MacOSAndLinux

    # Initialise instance variables for each subclass. These need to be initialised before the class is frozen,
    # and some DSL may never be called so it can't be done lazily.
    sig { params(child: T::Class[Formula]).void }
    def inherited(child)
      super
      child.instance_eval do
        # Ensure this is synced with `freeze`
        @stable = T.let(SoftwareSpec.new(flags: build_flags), T.nilable(SoftwareSpec))
        @head = T.let(HeadSoftwareSpec.new(flags: build_flags), T.nilable(HeadSoftwareSpec))
        @livecheck = T.let(Livecheck.new(self), T.nilable(Livecheck))
        @conflicts = T.let([], T.nilable(T::Array[FormulaConflict]))
        @skip_clean_paths = T.let(Set.new, T.nilable(T::Set[T.any(String, Symbol)]))
        @link_overwrite_paths = T.let(Set.new, T.nilable(T::Set[String]))
        @loaded_from_api = T.let(false, T.nilable(T::Boolean))
        @on_system_blocks_exist = T.let(false, T.nilable(T::Boolean))
        @network_access_allowed = T.let(SUPPORTED_NETWORK_ACCESS_PHASES.to_h do |phase|
          [phase, DEFAULT_NETWORK_ACCESS_ALLOWED]
        end, T.nilable(T::Hash[Symbol, T::Boolean]))
      end
    end

    sig { returns(T.self_type) }
    def freeze
      specs.each(&:freeze)
      @livecheck.freeze
      @conflicts.freeze
      @skip_clean_paths.freeze
      @link_overwrite_paths.freeze
      super
    end

    sig { returns(T::Hash[Symbol, T::Boolean]) }
    def network_access_allowed = T.must(@network_access_allowed)

    # Whether this formula was loaded using the formulae.brew.sh API
    sig { returns(T::Boolean) }
    def loaded_from_api? = !!@loaded_from_api

    # Whether this formula contains OS/arch-specific blocks
    # (e.g. `on_macos`, `on_arm`, `on_monterey :or_older`, `on_system :linux, macos: :big_sur_or_newer`).
    sig { returns(T::Boolean) }
    def on_system_blocks_exist? = !!@on_system_blocks_exist

    # The reason for why this software is not linked (by default) to {::HOMEBREW_PREFIX}.
    sig { returns(T.nilable(KegOnlyReason)) }
    attr_reader :keg_only_reason

    # A one-line description of the software. Used by users to get an overview
    # of the software and Homebrew maintainers.
    # Shows when running `brew info`.
    #
    # ### Example
    #
    # ```ruby
    # desc "Example formula"
    # ```
    #
    # @api public
    sig { params(val: String).returns(T.nilable(String)) }
    def desc(val = T.unsafe(nil))
      val.nil? ? @desc : @desc = T.let(val, T.nilable(String))
    end

    # The SPDX ID of the open-source license that the formula uses.
    # Shows when running `brew info`.
    #
    # Use `:any_of`, `:all_of` or `:with` to describe complex license expressions.
    # `:any_of` should be used when the user can choose which license to use.
    # `:all_of` should be used when the user must use all licenses.
    # `:with` should be used to specify a valid SPDX exception.
    #
    # Add `+` to an identifier to indicate that the formulae can be
    # licensed under later versions of the same license.
    #
    # ### Examples
    #
    # ```ruby
    # license "BSD-2-Clause"
    # ```
    #
    # ```ruby
    # license "EPL-1.0+"
    # ```
    #
    # ```ruby
    # license any_of: ["MIT", "GPL-2.0-only"]
    # ```
    #
    # ```ruby
    # license all_of: ["MIT", "GPL-2.0-only"]
    # ```
    #
    # ```ruby
    # license "GPL-2.0-only" => { with: "LLVM-exception" }
    # ```
    #
    # ```ruby
    # license :public_domain
    # ```
    #
    # ```ruby
    # license any_of: [
    #   "MIT",
    #   :public_domain,
    #   all_of: ["0BSD", "Zlib", "Artistic-1.0+"],
    #   "Apache-2.0" => { with: "LLVM-exception" },
    # ]
    # ```
    #
    # @see https://docs.brew.sh/License-Guidelines Homebrew License Guidelines
    # @see https://spdx.github.io/spdx-spec/latest/annexes/spdx-license-expressions/ SPDX license expression guide
    # @api public
    sig {
      params(args: T.any(NilClass, String, Symbol, T::Hash[T.any(String, Symbol), T.anything]))
        .returns(T.any(NilClass, String, Symbol, T::Hash[T.any(String, Symbol), T.anything]))
    }
    def license(args = nil)
      if args.nil?
        @licenses
      else
        @licenses = T.let(args, T.any(NilClass, String, Symbol, T::Hash[T.any(String, Symbol), T.anything]))
      end
    end

    # The phases for which network access is allowed. By default, network
    # access is allowed for all phases. Valid phases are `:build`, `:test`,
    # and `:postinstall`. When no argument is passed, network access will be
    # allowed for all phases.
    #
    # ### Examples
    #
    # ```ruby
    # allow_network_access!
    # ```
    #
    # ```ruby
    # allow_network_access! :build
    # ```
    #
    # ```ruby
    # allow_network_access! [:build, :test]
    # ```
    sig { params(phases: T.any(Symbol, T::Array[Symbol])).void }
    def allow_network_access!(phases = [])
      phases_array = Array(phases)
      if phases_array.empty?
        network_access_allowed.each_key { |phase| network_access_allowed[phase] = true }
      else
        phases_array.each do |phase|
          raise ArgumentError, "Unknown phase: #{phase}" unless SUPPORTED_NETWORK_ACCESS_PHASES.include?(phase)

          network_access_allowed[phase] = true
        end
      end
    end

    # The phases for which network access is denied. By default, network
    # access is allowed for all phases. Valid phases are `:build`, `:test`,
    # and `:postinstall`. When no argument is passed, network access will be
    # denied for all phases.
    #
    # ### Examples
    #
    # ```ruby
    # deny_network_access!
    # ```
    #
    # ```ruby
    # deny_network_access! :build
    # ```
    #
    # ```ruby
    # deny_network_access! [:build, :test]
    # ```
    sig { params(phases: T.any(Symbol, T::Array[Symbol])).void }
    def deny_network_access!(phases = [])
      phases_array = Array(phases)
      if phases_array.empty?
        network_access_allowed.each_key { |phase| network_access_allowed[phase] = false }
      else
        phases_array.each do |phase|
          raise ArgumentError, "Unknown phase: #{phase}" unless SUPPORTED_NETWORK_ACCESS_PHASES.include?(phase)

          network_access_allowed[phase] = false
        end
      end
    end

    # Whether the specified phase should be forced offline.
    sig { params(phase: Symbol).returns(T::Boolean) }
    def network_access_allowed?(phase)
      raise ArgumentError, "Unknown phase: #{phase}" unless SUPPORTED_NETWORK_ACCESS_PHASES.include?(phase)

      env_var = Homebrew::EnvConfig.send(:"formula_#{phase}_network")
      env_var.nil? ? network_access_allowed[phase] : env_var == "allow"
    end

    # The homepage for the software. Used by users to get more information
    # about the software and Homebrew maintainers as a point of contact for
    # e.g. submitting patches.
    # Can be opened with running `brew home`.
    #
    # ### Example
    #
    # ```ruby
    # homepage "https://www.example.com"
    # ```
    #
    # @api public
    sig { params(val: String).returns(T.nilable(String)) }
    def homepage(val = T.unsafe(nil))
      val.nil? ? @homepage : @homepage = T.let(val, T.nilable(String))
    end

    # Checks whether a `livecheck` specification is defined or not.
    #
    # It returns `true` when a `livecheck` block is present in the {Formula}
    # and `false` otherwise.
    sig { returns(T::Boolean) }
    def livecheck_defined?
      @livecheck_defined == true
    end

    # Checks whether a `livecheck` specification is defined or not. This is a
    # legacy alias for `#livecheck_defined?`.
    #
    # It returns `true` when a `livecheck` block is present in the {Formula}
    # and `false` otherwise.
    sig { returns(T::Boolean) }
    def livecheckable?
      # odeprecated "`livecheckable?`", "`livecheck_defined?`"
      @livecheck_defined == true
    end

    # Checks whether a service specification is defined or not.
    #
    # It returns `true` when a service block is present in the {Formula}
    # and `false` otherwise.
    sig { returns(T::Boolean) }
    def service?
      @service_block.present?
    end

    sig { returns(T.nilable(T::Array[FormulaConflict])) }
    attr_reader :conflicts

    sig { returns(T.nilable(T::Set[T.any(String, Symbol)])) }
    attr_reader :skip_clean_paths

    sig { returns(T.nilable(T::Set[String])) }
    attr_reader :link_overwrite_paths

    sig { returns(T.nilable(Symbol)) }
    attr_reader :pour_bottle_only_if

    # If `pour_bottle?` returns `false` the user-visible reason to display for
    # why they cannot use the bottle.
    sig { returns(T.nilable(String)) }
    attr_accessor :pour_bottle_check_unsatisfied_reason

    # Used for creating new Homebrew versions of software without new upstream
    # versions. For example, if we bump the major version of a library that this
    # {Formula} {.depends_on} then we may need to update the `revision` of this
    # {Formula} to install a new version linked against the new library version.
    # `0` if unset.
    #
    # ### Example
    #
    # ```ruby
    # revision 1
    # ```
    #
    # @api public
    sig { params(val: Integer).returns(T.nilable(Integer)) }
    def revision(val = T.unsafe(nil))
      val.nil? ? @revision : @revision = T.let(val, T.nilable(Integer))
    end

    # Used for creating new Homebrew version schemes. For example, if we want
    # to change version scheme from one to another, then we may need to update
    # `version_scheme` of this {Formula} to be able to use new version scheme,
    # e.g. to move from 20151020 scheme to 1.0.0 we need to increment
    # `version_scheme`. Without this, the prior scheme will always equate to a
    # higher version.
    # `0` if unset.
    #
    # ### Example
    #
    # ```ruby
    # version_scheme 1
    # ```
    #
    # @api public
    sig { params(val: Integer).returns(T.nilable(Integer)) }
    def version_scheme(val = T.unsafe(nil))
      val.nil? ? @version_scheme : @version_scheme = T.let(val, T.nilable(Integer))
    end

    sig { returns(T::Array[Symbol]) }
    def spec_syms = [:stable, :head].freeze

    # A list of the {.stable} and {.head} {SoftwareSpec}s.
    sig { returns(T::Array[SoftwareSpec]) }
    def specs
      spec_syms.map do |sym|
        send(sym)
      end.freeze
    end

    # The URL used to download the source for the {.stable} version of the formula.
    # We prefer `https` for security and proxy reasons.
    # If not inferable, specify the download strategy with `using: ...`.
    #
    # - `:git`, `:hg`, `:svn`, `:bzr`, `:fossil`, `:cvs`,
    # - `:curl` (normal file download, will also extract)
    # - `:nounzip` (without extracting)
    # - `:post` (download via an HTTP POST)
    #
    # ### Examples
    #
    # ```ruby
    # url "https://packed.sources.and.we.prefer.https.example.com/archive-1.2.3.tar.bz2"
    # ```
    #
    # ```ruby
    # url "https://some.dont.provide.archives.example.com",
    #     using:    :git,
    #     tag:      "1.2.3",
    #     revision: "db8e4de5b2d6653f66aea53094624468caad15d2"
    # ```
    #
    # @api public
    sig { params(val: String, specs: T::Hash[Symbol, T.any(String, Symbol)]).void }
    def url(val, specs = {}) = stable.url(val, specs)

    # The version string for the {.stable} version of the formula.
    # The version is autodetected from the URL and/or tag so only needs to be
    # declared if it cannot be autodetected correctly.
    #
    # ### Example
    #
    # ```ruby
    # version "1.2-final"
    # ```
    #
    # @api public
    sig { params(val: T.nilable(String)).returns(T.nilable(Version)) }
    def version(val = nil) = stable.version(val)

    # Additional URLs for the {.stable} version of the formula.
    # These are only used if the {.url} fails to download. It's optional and
    # there can be more than one. Generally we add them when the main {.url}
    # is unreliable. If {.url} is really unreliable then we may swap the
    # {.mirror} and {.url}.
    #
    # ### Example
    #
    # ```ruby
    # mirror "https://in.case.the.host.is.down.example.com"
    # mirror "https://in.case.the.mirror.is.down.example.com
    # ```
    #
    # @api public
    sig { params(val: String).void }
    def mirror(val) = stable.mirror(val)

    # @scope class
    # To verify the cached download's integrity and security we verify the
    # SHA-256 hash matches what we've declared in the {Formula}. To quickly fill
    # this value you can leave it blank and run `brew fetch --force` and it'll
    # tell you the currently valid value.
    #
    # ### Example
    #
    # ```ruby
    # sha256 "2a2ba417eebaadcb4418ee7b12fe2998f26d6e6f7fda7983412ff66a741ab6f7"
    # ```
    #
    # @api public
    sig { params(val: String).void }
    def sha256(val) = stable.sha256(val)

    # Adds a {.bottle} {SoftwareSpec}.
    # This provides a pre-built binary package built by the Homebrew maintainers for you.
    # It will be installed automatically if there is a binary package for your platform
    # and you haven't passed or previously used any options on this formula.
    #
    # If you maintain your own repository, you can add your own bottle links.
    # @see https://docs.brew.sh/Bottles Bottles
    # You can ignore this block entirely if submitting to Homebrew/homebrew-core.
    # It'll be handled for you by the Brew Test Bot.
    #
    # ```ruby
    # bottle do
    #   root_url "https://example.com" # Optional root to calculate bottle URLs.
    #   rebuild 1 # Marks the old bottle as outdated without bumping the version/revision of the formula.
    #   # Optionally specify the HOMEBREW_CELLAR in which the bottles were built.
    #   sha256 cellar: "/brew/Cellar", catalina:    "ef65c759c5097a36323fa9c77756468649e8d1980a3a4e05695c05e39568967c"
    #   sha256 cellar: :any,           mojave:      "28f4090610946a4eb207df102d841de23ced0d06ba31cb79e040d883906dcd4f"
    #   sha256                         high_sierra: "91dd0caca9bd3f38c439d5a7b6f68440c4274945615fae035ff0a369264b8a2f"
    # end
    # ```
    #
    # Homebrew maintainers aim to bottle all formulae.
    #
    # @api public
    sig { params(block: T.proc.bind(BottleSpecification).void).void }
    def bottle(&block) = stable.bottle(&block)

    sig { returns(BuildOptions) }
    def build = stable.build

    # Get the `BUILD_FLAGS` from the formula's namespace set in `Formulary::load_formula`.
    sig { returns(T::Array[String]) }
    def build_flags
      namespace = T.must(to_s.split("::")[0..-2]).join("::")
      return [] if namespace.empty?

      mod = const_get(namespace)
      mod.const_get(:BUILD_FLAGS)
    end

    # Allows adding {.depends_on} and {Patch}es just to the {.stable} {SoftwareSpec}.
    # This is required instead of using a conditional.
    # It is preferable to also pull the {url} and {sha256= sha256} into the block if one is added.
    #
    # ### Example
    #
    # ```ruby
    # stable do
    #   url "https://example.com/foo-1.0.tar.gz"
    #   sha256 "2a2ba417eebaadcb4418ee7b12fe2998f26d6e6f7fda7983412ff66a741ab6f7"
    #
    #   depends_on "libxml2"
    #   depends_on "libffi"
    # end
    # ```
    #
    # @api public
    sig { params(block: T.nilable(T.proc.returns(SoftwareSpec))).returns(T.untyped) }
    def stable(&block)
      return T.must(@stable) unless block

      T.must(@stable).instance_eval(&block)
    end

    # Adds a {.head} {SoftwareSpec}.
    # This can be installed by passing the `--HEAD` option to allow
    # installing software directly from a branch of a version-control repository.
    # If called as a method this provides just the {url} for the {SoftwareSpec}.
    # If a block is provided you can also add {.depends_on} and {Patch}es just to the {.head} {SoftwareSpec}.
    # The download strategies (e.g. `:using =>`) are the same as for {url}.
    # `master` is the default branch and doesn't need stating with a `branch:` parameter.
    #
    # ### Example
    #
    # ```ruby
    # head "https://we.prefer.https.over.git.example.com/.git"
    # ```
    #
    # ```ruby
    # head "https://example.com/.git", branch: "name_of_branch"
    # ```
    #
    # or (if autodetect fails):
    #
    # ```ruby
    # head "https://hg.is.awesome.but.git.has.won.example.com/", using: :hg
    # ```
    sig {
      params(val: T.nilable(String), specs: T::Hash[Symbol, T.untyped], block: T.nilable(T.proc.void))
        .returns(T.untyped)
    }
    def head(val = nil, specs = {}, &block)
      if block
        T.must(@head).instance_eval(&block)
      elsif val
        T.must(@head).url(val, specs)
      else
        @head
      end
    end

    # Additional downloads can be defined as {resource}s and accessed in the
    # install method. Resources can also be defined inside a {.stable} or
    # {.head} block. This mechanism replaces ad-hoc "subformula" classes.
    #
    # ### Example
    #
    # ```ruby
    # resource "additional_files" do
    #   url "https://example.com/additional-stuff.tar.gz"
    #   sha256 "c6bc3f48ce8e797854c4b865f6a8ff969867bbcaebd648ae6fd825683e59fef2"
    # end
    # ```
    #
    # @api public
    sig { params(name: String, klass: T.class_of(Resource), block: T.nilable(T.proc.bind(Resource).void)).void }
    def resource(name, klass = Resource, &block)
      specs.each do |spec|
        spec.resource(name, klass, &block) unless spec.resource_defined?(name)
      end
    end

    # Specify a Go resource.
    #
    # @api public
    sig { params(name: String, block: T.nilable(T.proc.void)).void }
    def go_resource(name, &block)
      odisabled "`Formula.go_resource`", "Go modules"
      specs.each { |spec| spec.go_resource(name, &block) }
    end

    # The dependencies for this formula. Use strings for the names of other
    # formulae. Homebrew provides some `:special` {Requirement}s for stuff
    # that needs extra handling (often changing some ENV vars or
    # deciding whether to use the system provided version).
    #
    # ### Examples
    #
    # `:build` means this dependency is only needed during build.
    #
    # ```ruby
    # depends_on "cmake" => :build
    # ```
    #
    # `:test` means this dependency is only needed during testing.
    #
    # ```ruby
    # depends_on "node" => :test
    # ```
    #
    # `:recommended` dependencies are built by default.
    # But a `--without-...` option is generated to opt-out.
    #
    # ```ruby
    # depends_on "readline" => :recommended
    # ```
    #
    # `:optional` dependencies are NOT built by default unless the
    # auto-generated `--with-...` option is passed.
    #
    # ```ruby
    # depends_on "glib" => :optional
    # ```
    #
    # If you need to specify that another formula has to be built with/out
    # certain options (note, no `--` needed before the option):
    #
    # ```ruby
    # depends_on "zeromq" => "with-pgm"
    # depends_on "qt" => ["with-qtdbus", "developer"] # Multiple options.
    # ```
    #
    # Optional and enforce that "boost" is built using `--with-c++11`.
    #
    # ```ruby
    # depends_on "boost" => [:optional, "with-c++11"]
    # ```
    #
    # If a dependency is only needed in certain cases:
    #
    # ```ruby
    # depends_on "sqlite" if MacOS.version >= :catalina
    # depends_on xcode: :build # If the formula really needs full Xcode to compile.
    # depends_on macos: :mojave # Needs at least macOS Mojave (10.14) to run.
    # ```
    #
    # It is possible to only depend on something if
    # `build.with?` or `build.without? "another_formula"`:
    #
    # ```ruby
    # depends_on "postgresql" if build.without? "sqlite"
    # ```
    #
    # @api public
    sig { params(dep: T.any(String, Symbol, T::Hash[String, T.untyped], T::Class[Requirement])).void }
    def depends_on(dep)
      specs.each { |spec| spec.depends_on(dep) }
    end

    # Indicates use of dependencies provided by macOS.
    # On macOS this is a no-op (as we use the provided system libraries) unless
    # `:since` specifies a minimum macOS version.
    # On Linux this will act as {.depends_on}.
    #
    # @api public
    sig {
      params(
        dep:    T.any(String, T::Hash[T.any(String, Symbol), T.any(Symbol, T::Array[Symbol])]),
        bounds: T::Hash[Symbol, Symbol],
      ).void
    }
    def uses_from_macos(dep, bounds = {})
      specs.each { |spec| spec.uses_from_macos(dep, bounds) }
    end

    # Options can be used as arguments to `brew install`.
    # To switch features on/off: `"with-something"` or `"with-otherthing"`.
    # To use other software: `"with-other-software"` or `"without-foo"`.
    # Note that for {.depends_on} that are `:optional` or `:recommended`, options
    # are generated automatically.
    #
    # There are also some special options:
    #
    # - `:universal`: build a universal binary/library (e.g. on newer Intel Macs
    #   this means a combined x86_64/x86 binary/library).
    #
    # ### Examples
    #
    # ```ruby
    # option "with-spam", "The description goes here without a dot at the end"
    # ```
    #
    # ```ruby
    # option "with-qt", "Text here overwrites what's autogenerated by 'depends_on "qt" => :optional'"
    # ```
    #
    # ```ruby
    # option :universal
    # ```
    #
    # @api public
    sig { params(name: String, description: String).void }
    def option(name, description = "")
      specs.each { |spec| spec.option(name, description) }
    end

    # Deprecated options are used to rename options and migrate users who used
    # them to newer ones. They are mostly used for migrating non-`with` options
    # (e.g. `enable-debug`) to `with` options (e.g. `with-debug`).
    #
    # ### Example
    #
    # ```ruby
    # deprecated_option "enable-debug" => "with-debug"
    # ```
    #
    # @api public
    sig { params(hash: T::Hash[String, String]).void }
    def deprecated_option(hash)
      specs.each { |spec| spec.deprecated_option(hash) }
    end

    # External patches can be declared using resource-style blocks.
    #
    # ### Examples
    #
    # ```ruby
    # patch do
    #   url "https://example.com/example_patch.diff"
    #   sha256 "c6bc3f48ce8e797854c4b865f6a8ff969867bbcaebd648ae6fd825683e59fef2"
    # end
    # ```
    #
    # A strip level of `-p1` is assumed. It can be overridden using a symbol
    # argument:
    #
    # ```ruby
    # patch :p0 do
    #   url "https://example.com/example_patch.diff"
    #   sha256 "c6bc3f48ce8e797854c4b865f6a8ff969867bbcaebd648ae6fd825683e59fef2"
    # end
    # ```
    #
    # Patches can be declared in stable and head blocks. This form is
    # preferred over using conditionals.
    #
    # ```ruby
    # stable do
    #   patch do
    #     url "https://example.com/example_patch.diff"
    #     sha256 "c6bc3f48ce8e797854c4b865f6a8ff969867bbcaebd648ae6fd825683e59fef2"
    #   end
    # end
    # ```
    #
    # Embedded (`__END__`) patches are declared like so:
    #
    # ```ruby
    # patch :DATA
    # patch :p0, :DATA
    # ```
    #
    # Patches can also be embedded by passing a string. This makes it possible
    # to provide multiple embedded patches while making only some of them
    # conditional.
    #
    # ```ruby
    # patch :p0, "..."
    # ```
    #
    # @see https://docs.brew.sh/Formula-Cookbook#patches Patches
    # @api public
    sig {
      params(strip: T.any(String, Symbol), src: T.any(NilClass, String, Symbol), block: T.nilable(T.proc.void)).void
    }
    def patch(strip = :p1, src = nil, &block)
      specs.each { |spec| spec.patch(strip, src, &block) }
    end

    # One or more formulae that conflict with this one and why.
    #
    # ### Example
    #
    # ```ruby
    # conflicts_with "imagemagick", because: "both install `convert` binaries"
    # ```
    #
    # @api public
    sig { params(names: T.untyped).void }
    def conflicts_with(*names)
      opts = T.let(names.last.is_a?(Hash) ? names.pop : {}, T::Hash[Symbol, T.untyped])
      names.each { |name| T.must(conflicts) << FormulaConflict.new(name, opts[:because]) }
    end

    # Skip cleaning paths in a formula.
    #
    # Sometimes the formula {Cleaner cleaner} breaks things.
    #
    # ### Examples
    #
    # Preserve cleaned paths with:
    #
    # ```ruby
    # skip_clean "bin/foo", "lib/bar"
    # ```
    #
    # Keep .la files with:
    #
    # ```ruby
    # skip_clean :la
    # ```
    #
    # @api public
    sig { params(paths: T.any(String, Symbol)).returns(T::Set[T.any(String, Symbol)]) }
    def skip_clean(*paths)
      paths.flatten!
      # Specifying :all is deprecated and will become an error
      T.must(skip_clean_paths).merge(paths)
    end

    # Software that will not be symlinked into the `brew --prefix` and will
    # only live in its Cellar. Other formulae can depend on it and Homebrew
    # will add the necessary includes, libraries and other paths while
    # building that other formula.
    #
    # Keg-only formulae are not in your PATH and are not seen by compilers
    # if you build your own software outside of Homebrew. This way, we
    # don't shadow software provided by macOS.
    #
    # ### Examples
    #
    # ```ruby
    # keg_only :provided_by_macos
    # ```
    #
    # ```ruby
    # keg_only :versioned_formulae
    # ```
    #
    # ```ruby
    # keg_only "because I want it so"
    # ```
    #
    # @api public
    sig { params(reason: T.any(String, Symbol), explanation: String).void }
    def keg_only(reason, explanation = "")
      @keg_only_reason = T.let(KegOnlyReason.new(reason, explanation), T.nilable(KegOnlyReason))
    end

    # Pass `:skip` to this method to disable post-install stdlib checking.
    #
    # @api public
    sig { params(check_type: Symbol).void }
    def cxxstdlib_check(check_type)
      define_method(:skip_cxxstdlib_check?) { true } if check_type == :skip
    end

    # Marks the {Formula} as failing with a particular compiler so it will fall back to others.
    #
    # ### Examples
    #
    # For Apple compilers, this should be in the format:
    #
    # ```ruby
    # fails_with :clang do
    #   build 600
    #   cause "multiple configure and compile errors"
    # end
    # ```
    #
    # The block may be omitted and if present, the build may be omitted;
    # if so, then the compiler will not be allowed for *all* versions.
    #
    # `major_version` should be the major release number only, for instance
    # '7' for the GCC 7 series (7.0, 7.1, etc.).
    # If `version` or the block is omitted, then the compiler will
    # not be allowed for all compilers in that series.
    #
    # For example, if a bug is only triggered on GCC 7.1 but is not
    # encountered on 7.2:
    #
    # ```ruby
    # fails_with :gcc => '7' do
    #   version '7.1'
    # end
    # ```
    #
    # @api public
    sig { params(compiler: T.any(Symbol, T::Hash[Symbol, String]), block: T.nilable(T.proc.void)).void }
    def fails_with(compiler, &block)
      specs.each { |spec| spec.fails_with(compiler, &block) }
    end

    # Marks the {Formula} as needing a certain standard, so Homebrew
    # will fall back to other compilers if the default compiler
    # does not implement that standard.
    #
    # We generally prefer to {.depends_on} a desired compiler and to
    # explicitly use that compiler in a formula's {#install} block,
    # rather than implicitly finding a suitable compiler with `needs`.
    #
    # @see .fails_with
    #
    # @api public
    sig { params(standards: String).void }
    def needs(*standards)
      specs.each { |spec| spec.needs(*standards) }
    end

    # A test is required for new formulae and makes us happy.
    #
    # The block will create, run in and delete a temporary directory.
    #
    # We want tests that don't require any user input
    # and test the basic functionality of the application.
    # For example, `foo build-foo input.foo` is a good test
    # and `foo --version` or `foo --help` are bad tests.
    # However, a bad test is better than no test at all.
    #
    # ### Examples
    #
    # ```ruby
    # (testpath/"test.file").write <<~EOS
    #   writing some test file, if you need to
    # EOS
    # assert_equal "OK", shell_output("test_command test.file").strip
    # ```
    #
    # Need complete control over stdin, stdout?
    #
    # ```ruby
    # require "open3"
    # Open3.popen3("#{bin}/example", "argument") do |stdin, stdout, _|
    #   stdin.write("some text")
    #   stdin.close
    #   assert_equal "result", stdout.read
    # end
    # ```
    #
    # The test will fail if it returns false, or if an exception is raised.
    # Failed assertions and failed `system` commands will raise exceptions.
    #
    # @see https://docs.brew.sh/Formula-Cookbook#add-a-test-to-the-formula Tests
    # @return [Boolean]
    # @api public
    sig { params(block: T.proc.returns(T.untyped)).returns(T.untyped) }
    def test(&block) = define_method(:test, &block)

    # {Livecheck} can be used to check for newer versions of the software.
    # This method evaluates the DSL specified in the `livecheck` block of the
    # {Formula} (if it exists) and sets the instance variables of a {Livecheck}
    # object accordingly. This is used by `brew livecheck` to check for newer
    # versions of the software.
    #
    # ### Example
    #
    # ```ruby
    # livecheck do
    #   skip "Not maintained"
    #   url "https://example.com/foo/releases"
    #   regex /foo-(\d+(?:\.\d+)+)\.tar/
    # end
    # ```
    #
    # @api public
    sig { params(block: T.nilable(T.proc.bind(Livecheck).returns(T.untyped))).returns(T.untyped) }
    def livecheck(&block)
      return @livecheck unless block

      @livecheck_defined = T.let(true, T.nilable(T::Boolean))
      @livecheck.instance_eval(&block)
    end

    # Service can be used to define services.
    # This method evaluates the DSL specified in the service block of the
    # {Formula} (if it exists) and sets the instance variables of a Service
    # object accordingly. This is used by `brew install` to generate a service file.
    #
    # ### Example
    #
    # ```ruby
    # service do
    #   run [opt_bin/"foo"]
    # end
    # ```
    #
    # @api public
    sig { params(block: T.nilable(T.proc.returns(T.untyped))).returns(T.nilable(T.proc.returns(T.untyped))) }
    def service(&block)
      return @service_block unless block

      @service_block = T.let(block, T.nilable(T.proc.returns(T.untyped)))
    end

    # Defines whether the {Formula}'s bottle can be used on the given Homebrew
    # installation.
    #
    # ### Examples
    #
    # If the bottle requires the Xcode CLT to be installed a
    # {Formula} would declare:
    #
    # ```ruby
    # pour_bottle? do
    #   reason "The bottle needs the Xcode CLT to be installed."
    #   satisfy { MacOS::CLT.installed? }
    # end
    # ```
    #
    # If `satisfy` returns `false` then a bottle will not be used and instead
    # the {Formula} will be built from source and `reason` will be printed.
    #
    # Alternatively, a preset reason can be passed as a symbol:
    #
    # ```ruby
    # pour_bottle? only_if: :clt_installed
    # ```
    #
    # @api public
    sig {
      params(
        only_if: T.nilable(Symbol),
        block:   T.nilable(T.proc.params(arg0: T.untyped).returns(T.any(T::Boolean, Symbol))),
      ).void
    }
    def pour_bottle?(only_if: nil, &block)
      @pour_bottle_check = T.let(PourBottleCheck.new(self), T.nilable(PourBottleCheck))
      @pour_bottle_only_if = T.let(only_if, T.nilable(Symbol))

      if only_if.present? && block.present?
        raise ArgumentError, "Do not pass both a preset condition and a block to `pour_bottle?`"
      end

      block ||= case only_if
      when :clt_installed
        lambda do |_|
          on_macos do
            T.bind(self, PourBottleCheck)
            reason(+<<~EOS)
              The bottle needs the Xcode Command Line Tools to be installed at /Library/Developer/CommandLineTools.
              Development tools provided by Xcode.app are not sufficient.

              You can install the Xcode Command Line Tools, if desired, with:
                  xcode-select --install
            EOS
            satisfy { MacOS::CLT.installed? }
          end
        end
      when :default_prefix
        lambda do |_|
          T.bind(self, PourBottleCheck)
          reason(<<~EOS)
            The bottle (and many others) needs to be installed into #{Homebrew::DEFAULT_PREFIX}.
          EOS
          satisfy { HOMEBREW_PREFIX.to_s == Homebrew::DEFAULT_PREFIX }
        end
      else
        raise ArgumentError, "Invalid preset `pour_bottle?` condition" if only_if.present?
      end

      @pour_bottle_check.instance_eval(&T.unsafe(block))
    end

    # Deprecates a {Formula} (on the given date) so a warning is
    # shown on each installation. If the date has not yet passed the formula
    # will not be deprecated.
    #
    # ### Examples
    #
    # ```ruby
    # deprecate! date: "2020-08-27", because: :unmaintained
    # ```
    #
    # ```ruby
    # deprecate! date: "2020-08-27", because: "has been replaced by foo"
    # ```
    #
    # ```ruby
    # deprecate! date: "2020-08-27", because: "has been replaced by foo", replacement: "foo"
    # ```
    #
    # @see https://docs.brew.sh/Deprecating-Disabling-and-Removing-Formulae
    # @see DeprecateDisable::FORMULA_DEPRECATE_DISABLE_REASONS
    # @api public
    sig { params(date: String, because: T.any(NilClass, String, Symbol), replacement: T.nilable(String)).void }
    def deprecate!(date:, because:, replacement: nil)
      @deprecation_date = T.let(Date.parse(date), T.nilable(Date))
      return if T.must(@deprecation_date) > Date.today

      @deprecation_reason = T.let(because, T.any(NilClass, String, Symbol))
      @deprecation_replacement = T.let(replacement, T.nilable(String))
      T.must(@deprecated = T.let(true, T.nilable(T::Boolean)))
    end

    # Whether this {Formula} is deprecated (i.e. warns on installation).
    # Defaults to false.
    # @see .deprecate!
    sig { returns(T::Boolean) }
    def deprecated?
      @deprecated == true
    end

    # The date that this {Formula} was or becomes deprecated.
    # Returns `nil` if no date is specified.
    #
    # @see .deprecate!
    sig { returns(T.nilable(Date)) }
    attr_reader :deprecation_date

    # The reason for deprecation of a {Formula}.
    #
    # @return [nil] if no reason was provided or the formula is not deprecated.
    # @see .deprecate!
    sig { returns(T.any(NilClass, String, Symbol)) }
    attr_reader :deprecation_reason

    # The replacement for a deprecated {Formula}.
    #
    # @return [nil] if no replacement was provided or the formula is not deprecated.
    # @see .deprecate!
    sig { returns(T.nilable(String)) }
    attr_reader :deprecation_replacement

    # Disables a {Formula} (on the given date) so it cannot be
    # installed. If the date has not yet passed the formula
    # will be deprecated instead of disabled.
    #
    # ### Examples
    #
    # ```ruby
    # disable! date: "2020-08-27", because: :does_not_build
    # ```
    #
    # ```ruby
    # disable! date: "2020-08-27", because: "has been replaced by foo"
    # ```
    #
    # ```ruby
    # disable! date: "2020-08-27", because: "has been replaced by foo", replacement: "foo"
    # ```
    #
    # @see https://docs.brew.sh/Deprecating-Disabling-and-Removing-Formulae
    # @see DeprecateDisable::FORMULA_DEPRECATE_DISABLE_REASONS
    # @api public
    sig { params(date: String, because: T.any(NilClass, String, Symbol), replacement: T.nilable(String)).void }
    def disable!(date:, because:, replacement: nil)
      @disable_date = T.let(Date.parse(date), T.nilable(Date))

      if T.must(@disable_date) > Date.today
        @deprecation_reason = T.let(because, T.any(NilClass, String, Symbol))
        @deprecation_replacement = T.let(replacement, T.nilable(String))
        @deprecated = T.let(true, T.nilable(T::Boolean))
        return
      end

      @disable_reason = T.let(because, T.nilable(T.any(String, Symbol)))
      @disable_replacement = T.let(replacement, T.nilable(String))
      @disabled = T.let(true, T.nilable(T::Boolean))
    end

    # Whether this {Formula} is disabled (i.e. cannot be installed).
    # Defaults to false.
    #
    # @see .disable!
    sig { returns(T::Boolean) }
    def disabled?
      @disabled == true
    end

    # The date that this {Formula} was or becomes disabled.
    # Returns `nil` if no date is specified.
    #
    # @see .disable!
    sig { returns(T.nilable(Date)) }
    attr_reader :disable_date

    # The reason this {Formula} is disabled.
    # Returns `nil` if no reason was provided or the formula is not disabled.
    #
    # @see .disable!
    sig { returns(T.any(NilClass, String, Symbol)) }
    attr_reader :disable_reason

    # The replacement for a disabled {Formula}.
    # Returns `nil` if no reason was provided or the formula is not disabled.
    #
    # @see .disable!
    sig { returns(T.nilable(String)) }
    attr_reader :disable_replacement

    # Permit overwriting certain files while linking.
    #
    # ### Examples
    #
    # Sometimes we accidentally install files outside the prefix. Once we fix that,
    # users will get a link conflict error. Overwrite those files with:
    #
    # ```ruby
    # link_overwrite "bin/foo", "lib/bar"
    # ```
    #
    # ```ruby
    # link_overwrite "share/man/man1/baz-*"
    # ```
    sig { params(paths: String).returns(T::Set[String]) }
    def link_overwrite(*paths)
      paths.flatten!
      T.must(link_overwrite_paths).merge(paths)
    end
  end
end

require "extend/os/formula"
