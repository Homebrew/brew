# typed: true
# frozen_string_literal: true

require "cache_store"
require "did_you_mean"
require "formula_support"
require "lock_file"
require "formula_pin"
require "hardware"
require "utils/bottles"
require "utils/shebang"
require "utils/shell"
require "build_environment"
require "build_options"
require "formulary"
require "software_spec"
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
require "extend/on_os"
require "bottle_api"

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
# <pre>class Wget < Formula
#   homepage "https://www.gnu.org/software/wget/"
#   url "https://ftp.gnu.org/gnu/wget/wget-1.15.tar.gz"
#   sha256 "52126be8cf1bddd7536886e74c053ad7d0ed2aa89b4b630f76785bac21695fcd"
#
#   def install
#     system "./configure", "--prefix=#{prefix}"
#     system "make", "install"
#   end
# end</pre>
class Formula
  extend T::Sig

  include FileUtils
  include Utils::Inreplace
  include Utils::Shebang
  include Utils::Shell
  include Context
  include OnOS
  extend Enumerable
  extend Forwardable
  extend Cachable
  extend Predicable

  # @!method inreplace(paths, before = nil, after = nil)
  # @see Utils::Inreplace.inreplace

  # The name of this {Formula}.
  # e.g. `this-formula`
  attr_reader :name

  # The path to the alias that was used to identify this {Formula}.
  # e.g. `/usr/local/Library/Taps/homebrew/homebrew-core/Aliases/another-name-for-this-formula`
  attr_reader :alias_path

  # The name of the alias that was used to identify this {Formula}.
  # e.g. `another-name-for-this-formula`
  attr_reader :alias_name

  # The fully-qualified name of this {Formula}.
  # For core formula it's the same as {#name}.
  # e.g. `homebrew/tap-name/this-formula`
  attr_reader :full_name

  # The fully-qualified alias referring to this {Formula}.
  # For core formula it's the same as {#alias_name}.
  # e.g. `homebrew/tap-name/another-name-for-this-formula`
  attr_reader :full_alias_name

  # The full path to this {Formula}.
  # e.g. `/usr/local/Library/Taps/homebrew/homebrew-core/Formula/this-formula.rb`
  attr_reader :path

  # The {Tap} instance associated with this {Formula}.
  # If it's `nil`, then this formula is loaded from a path or URL.
  # @private
  attr_reader :tap

  # The stable (and default) {SoftwareSpec} for this {Formula}.
  # This contains all the attributes (e.g. URL, checksum) that apply to the
  # stable version of this formula.
  # @private
  attr_reader :stable

  # The HEAD {SoftwareSpec} for this {Formula}.
  # Installed when using `brew install --HEAD`.
  # This is always installed with the version `HEAD` and taken from the latest
  # commit in the version control system.
  # `nil` if there is no HEAD version.
  # @see #stable
  # @private
  attr_reader :head

  # The currently active {SoftwareSpec}.
  # @see #determine_active_spec
  sig { returns(SoftwareSpec) }
  attr_reader :active_spec

  protected :active_spec

  # A symbol to indicate currently active {SoftwareSpec}.
  # It's either :stable or :head
  # @see #active_spec
  # @private
  attr_reader :active_spec_sym

  # most recent modified time for source files
  # @private
  attr_reader :source_modified_time

  # Used for creating new Homebrew versions of software without new upstream
  # versions.
  # @see .revision=
  attr_reader :revision

  # Used to change version schemes for packages.
  # @see .version_scheme=
  attr_reader :version_scheme

  # The current working directory during builds.
  # Will only be non-`nil` inside {#install}.
  attr_reader :buildpath

  # The current working directory during tests.
  # Will only be non-`nil` inside {.test}.
  attr_reader :testpath

  # When installing a bottle (binary package) from a local path this will be
  # set to the full path to the bottle tarball. If not, it will be `nil`.
  # @private
  attr_accessor :local_bottle_path

  # When performing a build, test, or other loggable action, indicates which
  # log file location to use.
  # @private
  attr_reader :active_log_type

  # The {BuildOptions} for this {Formula}. Lists the arguments passed and any
  # {.option}s in the {Formula}. Note that these may differ at different times
  # during the installation of a {Formula}. This is annoying but the result of
  # state that we're trying to eliminate.
  # @return [BuildOptions]
  attr_reader :build

  # Whether this formula should be considered outdated
  # if the target of the alias it was installed with has since changed.
  # Defaults to true.
  # @return [Boolean]
  attr_accessor :follow_installed_alias

  alias follow_installed_alias? follow_installed_alias

  # Whether or not to force the use of a bottle.
  # @return [Boolean]
  # @private
  attr_accessor :force_bottle

  # @private
  def initialize(name, path, spec, alias_path: nil, force_bottle: false)
    @name = name
    @path = path
    @alias_path = alias_path
    @alias_name = (File.basename(alias_path) if alias_path)
    @revision = self.class.revision || 0
    @version_scheme = self.class.version_scheme || 0

    @force_bottle = force_bottle

    @tap = if path == Formulary.core_path(name)
      CoreTap.instance
    else
      Tap.from_path(path)
    end

    @full_name = full_name_with_optional_tap(name)
    @full_alias_name = full_name_with_optional_tap(@alias_name)

    spec_eval :stable
    spec_eval :head

    @active_spec = determine_active_spec(spec)
    @active_spec_sym = if head?
      :head
    else
      :stable
    end
    validate_attributes!
    @build = active_spec.build
    @pin = FormulaPin.new(self)
    @follow_installed_alias = true
    @prefix_returns_versioned_prefix = false
    @oldname_lock = nil
  end

  # @private
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

  # @private
  def build=(build_options)
    old_options = @build
    @build = build_options

    return if old_options.used_options == build_options.used_options &&
              old_options.unused_options == build_options.unused_options

    Dependency.clear_cache
    Requirement.clear_cache
  end

  private

  # Allow full name logic to be re-used between names, aliases,
  # and installed aliases.
  def full_name_with_optional_tap(name)
    if name.nil? || @tap.nil? || @tap.core_tap?
      name
    else
      "#{@tap}/#{name}"
    end
  end

  def spec_eval(name)
    spec = self.class.send(name)
    return unless spec.url

    spec.owner = self
    instance_variable_set("@#{name}", spec)
  end

  def determine_active_spec(requested)
    spec = send(requested) || stable || head
    spec || raise(FormulaSpecificationError, "formulae require at least a URL")
  end

  def validate_attributes!
    raise FormulaValidationError.new(full_name, :name, name) if name.blank? || name.match?(/\s/)

    url = active_spec.url
    raise FormulaValidationError.new(full_name, :url, url) if url.blank? || url.match?(/\s/)

    val = version.respond_to?(:to_str) ? version.to_str : version
    return if val.present? && !val.match?(/\s/)

    raise FormulaValidationError.new(full_name, :version, val)
  end

  public

  # The alias path that was used to install this formula, if it exists.
  # Can differ from {#alias_path}, which is the alias used to find the formula,
  # and is specified to this instance.
  def installed_alias_path
    path = build.source["path"] if build.is_a?(Tab)
    return unless path&.match?(%r{#{HOMEBREW_TAP_DIR_REGEX}/Aliases}o)
    return unless File.symlink?(path)

    path
  end

  sig { returns(T.nilable(String)) }
  def installed_alias_name
    File.basename(installed_alias_path) if installed_alias_path
  end

  def full_installed_alias_name
    full_name_with_optional_tap(installed_alias_name)
  end

  # The path that was specified to find this formula.
  def specified_path
    alias_path || path
  end

  # The name specified to find this formula.
  def specified_name
    alias_name || name
  end

  # The name (including tap) specified to find this formula.
  def full_specified_name
    full_alias_name || full_name
  end

  # The name specified to install this formula.
  def installed_specified_name
    installed_alias_name || name
  end

  # The name (including tap) specified to install this formula.
  def full_installed_specified_name
    full_installed_alias_name || full_name
  end

  # Is the currently active {SoftwareSpec} a {#stable} build?
  # @private
  def stable?
    active_spec == stable
  end

  # Is the currently active {SoftwareSpec} a {#head} build?
  # @private
  def head?
    active_spec == head
  end

  # Is this formula HEAD-only?
  # @private
  def head_only?
    head && !stable
  end

  delegate [ # rubocop:disable Layout/HashAlignment
    :bottle_unneeded?,
    :bottle_disabled?,
    :bottle_disable_reason,
    :bottle_defined?,
    :bottle_tag?,
    :bottled?,
    :bottle_specification,
    :downloader,
  ] => :active_spec

  # The Bottle object for the currently active {SoftwareSpec}.
  # @private
  sig { returns(T.nilable(Bottle)) }
  def bottle
    @bottle ||= Bottle.new(self, bottle_specification) if bottled?
  end

  # The Bottle object for given tag.
  # @private
  sig { params(tag: T.nilable(String)).returns(T.nilable(Bottle)) }
  def bottle_for_tag(tag = nil)
    Bottle.new(self, bottle_specification, tag) if bottled?
  end

  # The description of the software.
  # @!method desc
  # @see .desc=
  delegate desc: :"self.class"

  # The SPDX ID of the software license.
  # @!method license
  # @see .license=
  delegate license: :"self.class"

  # The homepage for the software.
  # @!method homepage
  # @see .homepage=
  delegate homepage: :"self.class"

  # The livecheck specification for the software.
  # @!method livecheck
  # @see .livecheck=
  delegate livecheck: :"self.class"

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

  def update_head_version
    return unless head?
    return unless head.downloader.is_a?(VCSDownloadStrategy)
    return unless head.downloader.cached_location.exist?

    path = if ENV["HOMEBREW_ENV"]
      ENV["PATH"]
    else
      ENV["HOMEBREW_PATH"]
    end

    with_env(PATH: path) do
      head.version.update_commit(head.downloader.last_commit)
    end
  end

  # The {PkgVersion} for this formula with {version} and {#revision} information.
  sig { returns(PkgVersion) }
  def pkg_version
    PkgVersion.new(version, revision)
  end

  # If this is a `@`-versioned formula.
  def versioned_formula?
    name.include?("@")
  end

  # Returns any `@`-versioned formulae for any formula (including versioned formulae).
  def versioned_formulae
    Pathname.glob(path.to_s.gsub(/(@[\d.]+)?\.rb$/, "@*.rb")).map do |versioned_path|
      next if versioned_path == path

      Formula[versioned_path.basename(".rb").to_s]
    rescue FormulaUnavailableError
      nil
    end.compact.sort_by(&:version).reverse
  end

  # A named {Resource} for the currently active {SoftwareSpec}.
  # Additional downloads can be defined as {#resource}s.
  # {Resource#stage} will create a temporary directory and yield to a block.
  # <pre>resource("additional_files").stage { bin.install "my/extra/tool" }</pre>
  # @!method resource
  delegate resource: :active_spec

  # An old name for the formula.
  def oldname
    @oldname ||= if tap
      formula_renames = tap.formula_renames
      formula_renames.to_a.rassoc(name).first if formula_renames.value?(name)
    end
  end

  # All aliases for the formula.
  def aliases
    @aliases ||= if tap
      tap.alias_reverse_table[full_name].to_a.map do |a|
        a.split("/").last
      end
    else
      []
    end
  end

  # The {Resource}s for the currently active {SoftwareSpec}.
  # @!method resources
  def_delegator :"active_spec.resources", :values, :resources

  # The {Dependency}s for the currently active {SoftwareSpec}.
  delegate deps: :active_spec

  # Dependencies provided by macOS for the currently active {SoftwareSpec}.
  delegate uses_from_macos_elements: :active_spec

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
  # @private
  def latest_version_installed?
    latest_prefix = if ENV["HOMEBREW_JSON_CORE"].present? && (latest_pkg_version = BottleAPI.latest_pkg_version(name))
      prefix latest_pkg_version
    else
      latest_installed_prefix
    end

    (dir = latest_prefix).directory? && !dir.children.empty?
  end

  # If at least one version of {Formula} is installed.
  # @private
  def any_version_installed?
    installed_prefixes.any? { |keg| (keg/Tab::FILENAME).file? }
  end

  # @private
  # The link status symlink directory for this {Formula}.
  # You probably want {#opt_prefix} instead.
  def linked_keg
    linked_keg = possible_names.map { |name| HOMEBREW_LINKED_KEGS/name }
                               .find(&:directory?)
    return linked_keg if linked_keg.present?

    HOMEBREW_LINKED_KEGS/name
  end

  def latest_head_version
    head_versions = installed_prefixes.map do |pn|
      pn_pkgversion = PkgVersion.parse(pn.basename.to_s)
      pn_pkgversion if pn_pkgversion.head?
    end.compact

    head_versions.max_by do |pn_pkgversion|
      [Tab.for_keg(prefix(pn_pkgversion)).source_modified_time, pn_pkgversion.revision]
    end
  end

  def latest_head_prefix
    head_version = latest_head_version
    prefix(head_version) if head_version
  end

  def head_version_outdated?(version, fetch_head: false)
    tab = Tab.for_keg(prefix(version))

    return true if tab.version_scheme < version_scheme
    return true if stable && tab.stable_version && tab.stable_version < stable.version
    return false unless fetch_head
    return false unless head&.downloader.is_a?(VCSDownloadStrategy)

    downloader = head.downloader

    with_context quiet: true do
      downloader.commit_outdated?(version.version.commit)
    end
  end

  # The latest prefix for this formula. Checks for {#head} and then {#stable}'s {#prefix}
  # @private
  def latest_installed_prefix
    if head && (head_version = latest_head_version) && !head_version_outdated?(head_version)
      latest_head_prefix
    elsif stable && (stable_prefix = prefix(PkgVersion.new(stable.version, revision))).directory?
      stable_prefix
    else
      prefix
    end
  end

  # The directory in the cellar that the formula is installed to.
  # This directory points to {#opt_prefix} if it exists and if #{prefix} is not
  # called from within the same formula's {#install} or {#post_install} methods.
  # Otherwise, return the full path to the formula's versioned cellar.
  def prefix(v = pkg_version)
    versioned_prefix = versioned_prefix(v)
    if !@prefix_returns_versioned_prefix && v == pkg_version &&
       versioned_prefix.directory? && Keg.new(versioned_prefix).optlinked?
      opt_prefix
    else
      versioned_prefix
    end
  end

  # Is the formula linked?
  def linked?
    linked_keg.symlink?
  end

  # Is the formula linked to `opt`?
  def optlinked?
    opt_prefix.symlink?
  end

  # If a formula's linked keg points to the prefix.
  def prefix_linked?(v = pkg_version)
    return false unless linked?

    linked_keg.resolved_path == versioned_prefix(v)
  end

  # {PkgVersion} of the linked keg for the formula.
  sig { returns(T.nilable(PkgVersion)) }
  def linked_version
    return unless linked?

    Keg.for(linked_keg).version
  end

  # The parent of the prefix; the named directory in the cellar containing all
  # installed versions of this software.
  # @private
  sig { returns(Pathname) }
  def rack
    HOMEBREW_CELLAR/name
  end

  # All currently installed prefix directories.
  # @private
  def installed_prefixes
    possible_names.map { |name| HOMEBREW_CELLAR/name }
                  .select(&:directory?)
                  .flat_map(&:subdirs)
                  .sort_by(&:basename)
  end

  # All currently installed kegs.
  # @private
  def installed_kegs
    installed_prefixes.map { |dir| Keg.new(dir) }
  end

  # The directory where the formula's binaries should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  #
  # Need to install into the {.bin} but the makefile doesn't `mkdir -p prefix/bin`?
  # <pre>bin.mkpath</pre>
  #
  # No `make install` available?
  # <pre>bin.install "binary1"</pre>
  def bin
    prefix/"bin"
  end

  # The directory where the formula's documentation should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  def doc
    share/"doc"/name
  end

  # The directory where the formula's headers should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  #
  # No `make install` available?
  # <pre>include.install "example.h"</pre>
  def include
    prefix/"include"
  end

  # The directory where the formula's info files should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  def info
    share/"info"
  end

  # The directory where the formula's libraries should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  #
  # No `make install` available?
  # <pre>lib.install "example.dylib"</pre>
  def lib
    prefix/"lib"
  end

  # The directory where the formula's binaries should be installed.
  # This is not symlinked into `HOMEBREW_PREFIX`.
  # It is commonly used to install files that we do not wish to be
  # symlinked into `HOMEBREW_PREFIX` from one of the other directories and
  # instead manually create symlinks or wrapper scripts into e.g. {#bin}.
  # <pre>libexec.install "foo.jar"
  # bin.write_jar_script libexec/"foo.jar", "foo"
  # </pre>
  def libexec
    prefix/"libexec"
  end

  # The root directory where the formula's manual pages should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  # Often one of the more specific `man` functions should be used instead,
  # e.g. {#man1}.
  def man
    share/"man"
  end

  # The directory where the formula's man1 pages should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  #
  # No `make install` available?
  # <pre>man1.install "example.1"</pre>
  def man1
    man/"man1"
  end

  # The directory where the formula's man2 pages should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  def man2
    man/"man2"
  end

  # The directory where the formula's man3 pages should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  #
  # No `make install` available?
  # <pre>man3.install "man.3"</pre>
  def man3
    man/"man3"
  end

  # The directory where the formula's man4 pages should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  def man4
    man/"man4"
  end

  # The directory where the formula's man5 pages should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  def man5
    man/"man5"
  end

  # The directory where the formula's man6 pages should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  def man6
    man/"man6"
  end

  # The directory where the formula's man7 pages should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  def man7
    man/"man7"
  end

  # The directory where the formula's man8 pages should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  def man8
    man/"man8"
  end

  # The directory where the formula's `sbin` binaries should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  # Generally we try to migrate these to {#bin} instead.
  def sbin
    prefix/"sbin"
  end

  # The directory where the formula's shared files should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  #
  # Need a custom directory?
  # <pre>(share/"concept").mkpath</pre>
  #
  # Installing something into another custom directory?
  # <pre>(share/"concept2").install "ducks.txt"</pre>
  #
  # Install `./example_code/simple/ones` to `share/demos`:
  # <pre>(share/"demos").install "example_code/simple/ones"</pre>
  #
  # Install `./example_code/simple/ones` to `share/demos/examples`:
  # <pre>(share/"demos").install "example_code/simple/ones" => "examples"</pre>
  def share
    prefix/"share"
  end

  # The directory where the formula's shared files should be installed,
  # with the name of the formula appended to avoid linking conflicts.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  #
  # No `make install` available?
  # <pre>pkgshare.install "examples"</pre>
  def pkgshare
    prefix/"share"/name
  end

  # The directory where Emacs Lisp files should be installed, with the
  # formula name appended to avoid linking conflicts.
  #
  # To install an Emacs mode included with a software package:
  # <pre>elisp.install "contrib/emacs/example-mode.el"</pre>
  def elisp
    prefix/"share/emacs/site-lisp"/name
  end

  # The directory where the formula's Frameworks should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  # This is not symlinked into `HOMEBREW_PREFIX`.
  def frameworks
    prefix/"Frameworks"
  end

  # The directory where the formula's kernel extensions should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  # This is not symlinked into `HOMEBREW_PREFIX`.
  def kext_prefix
    prefix/"Library/Extensions"
  end

  # The directory where the formula's configuration files should be installed.
  # Anything using `etc.install` will not overwrite other files on e.g. upgrades
  # but will write a new file named `*.default`.
  # This directory is not inside the `HOMEBREW_CELLAR` so it persists
  # across upgrades.
  def etc
    (HOMEBREW_PREFIX/"etc").extend(InstallRenamed)
  end

  # A subdirectory of `etc` with the formula name suffixed.
  # e.g. `$HOMEBREW_PREFIX/etc/openssl@1.1`
  # Anything using `pkgetc.install` will not overwrite other files on
  # e.g. upgrades but will write a new file named `*.default`.
  def pkgetc
    (HOMEBREW_PREFIX/"etc"/name).extend(InstallRenamed)
  end

  # The directory where the formula's variable files should be installed.
  # This directory is not inside the `HOMEBREW_CELLAR` so it persists
  # across upgrades.
  def var
    HOMEBREW_PREFIX/"var"
  end

  # The directory where the formula's zsh function files should be
  # installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  def zsh_function
    share/"zsh/site-functions"
  end

  # The directory where the formula's fish function files should be
  # installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  def fish_function
    share/"fish/vendor_functions.d"
  end

  # The directory where the formula's Bash completion files should be
  # installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  def bash_completion
    prefix/"etc/bash_completion.d"
  end

  # The directory where the formula's zsh completion files should be
  # installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  def zsh_completion
    share/"zsh/site-functions"
  end

  # The directory where the formula's fish completion files should be
  # installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  def fish_completion
    share/"fish/vendor_completions.d"
  end

  # The directory used for as the prefix for {#etc} and {#var} files on
  # installation so, despite not being in `HOMEBREW_CELLAR`, they are installed
  # there after pouring a bottle.
  # @private
  def bottle_prefix
    prefix/".bottle"
  end

  # The directory where the formula's installation or test logs will be written.
  # @private
  def logs
    HOMEBREW_LOGS + name
  end

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
  def with_logging(log_type)
    old_log_type = @active_log_type
    @active_log_type = log_type
    yield
  ensure
    @active_log_type = old_log_type
  end

  # This method can be overridden to provide a plist.
  # @see https://www.unix.com/man-page/all/5/plist/ Apple's plist(5) man page
  # <pre>def plist; <<~EOS
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
  # end</pre>
  def plist
    nil
  end

  # The generated launchd {.plist} service name.
  sig { returns(String) }
  def plist_name
    "homebrew.mxcl.#{name}"
  end

  # The generated service name.
  sig { returns(String) }
  def service_name
    "homebrew.#{name}"
  end

  # The generated launchd {.plist} file path.
  sig { returns(Pathname) }
  def plist_path
    prefix/"#{plist_name}.plist"
  end

  # The generated systemd {.service} file path.
  sig { returns(Pathname) }
  def systemd_service_path
    prefix/"#{service_name}.service"
  end

  # The service specification of the software.
  def service
    return unless service?

    Homebrew::Service.new(self, &self.class.service)
  end

  # @private
  delegate plist_manual: :"self.class"

  # @private
  delegate plist_startup: :"self.class"

  # A stable path for this formula, when installed. Contains the formula name
  # but no version number. Only the active version will be linked here if
  # multiple versions are installed.
  #
  # This is the preferred way to refer to a formula in plists or from another
  # formula, as the path is stable even when the software is updated.
  # <pre>args << "--with-readline=#{Formula["readline"].opt_prefix}" if build.with? "readline"</pre>
  sig { returns(Pathname) }
  def opt_prefix
    HOMEBREW_PREFIX/"opt"/name
  end

  sig { returns(Pathname) }
  def opt_bin
    opt_prefix/"bin"
  end

  sig { returns(Pathname) }
  def opt_include
    opt_prefix/"include"
  end

  sig { returns(Pathname) }
  def opt_lib
    opt_prefix/"lib"
  end

  sig { returns(Pathname) }
  def opt_libexec
    opt_prefix/"libexec"
  end

  sig { returns(Pathname) }
  def opt_sbin
    opt_prefix/"sbin"
  end

  sig { returns(Pathname) }
  def opt_share
    opt_prefix/"share"
  end

  sig { returns(Pathname) }
  def opt_pkgshare
    opt_prefix/"share"/name
  end

  sig { returns(Pathname) }
  def opt_elisp
    opt_prefix/"share/emacs/site-lisp"/name
  end

  sig { returns(Pathname) }
  def opt_frameworks
    opt_prefix/"Frameworks"
  end

  # Indicates that this formula supports bottles. (Not necessarily that one
  # should be used in the current installation run.)
  # Can be overridden to selectively disable bottles from formulae.
  # Defaults to true so overridden version does not have to check if bottles
  # are supported.
  # Replaced by {.pour_bottle?}'s `satisfy` method if it is specified.
  sig { returns(T::Boolean) }
  def pour_bottle?
    true
  end

  # @private
  delegate pour_bottle_check_unsatisfied_reason: :"self.class"

  # Can be overridden to run commands on both source and bottle installation.
  sig { overridable.void }
  def post_install; end

  # @private
  sig { void }
  def run_post_install
    @prefix_returns_versioned_prefix = true
    build = self.build

    begin
      self.build = Tab.for_formula(self)

      new_env = {
        TMPDIR:        HOMEBREW_TEMP,
        TEMP:          HOMEBREW_TEMP,
        TMP:           HOMEBREW_TEMP,
        _JAVA_OPTIONS: "-Djava.io.tmpdir=#{HOMEBREW_TEMP}",
        HOMEBREW_PATH: nil,
        PATH:          ENV["HOMEBREW_PATH"],
      }

      with_env(new_env) do
        ENV.clear_sensitive_environment!
        ENV.activate_extensions!

        etc_var_dirs = [bottle_prefix/"etc", bottle_prefix/"var"]
        T.unsafe(Find).find(*etc_var_dirs.select(&:directory?)) do |path|
          path = Pathname.new(path)
          path.extend(InstallRenamed)
          path.cp_path_sub(bottle_prefix, HOMEBREW_PREFIX)
        end

        with_logging("post_install") do
          post_install
        end
      end
    ensure
      self.build = build
      @prefix_returns_versioned_prefix = false
    end
  end

  # Warn the user about any Homebrew-specific issues or quirks for this package.
  # These should not contain setup instructions that would apply to installation
  # through a different package manager on a different OS.
  # @return [String]
  # <pre>def caveats
  #   <<~EOS
  #     Are optional. Something the user must be warned about?
  #   EOS
  # end</pre>
  #
  # <pre>def caveats
  #   s = <<~EOS
  #     Print some important notice to the user when `brew info [formula]` is
  #     called or when brewing a formula.
  #     This is optional. You can use all the vars like #{version} here.
  #   EOS
  #   s += "Some issue only on older systems" if MacOS.version < :el_capitan
  #   s
  # end</pre>
  sig { overridable.returns(T.nilable(String)) }
  def caveats
    nil
  end

  # Rarely, you don't want your library symlinked into the main prefix.
  # See `gettext.rb` for an example.
  # @see .keg_only
  def keg_only?
    return false unless keg_only_reason

    keg_only_reason.applicable?
  end

  # @private
  delegate keg_only_reason: :"self.class"

  # @see .skip_clean
  # @private
  sig { params(path: Pathname).returns(T::Boolean) }
  def skip_clean?(path)
    return true if path.extname == ".la" && self.class.skip_clean_paths.include?(:la)

    to_check = path.relative_path_from(prefix).to_s
    self.class.skip_clean_paths.include? to_check
  end

  # @see .link_overwrite
  # @private
  def link_overwrite?(path)
    # Don't overwrite files not created by Homebrew.
    return false unless path.stat.uid == HOMEBREW_BREW_FILE.stat.uid

    # Don't overwrite files belong to other keg except when that
    # keg's formula is deleted.
    begin
      keg = Keg.for(path)
    rescue NotAKegError, Errno::ENOENT
      # file doesn't belong to any keg.
    else
      tab_tap = Tab.for_keg(keg).tap
      # this keg doesn't below to any core/tap formula, most likely coming from a DIY install.
      return false if tab_tap.nil?

      begin
        f = Formulary.factory(keg.name)
      rescue FormulaUnavailableError
        # formula for this keg is deleted, so defer to allowlist
      rescue TapFormulaAmbiguityError, TapFormulaWithOldnameAmbiguityError
        return false # this keg belongs to another formula
      else
        # this keg belongs to another unrelated formula
        return false unless f.possible_names.include?(keg.name)
      end
    end
    to_check = path.relative_path_from(HOMEBREW_PREFIX).to_s
    self.class.link_overwrite_paths.any? do |p|
      p == to_check ||
        to_check.start_with?("#{p.chomp("/")}/") ||
        to_check =~ /^#{Regexp.escape(p).gsub('\*', ".*?")}$/
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

  sig { returns(T::Boolean) }
  def skip_cxxstdlib_check?
    false
  end

  # @private
  sig { returns(T::Boolean) }
  def require_universal_deps?
    false
  end

  # @private
  def patch
    return if patchlist.empty?

    ohai "Patching"
    patchlist.each(&:apply)
  end

  # Yields |self,staging| with current working directory set to the uncompressed tarball
  # where staging is a {Mktemp} staging context.
  # @private
  def brew(fetch: true, keep_tmp: false, interactive: false)
    @prefix_returns_versioned_prefix = true
    active_spec.fetch if fetch
    stage(interactive: interactive) do |staging|
      staging.retain! if keep_tmp

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
          CMakeOutput.log
          CMakeError.log
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
    @prefix_returns_versioned_prefix = false
  end

  # @private
  def lock
    @lock = FormulaLock.new(name)
    @lock.lock
    return unless oldname
    return unless (oldname_rack = HOMEBREW_CELLAR/oldname).exist?
    return unless oldname_rack.resolved_path == rack

    @oldname_lock = FormulaLock.new(oldname)
    @oldname_lock.lock
  end

  # @private
  def unlock
    @lock&.unlock
    @oldname_lock&.unlock
  end

  def migration_needed?
    return false unless oldname
    return false if rack.exist?

    old_rack = HOMEBREW_CELLAR/oldname
    return false unless old_rack.directory?
    return false if old_rack.subdirs.empty?

    tap == Tab.for_keg(old_rack.subdirs.min).tap
  end

  # @private
  def outdated_kegs(fetch_head: false)
    raise Migrator::MigrationNeededError, self if migration_needed?

    cache_key = "#{full_name}-#{fetch_head}"
    Formula.cache[:outdated_kegs] ||= {}
    Formula.cache[:outdated_kegs][cache_key] ||= begin
      all_kegs = []
      current_version = T.let(false, T::Boolean)
      latest_version = if ENV["HOMEBREW_JSON_CORE"].present? && (core_formula? || tap.blank?)
        BottleAPI.latest_pkg_version(name) || pkg_version
      else
        pkg_version
      end

      installed_kegs.each do |keg|
        all_kegs << keg
        version = keg.version
        next if version.head?

        tab = Tab.for_keg(keg)
        next if version_scheme > tab.version_scheme && latest_version != version
        next if version_scheme == tab.version_scheme && latest_version > version

        # don't consider this keg current if there's a newer formula available
        next if follow_installed_alias? && new_formula_available?

        # this keg is the current version of the formula, so it's not outdated
        current_version = true
        break
      end

      if current_version ||
         ((head_version = latest_head_version) && !head_version_outdated?(head_version, fetch_head: fetch_head))
        []
      else
        all_kegs += old_installed_formulae.flat_map(&:installed_kegs)
        all_kegs.sort_by(&:version)
      end
    end
  end

  def new_formula_available?
    installed_alias_target_changed? && !latest_formula.latest_version_installed?
  end

  def current_installed_alias_target
    Formulary.factory(installed_alias_path) if installed_alias_path
  end

  # Has the target of the alias used to install this formula changed?
  # Returns false if the formula wasn't installed with an alias.
  def installed_alias_target_changed?
    target = current_installed_alias_target
    return false unless target

    target.name != name
  end

  # Is this formula the target of an alias used to install an old formula?
  def supersedes_an_installed_formula?
    old_installed_formulae.any?
  end

  # Has the alias used to install the formula changed, or are different
  # formulae already installed with this alias?
  def alias_changed?
    installed_alias_target_changed? || supersedes_an_installed_formula?
  end

  # If the alias has changed value, return the new formula.
  # Otherwise, return self.
  def latest_formula
    installed_alias_target_changed? ? current_installed_alias_target : self
  end

  def old_installed_formulae
    # If this formula isn't the current target of the alias,
    # it doesn't make sense to say that other formulae are older versions of it
    # because we don't know which came first.
    return [] if alias_path.nil? || installed_alias_target_changed?

    self.class.installed_with_alias_path(alias_path).reject { |f| f.name == name }
  end

  # @private
  def outdated?(fetch_head: false)
    !outdated_kegs(fetch_head: fetch_head).empty?
  rescue Migrator::MigrationNeededError
    true
  end

  # @private
  delegate pinnable?: :@pin

  # @private
  delegate pinned?: :@pin

  # @private
  delegate pinned_version: :@pin

  # @private
  delegate pin: :@pin

  # @private
  delegate unpin: :@pin

  # @private
  def ==(other)
    instance_of?(other.class) &&
      name == other.name &&
      active_spec == other.active_spec
  end
  alias eql? ==

  # @private
  def hash
    name.hash
  end

  # @private
  def <=>(other)
    return unless other.is_a?(Formula)

    name <=> other.name
  end

  # @private
  def possible_names
    [name, oldname, *aliases].compact
  end

  def to_s
    name
  end

  # @private
  sig { returns(String) }
  def inspect
    "#<Formula #{name} (#{active_spec_sym}) #{path}>"
  end

  # Standard parameters for configure builds.
  sig { returns(T::Array[String]) }
  def std_configure_args
    ["--disable-debug", "--disable-dependency-tracking", "--prefix=#{prefix}", "--libdir=#{lib}"]
  end

  # Standard parameters for cargo builds.
  sig { params(root: String, path: String).returns(T::Array[T.any(String, Pathname)]) }
  def std_cargo_args(root: prefix, path: ".")
    ["--locked", "--root", root, "--path", path]
  end

  # Standard parameters for CMake builds.
  #
  # Setting `CMAKE_FIND_FRAMEWORK` to "LAST" tells CMake to search for our
  # libraries before trying to utilize Frameworks, many of which will be from
  # 3rd party installs.
  sig { returns(T::Array[String]) }
  def std_cmake_args
    args = %W[
      -DCMAKE_INSTALL_PREFIX=#{prefix}
      -DCMAKE_INSTALL_LIBDIR=lib
      -DCMAKE_BUILD_TYPE=Release
      -DCMAKE_FIND_FRAMEWORK=LAST
      -DCMAKE_VERBOSE_MAKEFILE=ON
      -Wno-dev
      -DBUILD_TESTING=OFF
    ]

    # Avoid false positives for clock_gettime support on 10.11.
    # CMake cache entries for other weak symbols may be added here as needed.
    args << "-DHAVE_CLOCK_GETTIME:INTERNAL=0" if MacOS.version == "10.11" && MacOS::Xcode.version >= "8.0"

    # Ensure CMake is using the same SDK we are using.
    args << "-DCMAKE_OSX_SYSROOT=#{MacOS.sdk_for_formula(self).path}" if MacOS.sdk_root_needed?

    args
  end

  # Standard parameters for Go builds.
  sig { params(ldflags: T.nilable(String)).returns(T::Array[String]) }
  def std_go_args(ldflags: nil)
    args = ["-trimpath", "-o=#{bin/name}"]
    args += ["-ldflags=#{ldflags}"] if ldflags
    args
  end

  # Standard parameters for cabal-v2 builds.
  sig { returns(T::Array[String]) }
  def std_cabal_v2_args
    env = T.cast(ENV, T.any(Stdenv, Superenv))

    # cabal-install's dependency-resolution backtracking strategy can
    # easily need more than the default 2,000 maximum number of
    # "backjumps," since Hackage is a fast-moving, rolling-release
    # target. The highest known needed value by a formula was 43,478
    # for git-annex, so 100,000 should be enough to avoid most
    # gratuitous backjumps build failures.
    ["--jobs=#{env.make_jobs}", "--max-backjumps=100000", "--install-method=copy", "--installdir=#{bin}"]
  end

  # Standard parameters for meson builds.
  sig { returns(T::Array[String]) }
  def std_meson_args
    ["--prefix=#{prefix}", "--libdir=#{lib}", "--buildtype=release", "--wrap-mode=nofallback"]
  end

  # Shared library names according to platform conventions.
  #
  # Optionally specify a `version` to restrict the shared library to a specific
  # version. The special string "*" matches any version.
  #
  # If `name` is specified as "*", match any shared library of any version.
  #
  # <pre>
  # shared_library("foo")      #=> foo.dylib
  # shared_library("foo", 1)   #=> foo.1.dylib
  # shared_library("foo", "*") #=> foo.2.dylib, foo.1.dylib, foo.dylib
  # shared_library("*")        #=> foo.dylib, bar.dylib
  # </pre>
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
  sig { returns(String) }
  def rpath
    "@loader_path/../lib"
  end

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

  sig { params(targets: T.nilable(T.any(Pathname, String))).void }
  def deuniversalize_machos(*targets)
    if targets.blank?
      targets = any_installed_keg.mach_o_files.select do |file|
        file.arch == :universal && file.archs.include?(Hardware::CPU.arch)
      end
    end

    targets.each do |t|
      macho = MachO::FatFile.new(t)
      native_slice = macho.extract(Hardware::CPU.arch)
      native_slice.write t
    end
  end

  # an array of all core {Formula} names
  # @private
  def self.core_names
    CoreTap.instance.formula_names
  end

  # an array of all core {Formula} files
  # @private
  def self.core_files
    CoreTap.instance.formula_files
  end

  # an array of all tap {Formula} names
  # @private
  def self.tap_names
    @tap_names ||= Tap.reject(&:core_tap?).flat_map(&:formula_names).sort
  end

  # an array of all tap {Formula} files
  # @private
  def self.tap_files
    @tap_files ||= Tap.reject(&:core_tap?).flat_map(&:formula_files)
  end

  # an array of all {Formula} names
  # @private
  def self.names
    @names ||= (core_names + tap_names.map { |name| name.split("/").last }).uniq.sort
  end

  # an array of all {Formula} files
  # @private
  def self.files
    @files ||= core_files + tap_files
  end

  # an array of all {Formula} names, which the tap formulae have the fully-qualified name
  # @private
  def self.full_names
    @full_names ||= core_names + tap_names
  end

  # @private
  def self.each(&block)
    files.each do |file|
      block.call Formulary.factory(file)
    rescue FormulaUnavailableError, FormulaUnreadableError => e
      # Don't let one broken formula break commands. But do complain.
      onoe "Failed to import: #{file}"
      $stderr.puts e
      next
    end
  end

  # An array of all racks currently installed.
  # @private
  def self.racks
    Formula.cache[:racks] ||= if HOMEBREW_CELLAR.directory?
      HOMEBREW_CELLAR.subdirs.reject do |rack|
        rack.symlink? || rack.basename.to_s.start_with?(".") || rack.subdirs.empty?
      end
    else
      []
    end
  end

  # An array of all installed {Formula}
  # @private
  def self.installed
    Formula.cache[:installed] ||= racks.flat_map do |rack|
      Formulary.from_rack(rack)
    rescue
      []
    end.uniq(&:name)
  end

  # An array of all installed {Formula} without dependents
  # @private
  def self.installed_formulae_with_no_dependents(formulae = installed)
    return [] if formulae.blank?

    formulae - formulae.flat_map(&:runtime_formula_dependencies)
  end

  def self.installed_with_alias_path(alias_path)
    return [] if alias_path.nil?

    installed.select { |f| f.installed_alias_path == alias_path }
  end

  # an array of all alias files of core {Formula}
  # @private
  def self.core_alias_files
    CoreTap.instance.alias_files
  end

  # an array of all core aliases
  # @private
  def self.core_aliases
    CoreTap.instance.aliases
  end

  # an array of all tap aliases
  # @private
  def self.tap_aliases
    @tap_aliases ||= Tap.reject(&:core_tap?).flat_map(&:aliases).sort
  end

  # an array of all aliases
  # @private
  def self.aliases
    @aliases ||= (core_aliases + tap_aliases.map { |name| name.split("/").last }).uniq.sort
  end

  # an array of all aliases, , which the tap formulae have the fully-qualified name
  # @private
  def self.alias_full_names
    @alias_full_names ||= core_aliases + tap_aliases
  end

  # a table mapping core alias to formula name
  # @private
  def self.core_alias_table
    CoreTap.instance.alias_table
  end

  # a table mapping core formula name to aliases
  # @private
  def self.core_alias_reverse_table
    CoreTap.instance.alias_reverse_table
  end

  # Returns a list of approximately matching formula names, but not the complete match
  # @private
  def self.fuzzy_search(name)
    @spell_checker ||= DidYouMean::SpellChecker.new(dictionary: Set.new(names + full_names).to_a)
    @spell_checker.correct(name)
  end

  def self.[](name)
    Formulary.factory(name)
  end

  # True if this formula is provided by Homebrew itself
  # @private
  def core_formula?
    tap&.core_tap?
  end

  # True if this formula is provided by external Tap
  # @private
  def tap?
    return false unless tap

    !tap.core_tap?
  end

  # @private
  def print_tap_action(options = {})
    return unless tap?

    verb = options[:verb] || "Installing"
    ohai "#{verb} #{name} from #{tap}"
  end

  # @private
  delegate env: :"self.class"

  # @private
  delegate conflicts: :"self.class"

  # Returns a list of Dependency objects in an installable order, which
  # means if a depends on b then b will be ordered before a in this list
  # @private
  def recursive_dependencies(&block)
    cache_key = "Formula#recursive_dependencies" unless block
    Dependency.expand(self, cache_key: cache_key, &block)
  end

  # The full set of Requirements for this formula's dependency tree.
  # @private
  def recursive_requirements(&block)
    cache_key = "Formula#recursive_requirements" unless block
    Requirement.expand(self, cache_key: cache_key, &block)
  end

  # Returns a Keg for the opt_prefix or installed_prefix if they exist.
  # If not, return `nil`.
  # @private
  def any_installed_keg
    Formula.cache[:any_installed_keg] ||= {}
    Formula.cache[:any_installed_keg][full_name] ||= if (installed_prefix = any_installed_prefix)
      Keg.new(installed_prefix)
    end
  end

  def any_installed_prefix
    if optlinked? && opt_prefix.exist?
      opt_prefix
    elsif (latest_installed_prefix = installed_prefixes.last)
      latest_installed_prefix
    end
  end

  # Returns the {PkgVersion} for this formula if it is installed.
  # If not, return `nil`.
  def any_installed_version
    any_installed_keg&.version
  end

  # Returns a list of Dependency objects that are required at runtime.
  # @private
  def runtime_dependencies(read_from_tab: true, undeclared: true)
    deps = if read_from_tab && undeclared &&
              (tab_deps = any_installed_keg&.runtime_dependencies)
      tab_deps.map do |d|
        full_name = d["full_name"]
        next unless full_name

        Dependency.new full_name
      end.compact
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
  # @private
  def runtime_formula_dependencies(read_from_tab: true, undeclared: true)
    cache_key = "#{full_name}-#{read_from_tab}-#{undeclared}"

    Formula.cache[:runtime_formula_dependencies] ||= {}
    Formula.cache[:runtime_formula_dependencies][cache_key] ||= runtime_dependencies(
      read_from_tab: read_from_tab,
      undeclared:    undeclared,
    ).map do |d|
      d.to_formula
    rescue FormulaUnavailableError
      nil
    end.compact
  end

  def runtime_installed_formula_dependents
    # `any_installed_keg` and `runtime_dependencies` `select`s ensure
    # that we don't end up with something `Formula#runtime_dependencies` can't
    # read from a `Tab`.
    Formula.cache[:runtime_installed_formula_dependents] = {}
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
  def missing_dependencies(hide: nil)
    hide ||= []
    runtime_formula_dependencies.select do |f|
      hide.include?(f.name) || f.installed_prefixes.empty?
    end
  # If we're still getting unavailable formulae at this stage the best we can
  # do is just return no results.
  rescue FormulaUnavailableError
    []
  end

  # @private
  def to_hash
    dependencies = deps
    uses_from_macos = uses_from_macos_elements || []

    hsh = {
      "name"                     => name,
      "full_name"                => full_name,
      "tap"                      => tap&.name,
      "oldname"                  => oldname,
      "aliases"                  => aliases.sort,
      "versioned_formulae"       => versioned_formulae.map(&:name),
      "desc"                     => desc,
      "license"                  => SPDX.license_expression_to_string(license),
      "homepage"                 => homepage,
      "versions"                 => {
        "stable" => stable&.version&.to_s,
        "head"   => head&.version&.to_s,
        "bottle" => !bottle_specification.checksums.empty?,
      },
      "urls"                     => {},
      "revision"                 => revision,
      "version_scheme"           => version_scheme,
      "bottle"                   => {},
      "keg_only"                 => keg_only?,
      "bottle_disabled"          => bottle_disabled?,
      "options"                  => [],
      "build_dependencies"       => dependencies.select(&:build?)
                                                .map(&:name)
                                                .uniq,
      "dependencies"             => dependencies.reject(&:optional?)
                                                .reject(&:recommended?)
                                                .reject(&:build?)
                                                .map(&:name)
                                                .uniq,
      "recommended_dependencies" => dependencies.select(&:recommended?)
                                                .map(&:name)
                                                .uniq,
      "optional_dependencies"    => dependencies.select(&:optional?)
                                                .map(&:name)
                                                .uniq,
      "uses_from_macos"          => uses_from_macos.uniq,
      "requirements"             => [],
      "conflicts_with"           => conflicts.map(&:name),
      "caveats"                  => caveats&.gsub(HOMEBREW_PREFIX, "$(brew --prefix)"),
      "installed"                => [],
      "linked_keg"               => linked_version&.to_s,
      "pinned"                   => pinned?,
      "outdated"                 => outdated?,
      "deprecated"               => deprecated?,
      "deprecation_date"         => deprecation_date,
      "deprecation_reason"       => deprecation_reason,
      "disabled"                 => disabled?,
      "disable_date"             => disable_date,
      "disable_reason"           => disable_reason,
    }

    if stable
      hsh["urls"]["stable"] = {
        "url"      => stable.url,
        "tag"      => stable.specs[:tag],
        "revision" => stable.specs[:revision],
      }

      hsh["bottle"]["stable"] = bottle_hash if bottle_defined?
    end

    hsh["options"] = options.map do |opt|
      { "option" => opt.flag, "description" => opt.description }
    end

    hsh["requirements"] = requirements.map do |req|
      req.name.prepend("maximum_") if req.try(:comparator) == "<="
      {
        "name"     => req.name,
        "cask"     => req.cask,
        "download" => req.download,
        "version"  => req.try(:version) || req.try(:arch),
        "contexts" => req.tags,
      }
    end

    hsh["installed"] = installed_kegs.sort_by(&:version).map do |keg|
      tab = Tab.for_keg keg
      {
        "version"                 => keg.version.to_s,
        "used_options"            => tab.used_options.as_flags,
        "built_as_bottle"         => tab.built_as_bottle,
        "poured_from_bottle"      => tab.poured_from_bottle,
        "runtime_dependencies"    => tab.runtime_dependencies,
        "installed_as_dependency" => tab.installed_as_dependency,
        "installed_on_request"    => tab.installed_on_request,
      }
    end

    hsh
  end

  # @api private
  # Generate a hash to be used to install a formula from a JSON file
  def to_recursive_bottle_hash(top_level: true)
    bottle = bottle_hash

    bottles = bottle["files"].map do |tag, file|
      info = { "url" => file["url"] }
      info["sha256"] = file["sha256"] if tap.name != "homebrew/core"
      [tag.to_s, info]
    end.to_h

    hash = {
      "name"        => name,
      "pkg_version" => pkg_version,
      "rebuild"     => bottle["rebuild"],
      "bottles"     => bottles,
    }

    return hash unless top_level

    hash["dependencies"] = declared_runtime_dependencies.map do |dep|
      dep.to_formula.to_recursive_bottle_hash(top_level: false)
    end
    hash
  end

  # Returns the bottle information for a formula
  def bottle_hash
    bottle_spec = stable.bottle_specification
    hash = {
      "rebuild"  => bottle_spec.rebuild,
      "root_url" => bottle_spec.root_url,
      "files"    => {},
    }
    bottle_spec.collector.each_key do |os|
      collector_os = bottle_spec.collector[os]
      os_cellar = collector_os[:cellar]
      os_cellar = os_cellar.is_a?(Symbol) ? os_cellar.inspect : os_cellar

      checksum = collector_os[:checksum].hexdigest
      filename = Bottle::Filename.create(self, os, bottle_spec.rebuild)
      path, = Utils::Bottles.path_resolved_basename(bottle_spec.root_url, name, checksum, filename)
      url = "#{bottle_spec.root_url}/#{path}"

      hash["files"][os] = {
        "cellar" => os_cellar,
        "url"    => url,
        "sha256" => checksum,
      }
    end
    hash
  end

  # @private
  def fetch(verify_download_integrity: true)
    active_spec.fetch(verify_download_integrity: verify_download_integrity)
  end

  # @private
  def verify_download_integrity(fn)
    active_spec.verify_download_integrity(fn)
  end

  # @private
  def run_test(keep_tmp: false)
    @prefix_returns_versioned_prefix = true

    test_env = {
      TMPDIR:        HOMEBREW_TEMP,
      TEMP:          HOMEBREW_TEMP,
      TMP:           HOMEBREW_TEMP,
      TERM:          "dumb",
      PATH:          PATH.new(ENV["PATH"], HOMEBREW_PREFIX/"bin"),
      HOMEBREW_PATH: nil,
    }.merge(common_stage_test_env)
    test_env[:_JAVA_OPTIONS] += " -Djava.io.tmpdir=#{HOMEBREW_TEMP}"

    ENV.clear_sensitive_environment!
    Utils::Git.set_name_email!

    mktemp("#{name}-test") do |staging|
      staging.retain! if keep_tmp
      @testpath = staging.tmpdir
      test_env[:HOME] = @testpath
      setup_home @testpath
      begin
        with_logging("test") do
          with_env(test_env) do
            test
          end
        end
      rescue Exception # rubocop:disable Lint/RescueException
        staging.retain! if debug?
        raise
      end
    end
  ensure
    @prefix_returns_versioned_prefix = false
    @testpath = nil
  end

  # @private
  sig { returns(T::Boolean) }
  def test_defined?
    false
  end

  # @private
  def test; end

  # @private
  def test_fixtures(file)
    HOMEBREW_LIBRARY_PATH/"test/support/fixtures"/file
  end

  # This method is overridden in {Formula} subclasses to provide the
  # installation instructions. The sources (from {.url}) are downloaded,
  # hash-checked and then Homebrew changes into a temporary directory where the
  # archive is unpacked or repository cloned.
  # <pre>def install
  #   system "./configure", "--prefix=#{prefix}"
  #   system "make", "install"
  # end</pre>
  def install; end

  protected

  def setup_home(home)
    # keep Homebrew's site-packages in sys.path when using system Python
    user_site_packages = home/"Library/Python/2.7/lib/python/site-packages"
    user_site_packages.mkpath
    (user_site_packages/"homebrew.pth").write <<~PYTHON
      import site; site.addsitedir("#{HOMEBREW_PREFIX}/lib/python2.7/site-packages")
      import sys, os; sys.path = (os.environ["PYTHONPATH"].split(os.pathsep) if "PYTHONPATH" in os.environ else []) + ["#{HOMEBREW_PREFIX}/lib/python2.7/site-packages"] + sys.path
    PYTHON

    # Don't let bazel write to tmp directories we don't control or clean.
    (home/".bazelrc").write "startup --output_user_root=#{home}/_bazel"
  end

  # Returns a list of Dependency objects that are declared in the formula.
  # @private
  def declared_runtime_dependencies
    recursive_dependencies do |_, dependency|
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
  # @private
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
  # <pre>system "./bootstrap.sh", "--arg1", "--prefix=#{prefix}"</pre>
  #
  # For CMake and other build systems we have some necessary defaults in e.g.
  # {#std_cmake_args}:
  # <pre>system "cmake", ".", *std_cmake_args</pre>
  #
  # If the arguments given to `configure` (or `make` or `cmake`) are depending
  # on options defined above, we usually make a list first and then
  # use the `args << if <condition>` to append each:
  # <pre>args = ["--with-option1", "--with-option2"]
  # args << "--without-gcc" if ENV.compiler == :clang
  #
  # # Most software still uses `configure` and `make`.
  # # Check with `./configure --help` for what our options are.
  # system "./configure", "--disable-debug", "--disable-dependency-tracking",
  #                       "--disable-silent-rules", "--prefix=#{prefix}",
  #                       *args # our custom arg list (needs `*` to unpack)
  #
  # # If there is a "make install" available, please use it!
  # system "make", "install"</pre>
  sig { params(cmd: T.any(String, Pathname), args: T.any(String, Pathname, Integer)).void }
  def system(cmd, *args)
    verbose_using_dots = Homebrew::EnvConfig.verbose_using_dots?

    # remove "boring" arguments so that the important ones are more likely to
    # be shown considering that we trim long ohai lines to the terminal width
    pretty_args = args.dup
    unless verbose?
      case cmd
      when "./configure"
        pretty_args -= %w[--disable-dependency-tracking --disable-debug --disable-silent-rules]
      when "cargo"
        pretty_args -= std_cargo_args
      when "cmake"
        pretty_args -= std_cmake_args
      when "go"
        pretty_args -= std_go_args
      end
    end
    pretty_args.each_index do |i|
      pretty_args[i] = "import setuptools..." if pretty_args[i].to_s.start_with? "import setuptools"
    end
    ohai "#{cmd} #{pretty_args * " "}".strip

    @exec_count ||= 0
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
              next unless (Time.now - last_dot) > 60

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

      Process.wait(T.must(pid))

      $stdout.flush

      unless $CHILD_STATUS.success?
        log_lines = Homebrew::EnvConfig.fail_log_lines

        log.flush
        if !verbose? || verbose_using_dots
          puts "Last #{log_lines} lines from #{logfn}:"
          Kernel.system "/usr/bin/tail", "-n", log_lines, logfn
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

  # @private
  def eligible_kegs_for_cleanup(quiet: false)
    eligible_for_cleanup = []
    if latest_version_installed?
      eligible_kegs = if head? && (head_prefix = latest_head_prefix)
        head, stable = installed_kegs.partition { |k| k.version.head? }
        # Remove newest head and stable kegs
        head - [Keg.new(head_prefix)] + stable.sort_by(&:version).slice(0...-1)
      else
        installed_kegs.select do |keg|
          tab = Tab.for_keg(keg)
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
  def mktemp(prefix = name, opts = {}, &block)
    Mktemp.new(prefix, opts).run(&block)
  end

  # A version of `FileUtils.mkdir` that also changes to that folder in
  # a block.
  def mkdir(name, &block)
    result = FileUtils.mkdir_p(name)
    return result unless block

    FileUtils.chdir(name, &block)
  end

  # Runs `xcodebuild` without Homebrew's compiler environment variables set.
  sig { params(args: T.any(String, Pathname)).void }
  def xcodebuild(*args)
    removed = ENV.remove_cc_etc

    begin
      T.unsafe(self).system("xcodebuild", *args)
    ensure
      ENV.update(removed)
    end
  end

  def fetch_patches
    patchlist.select(&:external?).each(&:fetch)
  end

  sig { void }
  def fetch_bottle_tab
    return unless bottled?

    T.must(bottle).fetch_tab
  end

  sig { returns(Hash) }
  def bottle_tab_attributes
    return {} unless bottled?

    T.must(bottle).tab_attributes
  end

  private

  def prepare_patches
    patchlist.grep(DATAPatch) { |p| p.path = path }
  end

  # Returns the prefix for a given formula version number.
  # @private
  def versioned_prefix(v)
    rack/v
  end

  def exec_cmd(cmd, args, out, logfn)
    ENV["HOMEBREW_CC_LOG_PATH"] = logfn

    ENV.remove_cc_etc if cmd.to_s.start_with? "xcodebuild"

    # Turn on argument filtering in the superenv compiler wrapper.
    # We should probably have a better mechanism for this than adding
    # special cases to this method.
    if cmd == "python"
      setup_py_in_args = %w[setup.py build.py].include?(args.first)
      setuptools_shim_in_args = args.any? { |a| a.to_s.start_with? "import setuptools" }
      env = T.cast(ENV, T.any(Stdenv, Superenv))
      env.refurbish_args if setup_py_in_args || setuptools_shim_in_args
    end

    $stdout.reopen(out)
    $stderr.reopen(out)
    out.close
    args.map!(&:to_s)
    begin
      T.unsafe(Kernel).exec(cmd, *args)
    rescue
      nil
    end
    puts "Failed to execute: #{cmd}"
    exit! 1 # never gets here unless exec threw or failed
  end

  # Common environment variables used at both build and test time.
  def common_stage_test_env
    {
      _JAVA_OPTIONS: "-Duser.home=#{HOMEBREW_CACHE}/java_cache",
      GOCACHE:       "#{HOMEBREW_CACHE}/go_cache",
      GOPATH:        "#{HOMEBREW_CACHE}/go_mod_cache",
      CARGO_HOME:    "#{HOMEBREW_CACHE}/cargo_cache",
      CURL_HOME:     ENV["CURL_HOME"] || ENV["HOME"],
    }
  end

  def stage(interactive: false)
    active_spec.stage do |staging|
      @source_modified_time = active_spec.source_modified_time
      @buildpath = Pathname.pwd
      env_home = buildpath/".brew_home"
      mkdir_p env_home

      stage_env = {
        HOMEBREW_PATH: nil,
      }

      unless interactive
        stage_env[:HOME] = env_home
        stage_env.merge!(common_stage_test_env)
      end

      setup_home env_home

      ENV.clear_sensitive_environment!

      begin
        with_env(stage_env) do
          yield staging
        end
      ensure
        @buildpath = nil
      end
    end
  end

  # The methods below define the formula DSL.
  class << self
    include BuildEnvironment::DSL
    include OnOS

    def method_added(method)
      super

      case method
      when :brew
        raise "You cannot override Formula#brew in class #{name}"
      when :test
        define_method(:test_defined?) { true }
      end
    end

    # The reason for why this software is not linked (by default) to
    # {::HOMEBREW_PREFIX}.
    # @private
    attr_reader :keg_only_reason

    # @!attribute [w] desc
    # A one-line description of the software. Used by users to get an overview
    # of the software and Homebrew maintainers.
    # Shows when running `brew info`.
    #
    # <pre>desc "Example formula"</pre>
    attr_rw :desc

    # @!attribute [w] license
    # The SPDX ID of the open-source license that the formula uses.
    # Shows when running `brew info`.
    # Use `:any_of`, `:all_of` or `:with` to describe complex license expressions.
    # `:any_of` should be used when the user can choose which license to use.
    # `:all_of` should be used when the user must use all licenses.
    # `:with` should be used to specify a valid SPDX exception.
    # Add `+` to an identifier to indicate that the formulae can be
    # licensed under later versions of the same license.
    # @see https://docs.brew.sh/License-Guidelines Homebrew License Guidelines
    # @see https://spdx.github.io/spdx-spec/appendix-IV-SPDX-license-expressions/ SPDX license expression guide
    # <pre>license "BSD-2-Clause"</pre>
    # <pre>license "EPL-1.0+"</pre>
    # <pre>license any_of: ["MIT", "GPL-2.0-only"]</pre>
    # <pre>license all_of: ["MIT", "GPL-2.0-only"]</pre>
    # <pre>license "GPL-2.0-only" => { with: "LLVM-exception" }</pre>
    # <pre>license :public_domain</pre>
    # <pre>license any_of: [
    #   "MIT",
    #   :public_domain,
    #   all_of: ["0BSD", "Zlib", "Artistic-1.0+"],
    #   "Apache-2.0" => { with: "LLVM-exception" },
    # ]</pre>
    def license(args = nil)
      if args.nil?
        @licenses
      else
        @licenses = args
      end
    end

    # @!attribute [w] homepage
    # The homepage for the software. Used by users to get more information
    # about the software and Homebrew maintainers as a point of contact for
    # e.g. submitting patches.
    # Can be opened with running `brew home`.
    #
    # <pre>homepage "https://www.example.com"</pre>
    attr_rw :homepage

    # Whether a livecheck specification is defined or not.
    # It returns true when a livecheck block is present in the {Formula} and
    # false otherwise, and is used by livecheck.
    def livecheckable?
      @livecheckable == true
    end

    # Whether a service specification is defined or not.
    # It returns true when a service block is present in the {Formula} and
    # false otherwise, and is used by service.
    def service?
      @service_block.present?
    end

    # The `:startup` attribute set by {.plist_options}.
    # @private
    attr_reader :plist_startup

    # The `:manual` attribute set by {.plist_options}.
    # @private
    attr_reader :plist_manual

    # If `pour_bottle?` returns `false` the user-visible reason to display for
    # why they cannot use the bottle.
    # @private
    attr_accessor :pour_bottle_check_unsatisfied_reason

    # @!attribute [w] revision
    # Used for creating new Homebrew versions of software without new upstream
    # versions. For example, if we bump the major version of a library that this
    # {Formula} {.depends_on} then we may need to update the `revision` of this
    # {Formula} to install a new version linked against the new library version.
    # `0` if unset.
    #
    # <pre>revision 1</pre>
    attr_rw :revision

    # @!attribute [w] version_scheme
    # Used for creating new Homebrew version schemes. For example, if we want
    # to change version scheme from one to another, then we may need to update
    # `version_scheme` of this {Formula} to be able to use new version scheme,
    # e.g. to move from 20151020 scheme to 1.0.0 we need to increment
    # `version_scheme`. Without this, the prior scheme will always equate to a
    # higher version.
    # `0` if unset.
    #
    # <pre>version_scheme 1</pre>
    attr_rw :version_scheme

    # A list of the {.stable} and {.head} {SoftwareSpec}s.
    # @private
    def specs
      @specs ||= [stable, head].freeze
    end

    # @!attribute [w] url
    # The URL used to download the source for the {.stable} version of the formula.
    # We prefer `https` for security and proxy reasons.
    # If not inferrable, specify the download strategy with `using: ...`.
    #
    # - `:git`, `:hg`, `:svn`, `:bzr`, `:fossil`, `:cvs`,
    # - `:curl` (normal file download, will also extract)
    # - `:nounzip` (without extracting)
    # - `:post` (download via an HTTP POST)
    #
    # <pre>url "https://packed.sources.and.we.prefer.https.example.com/archive-1.2.3.tar.bz2"</pre>
    # <pre>url "https://some.dont.provide.archives.example.com",
    #     using:    :git,
    #     tag:      "1.2.3",
    #     revision: "db8e4de5b2d6653f66aea53094624468caad15d2"</pre>
    def url(val, specs = {})
      stable.url(val, specs)
    end

    # @!attribute [w] version
    # The version string for the {.stable} version of the formula.
    # The version is autodetected from the URL and/or tag so only needs to be
    # declared if it cannot be autodetected correctly.
    #
    # <pre>version "1.2-final"</pre>
    def version(val = nil)
      stable.version(val)
    end

    # @!attribute [w] mirror
    # Additional URLs for the {.stable} version of the formula.
    # These are only used if the {.url} fails to download. It's optional and
    # there can be more than one. Generally we add them when the main {.url}
    # is unreliable. If {.url} is really unreliable then we may swap the
    # {.mirror} and {.url}.
    #
    # <pre>mirror "https://in.case.the.host.is.down.example.com"
    # mirror "https://in.case.the.mirror.is.down.example.com</pre>
    def mirror(val)
      stable.mirror(val)
    end

    # @!attribute [w] sha256
    # @scope class
    # To verify the cached download's integrity and security we verify the
    # SHA-256 hash matches what we've declared in the {Formula}. To quickly fill
    # this value you can leave it blank and run `brew fetch --force` and it'll
    # tell you the currently valid value.
    #
    # <pre>sha256 "2a2ba417eebaadcb4418ee7b12fe2998f26d6e6f7fda7983412ff66a741ab6f7"</pre>
    def sha256(val)
      stable.sha256(val)
    end

    # @!attribute [w] bottle
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
    # <pre>bottle do
    #   root_url "https://example.com" # Optional root to calculate bottle URLs.
    #   rebuild 1 # Marks the old bottle as outdated without bumping the version/revision of the formula.
    #   # Optionally specify the HOMEBREW_CELLAR in which the bottles were built.
    #   sha256 cellar: "/brew/Cellar", catalina:    "ef65c759c5097a36323fa9c77756468649e8d1980a3a4e05695c05e39568967c"
    #   sha256 cellar: :any,           mojave:      "28f4090610946a4eb207df102d841de23ced0d06ba31cb79e040d883906dcd4f"
    #   sha256                         high_sierra: "91dd0caca9bd3f38c439d5a7b6f68440c4274945615fae035ff0a369264b8a2f"
    # end</pre>
    #
    # Homebrew maintainers aim to bottle all formulae that require compilation.
    #
    # Formulae that can be installed without compilation should be tagged with:
    # <pre>bottle :unneeded</pre>
    #
    # Formulae which should not be bottled should be tagged with:
    # <pre>bottle :disable, "reasons"</pre>
    def bottle(*args, &block)
      stable.bottle(*args, &block)
    end

    # @private
    def build
      stable.build
    end

    # Get the `BUILD_FLAGS` from the formula's namespace set in `Formulary::load_formula`.
    # @private
    def build_flags
      namespace = T.must(to_s.split("::")[0..-2]).join("::")
      return [] if namespace.empty?

      mod = const_get(namespace)
      mod.const_get(:BUILD_FLAGS)
    end

    # @!attribute [w] stable
    # Allows adding {.depends_on} and {Patch}es just to the {.stable} {SoftwareSpec}.
    # This is required instead of using a conditional.
    # It is preferrable to also pull the {url} and {sha256= sha256} into the block if one is added.
    #
    # <pre>stable do
    #   url "https://example.com/foo-1.0.tar.gz"
    #   sha256 "2a2ba417eebaadcb4418ee7b12fe2998f26d6e6f7fda7983412ff66a741ab6f7"
    #
    #   depends_on "libxml2"
    #   depends_on "libffi"
    # end</pre>
    def stable(&block)
      @stable ||= SoftwareSpec.new(flags: build_flags)
      return @stable unless block

      @stable.instance_eval(&block)
    end

    # @!attribute [w] head
    # Adds a {.head} {SoftwareSpec}.
    # This can be installed by passing the `--HEAD` option to allow
    # installing software directly from a branch of a version-control repository.
    # If called as a method this provides just the {url} for the {SoftwareSpec}.
    # If a block is provided you can also add {.depends_on} and {Patch}es just to the {.head} {SoftwareSpec}.
    # The download strategies (e.g. `:using =>`) are the same as for {url}.
    # `master` is the default branch and doesn't need stating with a `branch:` parameter.
    # <pre>head "https://we.prefer.https.over.git.example.com/.git"</pre>
    # <pre>head "https://example.com/.git", branch: "name_of_branch"</pre>
    # or (if autodetect fails):
    # <pre>head "https://hg.is.awesome.but.git.has.won.example.com/", using: :hg</pre>
    def head(val = nil, specs = {}, &block)
      @head ||= HeadSoftwareSpec.new(flags: build_flags)
      if block
        @head.instance_eval(&block)
      elsif val
        @head.url(val, specs)
      else
        @head
      end
    end

    # Additional downloads can be defined as {resource}s and accessed in the
    # install method. Resources can also be defined inside a {.stable} or
    # {.head} block. This mechanism replaces ad-hoc "subformula" classes.
    # <pre>resource "additional_files" do
    #   url "https://example.com/additional-stuff.tar.gz"
    #   sha256 "c6bc3f48ce8e797854c4b865f6a8ff969867bbcaebd648ae6fd825683e59fef2"
    # end</pre>
    def resource(name, klass = Resource, &block)
      specs.each do |spec|
        spec.resource(name, klass, &block) unless spec.resource_defined?(name)
      end
    end

    def go_resource(name, &block)
      specs.each { |spec| spec.go_resource(name, &block) }
    end

    # The dependencies for this formula. Use strings for the names of other
    # formulae. Homebrew provides some `:special` {Requirement}s for stuff
    # that needs extra handling (often changing some ENV vars or
    # deciding whether to use the system provided version).
    #
    # `:build` means this dependency is only needed during build.
    # <pre>depends_on "cmake" => :build</pre>
    #
    # `:test` means this dependency is only needed during testing.
    # <pre>depends_on "node" => :test</pre>
    #
    # `:recommended` dependencies are built by default.
    # But a `--without-...` option is generated to opt-out.
    # <pre>depends_on "readline" => :recommended</pre>
    #
    # `:optional` dependencies are NOT built by default unless the
    # auto-generated `--with-...` option is passed.
    # <pre>depends_on "glib" => :optional</pre>
    #
    # If you need to specify that another formula has to be built with/out
    # certain options (note, no `--` needed before the option):
    # <pre>depends_on "zeromq" => "with-pgm"
    # depends_on "qt" => ["with-qtdbus", "developer"] # Multiple options.</pre>
    #
    # Optional and enforce that "boost" is built with `--with-c++11`.
    # <pre>depends_on "boost" => [:optional, "with-c++11"]</pre>
    #
    # If a dependency is only needed in certain cases:
    # <pre>depends_on "sqlite" if MacOS.version >= :catalina
    # depends_on xcode: :build # If the formula really needs full Xcode to compile.
    # depends_on macos: :mojave # Needs at least macOS Mojave (10.14) to run.
    # </pre>
    #
    # It is possible to only depend on something if
    # `build.with?` or `build.without? "another_formula"`:
    # <pre>depends_on "postgresql" if build.without? "sqlite"</pre>
    def depends_on(dep)
      specs.each { |spec| spec.depends_on(dep) }
    end

    # Indicates use of dependencies provided by macOS.
    # On macOS this is a no-op (as we use the provided system libraries).
    # On Linux this will act as {.depends_on}.
    def uses_from_macos(dep, bounds = {})
      specs.each { |spec| spec.uses_from_macos(dep, bounds) }
    end

    # @!attribute [w] option
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
    # <pre>option "with-spam", "The description goes here without a dot at the end"</pre>
    # <pre>option "with-qt", "Text here overwrites what's autogenerated by 'depends_on "qt" => :optional'"</pre>
    # <pre>option :universal</pre>
    def option(name, description = "")
      specs.each { |spec| spec.option(name, description) }
    end

    # @!attribute [w] deprecated_option
    # Deprecated options are used to rename options and migrate users who used
    # them to newer ones. They are mostly used for migrating non-`with` options
    # (e.g. `enable-debug`) to `with` options (e.g. `with-debug`).
    # <pre>deprecated_option "enable-debug" => "with-debug"</pre>
    def deprecated_option(hash)
      specs.each { |spec| spec.deprecated_option(hash) }
    end

    # External patches can be declared using resource-style blocks.
    # <pre>patch do
    #   url "https://example.com/example_patch.diff"
    #   sha256 "c6bc3f48ce8e797854c4b865f6a8ff969867bbcaebd648ae6fd825683e59fef2"
    # end</pre>
    #
    # A strip level of `-p1` is assumed. It can be overridden using a symbol
    # argument:
    # <pre>patch :p0 do
    #   url "https://example.com/example_patch.diff"
    #   sha256 "c6bc3f48ce8e797854c4b865f6a8ff969867bbcaebd648ae6fd825683e59fef2"
    # end</pre>
    #
    # Patches can be declared in stable and head blocks. This form is
    # preferred over using conditionals.
    # <pre>stable do
    #   patch do
    #     url "https://example.com/example_patch.diff"
    #     sha256 "c6bc3f48ce8e797854c4b865f6a8ff969867bbcaebd648ae6fd825683e59fef2"
    #   end
    # end</pre>
    #
    # Embedded (`__END__`) patches are declared like so:
    # <pre>patch :DATA
    # patch :p0, :DATA</pre>
    #
    # Patches can also be embedded by passing a string. This makes it possible
    # to provide multiple embedded patches while making only some of them
    # conditional.
    # <pre>patch :p0, "..."</pre>
    # @see https://docs.brew.sh/Formula-Cookbook#patches Patches
    def patch(strip = :p1, src = nil, &block)
      specs.each { |spec| spec.patch(strip, src, &block) }
    end

    # Defines launchd plist handling.
    #
    # Does your plist need to be loaded at startup?
    # <pre>plist_options startup: true</pre>
    #
    # Or only when necessary or desired by the user?
    # <pre>plist_options manual: "foo"</pre>
    #
    # Or perhaps you'd like to give the user a choice? Ooh fancy.
    # <pre>plist_options startup: true, manual: "foo start"</pre>
    def plist_options(options)
      @plist_startup = options[:startup]
      @plist_manual = options[:manual]
    end

    # @private
    def conflicts
      @conflicts ||= []
    end

    # One or more formulae that conflict with this one and why.
    # <pre>conflicts_with "imagemagick", because: "both install `convert` binaries"</pre>
    def conflicts_with(*names)
      opts = names.last.is_a?(Hash) ? names.pop : {}
      names.each { |name| conflicts << FormulaConflict.new(name, opts[:because]) }
    end

    # Skip cleaning paths in a formula.
    #
    # Sometimes the formula {Cleaner cleaner} breaks things.
    # Preserve cleaned paths with:
    # <pre>skip_clean "bin/foo", "lib/bar"</pre>
    # Keep .la files with:
    # <pre>skip_clean :la</pre>
    def skip_clean(*paths)
      paths.flatten!
      # Specifying :all is deprecated and will become an error
      skip_clean_paths.merge(paths)
    end

    # @private
    def skip_clean_paths
      @skip_clean_paths ||= Set.new
    end

    # Software that will not be symlinked into the `brew --prefix` and will
    # only live in its Cellar. Other formulae can depend on it and Homebrew
    # will add the necessary includes, libraries, and other paths while
    # building that other formula.
    #
    # Keg-only formulae are not in your PATH and are not seen by compilers
    # if you build your own software outside of Homebrew. This way, we
    # don't shadow software provided by macOS.
    # <pre>keg_only :provided_by_macos</pre>
    # <pre>keg_only :versioned_formulae</pre>
    # <pre>keg_only "because I want it so"</pre>
    def keg_only(reason, explanation = "")
      @keg_only_reason = KegOnlyReason.new(reason, explanation)
    end

    # Pass `:skip` to this method to disable post-install stdlib checking.
    def cxxstdlib_check(check_type)
      define_method(:skip_cxxstdlib_check?) { true } if check_type == :skip
    end

    # Marks the {Formula} as failing with a particular compiler so it will fall back to others.
    # For Apple compilers, this should be in the format:
    # <pre>fails_with :clang do
    #   build 600
    #   cause "multiple configure and compile errors"
    # end</pre>
    #
    # The block may be omitted, and if present the build may be omitted;
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
    # <pre>fails_with :gcc => '7' do
    #   version '7.1'
    # end</pre>
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
    # @see #fails_with
    def needs(*standards)
      specs.each { |spec| spec.needs(*standards) }
    end

    # A test is required for new formulae and makes us happy.
    # @return [Boolean]
    #
    # The block will create, run in and delete a temporary directory.
    #
    # We want tests that don't require any user input
    # and test the basic functionality of the application.
    # For example, `foo build-foo input.foo` is a good test
    # and `foo --version` or `foo --help` are bad tests.
    # However, a bad test is better than no test at all.
    #
    # @see https://docs.brew.sh/Formula-Cookbook#add-a-test-to-the-formula Tests
    #
    # <pre>(testpath/"test.file").write <<~EOS
    #   writing some test file, if you need to
    # EOS
    # assert_equal "OK", shell_output("test_command test.file").strip</pre>
    #
    # Need complete control over stdin, stdout?
    # <pre>require "open3"
    # Open3.popen3("#{bin}/example", "argument") do |stdin, stdout, _|
    #   stdin.write("some text")
    #   stdin.close
    #   assert_equal "result", stdout.read
    # end</pre>
    #
    # The test will fail if it returns false, or if an exception is raised.
    # Failed assertions and failed `system` commands will raise exceptions.
    def test(&block)
      define_method(:test, &block)
    end

    # @!attribute [w] livecheck
    # {Livecheck} can be used to check for newer versions of the software.
    # This method evaluates the DSL specified in the livecheck block of the
    # {Formula} (if it exists) and sets the instance variables of a {Livecheck}
    # object accordingly. This is used by `brew livecheck` to check for newer
    # versions of the software.
    #
    # <pre>livecheck do
    #   skip "Not maintained"
    #   url "https://example.com/foo/releases"
    #   regex /foo-(\d+(?:\.\d+)+)\.tar/
    # end</pre>
    def livecheck(&block)
      @livecheck ||= Livecheck.new(self)
      return @livecheck unless block

      @livecheckable = true
      @livecheck.instance_eval(&block)
    end

    # @!attribute [w] service
    # Service can be used to define services.
    # This method evaluates the DSL specified in the service block of the
    # {Formula} (if it exists) and sets the instance variables of a Service
    # object accordingly. This is used by `brew install` to generate a plist.
    #
    # <pre>service do
    #   run [opt_bin/"foo"]
    # end</pre>
    def service(&block)
      return @service_block unless block

      @service_block = block
    end

    # Defines whether the {Formula}'s bottle can be used on the given Homebrew
    # installation.
    #
    # For example, if the bottle requires the Xcode CLT to be installed a
    # {Formula} would declare:
    # <pre>pour_bottle? do
    #   reason "The bottle needs the Xcode CLT to be installed."
    #   satisfy { MacOS::CLT.installed? }
    # end</pre>
    #
    # If `satisfy` returns `false` then a bottle will not be used and instead
    # the {Formula} will be built from source and `reason` will be printed.
    #
    # Alternatively, a preset reason can be passed as a symbol:
    # <pre>pour_bottle? only_if: :clt_installed</pre>
    def pour_bottle?(only_if: nil, &block)
      @pour_bottle_check = PourBottleCheck.new(self)

      if only_if.present? && block.present?
        raise ArgumentError, "Do not pass both a preset condition and a block to `pour_bottle?`"
      end

      block ||= case only_if
      when :clt_installed
        lambda do |_|
          on_macos do
            T.cast(self, PourBottleCheck).reason(+<<~EOS)
              The bottle needs the Apple Command Line Tools to be installed.
                You can install them, if desired, with:
                  xcode-select --install
            EOS
            T.cast(self, PourBottleCheck).satisfy { MacOS::CLT.installed? }
          end
        end
      when :default_prefix
        lambda do |_|
          T.cast(self, PourBottleCheck).reason(+<<~EOS)
            The bottle needs to be installed into #{Homebrew::DEFAULT_PREFIX}.
          EOS
          T.cast(self, PourBottleCheck).satisfy { HOMEBREW_PREFIX.to_s == Homebrew::DEFAULT_PREFIX }
        end
      else
        raise ArgumentError, "Invalid preset `pour_bottle?` condition" if only_if.present?
      end

      @pour_bottle_check.instance_eval(&block)
    end

    # Deprecates a {Formula} (on the given date) so a warning is
    # shown on each installation. If the date has not yet passed the formula
    # will not be deprecated.
    # <pre>deprecate! date: "2020-08-27", because: :unmaintained</pre>
    # <pre>deprecate! date: "2020-08-27", because: "has been replaced by foo"</pre>
    # @see https://docs.brew.sh/Deprecating-Disabling-and-Removing-Formulae
    # @see DeprecateDisable::DEPRECATE_DISABLE_REASONS
    def deprecate!(date:, because:)
      @deprecation_date = Date.parse(date)
      return if @deprecation_date > Date.today

      @deprecation_reason = because
      @deprecated = true
    end

    # Whether this {Formula} is deprecated (i.e. warns on installation).
    # Defaults to false.
    # @return [Boolean]
    # @see .deprecate!
    def deprecated?
      @deprecated == true
    end

    # The date that this {Formula} was or becomes deprecated.
    # Returns `nil` if no date is specified.
    # @return Date
    # @see .deprecate!
    attr_reader :deprecation_date

    # The reason for deprecation of a {Formula}.
    # @return [nil] if no reason was provided or the formula is not deprecated.
    # @return [String, Symbol]
    # @see .deprecate!
    attr_reader :deprecation_reason

    # Disables a {Formula} (on the given date) so it cannot be
    # installed. If the date has not yet passed the formula
    # will be deprecated instead of disabled.
    # <pre>disable! date: "2020-08-27", because: :does_not_build</pre>
    # <pre>disable! date: "2020-08-27", because: "has been replaced by foo"</pre>
    # @see https://docs.brew.sh/Deprecating-Disabling-and-Removing-Formulae
    # @see DeprecateDisable::DEPRECATE_DISABLE_REASONS
    def disable!(date:, because:)
      @disable_date = Date.parse(date)

      if @disable_date > Date.today
        @deprecation_reason = because
        @deprecated = true
        return
      end

      @disable_reason = because
      @disabled = true
    end

    # Whether this {Formula} is disabled (i.e. cannot be installed).
    # Defaults to false.
    # @return [Boolean]
    # @see .disable!
    def disabled?
      @disabled == true
    end

    # The date that this {Formula} was or becomes disabled.
    # Returns `nil` if no date is specified.
    # @return Date
    # @see .disable!
    attr_reader :disable_date

    # The reason this {Formula} is disabled.
    # Returns `nil` if no reason was provided or the formula is not disabled.
    # @return [String, Symbol]
    # @see .disable!
    attr_reader :disable_reason

    # Permit overwriting certain files while linking.
    #
    # Sometimes we accidentally install files outside prefix. Once we fix that,
    # users will get a link conflict error. Overwrite those files with:
    # <pre>link_overwrite "bin/foo", "lib/bar"</pre>
    # <pre>link_overwrite "share/man/man1/baz-*"</pre>
    def link_overwrite(*paths)
      paths.flatten!
      link_overwrite_paths.merge(paths)
    end

    # @private
    def link_overwrite_paths
      @link_overwrite_paths ||= Set.new
    end

    # Permit links to certain libraries that don't exist. Available on Linux only.
    def ignore_missing_libraries(*)
      raise FormulaSpecificationError, "#{__method__} is available on Linux only"
    end

    # @private
    def allowed_missing_libraries
      @allowed_missing_libraries ||= Set.new
    end
  end
end

require "extend/os/formula"
