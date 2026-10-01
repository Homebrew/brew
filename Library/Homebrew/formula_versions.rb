# typed: strict
# frozen_string_literal: true

require "formula"
require "utils/output"

# Helper class for traversing a formula's previous versions.
#
# @api internal
class FormulaVersions
  include Context
  include Utils::Output::Mixin

  # Historical metadata is inspected, never downloaded using these obsolete checksums.
  module LegacyChecksums
    sig { params(_value: T.any(String, T::Hash[String, Symbol])).void }
    def sha1(_value); end

    sig { params(_value: T.any(String, T::Hash[String, Symbol])).void }
    def md5(_value); end
  end

  class LegacyResource < Resource
    include LegacyChecksums

    sig {
      override.params(strip: T.any(Symbol, String), src: T.nilable(T.any(Symbol, String)),
                      block: T.nilable(T.proc.bind(Resource::Patch).void))
              .returns(T::Array[T.any(EmbeddedPatch, ExternalPatch)])
    }
    def patch(strip = :p1, src = nil, &block)
      super(strip, src, &(FormulaVersions.legacy_patch_block(block) if block))
    end
  end

  module LegacySoftwareSpec
    extend T::Helpers
    include LegacyChecksums

    requires_ancestor { SoftwareSpec }

    sig {
      params(name: T.nilable(String), klass: T.class_of(Resource),
             block: T.nilable(T.proc.bind(Resource).void)).returns(T.nilable(Resource))
    }
    def resource(name = nil, klass = Resource, &block)
      super(name, (klass == Resource) ? LegacyResource : klass, &block)
    end

    sig {
      params(strip: T.any(Symbol, String), src: T.nilable(T.any(Symbol, String)),
             block: T.nilable(T.proc.bind(Resource::Patch).void)).void
    }
    def patch(strip = :p1, src = nil, &block)
      super(strip, src, &(FormulaVersions.legacy_patch_block(block) if block))
    end
  end

  # Extend each historical patch resource before evaluating its declarations.
  sig { params(block: T.proc.void).returns(T.proc.void) }
  def self.legacy_patch_block(block)
    proc do
      T.bind(self, Resource::Patch)
      extend LegacyChecksums

      instance_eval(&block)
    end
  end

  # Parses bottle syntax that was removed in February 2021 without exposing it
  # to normal formula loading.
  class LegacyBottleSpecification < BottleSpecification
    include LegacyChecksums

    sig { override.void }
    def initialize
      super
      @legacy_cellar = T.let(nil, T.nilable(T.any(Symbol, String)))
    end

    sig { override.params(hash: T::Hash[T.any(Symbol, String), T.any(String, Symbol)]).void }
    def sha256(hash)
      legacy = hash.find do |key, value|
        key.is_a?(String) && key.match?(/^[a-f0-9]{64}$/i) && value.is_a?(Symbol)
      end
      return super if legacy.nil?

      digest, tag = legacy
      converted = T.let({ tag => digest }, T::Hash[T.any(Symbol, String), T.any(String, Symbol)])
      cellar = hash[:cellar] || @legacy_cellar
      converted[:cellar] = cellar unless cellar.nil?
      super(converted)
    end

    sig { params(_value: String).void }
    def prefix(_value); end

    sig { params(_value: Integer).void }
    def revision(_value); end

    sig { params(value: T.any(Symbol, String)).returns(T.any(Symbol, String)) }
    def cellar(value)
      @legacy_cellar = value
    end
  end

  # Resolve historical macOS conditionals using the target, never the worker host.
  class LegacyMacOSVersion < Version
    RELEASES = T.let(MacOSVersion::RELEASES.merge(
      yosemite: "10.10", mavericks: "10.9", mountain_lion: "10.8", lion: "10.7",
      snow_leopard: "10.6", leopard: "10.5", tiger: "10.4"
    ).freeze, T::Hash[Symbol, String])

    sig { override.params(other: T.untyped).returns(T.nilable(Integer)) }
    def <=>(other)
      super(release_operand(other))
    end

    # `Version#==` answers `NULL` without calling `<=>`, so validate here too.
    sig { override.params(other: T.anything).returns(T::Boolean) }
    def ==(other)
      super(release_operand(other))
    end
    alias eql? ==

    sig { returns(Symbol) }
    def to_sym
      RELEASES.key(to_s) || raise(FormulaSpecificationError, "Historical Linux MacOS.version has no release name")
    end

    # Linux answered historical macOS queries as older than every release
    # from February 2018 until September 2024.
    NULL = T.let(new("NULL").tap { |v| v.instance_variable_set(:@version, nil) }.freeze, LegacyMacOSVersion)

    private

    sig { params(other: T.anything).returns(T.anything) }
    def release_operand(other)
      case other
      when Symbol
        RELEASES.fetch(other) do
          raise FormulaSpecificationError, "Unknown historical macOS release: #{other.inspect}"
        end
      when Float
        raise FormulaSpecificationError, "Unsupported historical macOS version comparison: #{other.inspect}"
      else
        other
      end
    end
  end

  # Historical Linux answers for `MacOS::Xcode` and `MacOS::CLT`.
  module LegacyLinuxDeveloperTools
    sig { returns(Version) }
    def self.version = Version::NULL

    sig { returns(T::Boolean) }
    def self.installed? = false
  end

  # Advisory history walks answer `MacOS` from the simulated target, even when
  # it matches the host, and hold host-only queries. Other callers keep the
  # host `MacOS` API.
  module LegacyMacOS
    LINUX_ANSWERS = T.let({
      full_version:       LegacyMacOSVersion::NULL,
      sdk_root_needed?:   false,
      sdk_path_if_needed: nil,
      sdk_path:           nil,
    }.freeze, T::Hash[Symbol, T.nilable(T.any(LegacyMacOSVersion, T::Boolean))])

    @simulated_target = T.let(false, T::Boolean)

    class << self
      sig { returns(T::Boolean) }
      attr_accessor :simulated_target

      sig { returns(T.any(LegacyMacOSVersion, MacOSVersion)) }
      def version
        simulated_target ? target_version : ::MacOS.version
      end

      sig { returns(LegacyMacOSVersion) }
      def target_version
        target = Homebrew::SimulateSystem.current_os
        return LegacyMacOSVersion::NULL if target == :linux

        LegacyMacOSVersion.new(LegacyMacOSVersion::RELEASES.fetch(target) do
          raise FormulaSpecificationError, "historical MacOS.version requires a concrete macOS target"
        end)
      end

      sig {
        params(name: Symbol, args: T.anything, kwargs: T.anything, block: T.nilable(Proc)).returns(T.anything)
      }
      def method_missing(name, *args, **kwargs, &block)
        return ::MacOS.public_send(name, *args, **kwargs, &block) unless simulated_target
        if Homebrew::SimulateSystem.current_os == :linux && LINUX_ANSWERS.key?(name)
          return LINUX_ANSWERS.fetch(name)
        end

        raise FormulaSpecificationError, "historical MacOS.#{name} has no simulated target answer"
      end

      sig { params(name: Symbol, include_private: T::Boolean).returns(T::Boolean) }
      def respond_to_missing?(name, include_private = false)
        return ::MacOS.respond_to?(name, include_private) unless simulated_target

        Homebrew::SimulateSystem.current_os == :linux && LINUX_ANSWERS.key?(name)
      end

      sig { params(name: Symbol).returns(T.anything) }
      def const_missing(name)
        # Host callers keep constants such as `MacOS::CLT::PKG_PATH`.
        # rubocop:disable Sorbet/ConstantsFromStrings
        return ::MacOS.const_get(name, false) unless simulated_target
        # rubocop:enable Sorbet/ConstantsFromStrings
        if Homebrew::SimulateSystem.current_os == :linux && [:Xcode, :CLT].include?(name)
          return LegacyLinuxDeveloperTools
        end

        raise FormulaSpecificationError, "historical MacOS::#{name} has no simulated target answer"
      end
    end
  end

  @legacy_formula_class = T.let(nil, T.nilable(T.class_of(Formula)))

  sig { returns(T.class_of(Formula)) }
  def self.legacy_formula_class
    @legacy_formula_class ||= Class.new(Formula) do
      extend LegacyChecksums

      const_set(:MacOS, LegacyMacOS)
      const_set(:StrictSubversionDownloadStrategy, SubversionDownloadStrategy)

      class << self
        define_method(:on_system) do |linux, macos:, &block|
          T.bind(self, T.class_of(Formula))
          # `Ignorable` resumes after the modern `ArgumentError`s, so reject
          # invalid historical arguments before delegating.
          raise FormulaSpecificationError, "The first argument to `on_system` must be `:linux`" if linux != :linux

          version, condition = macos.to_s.split(/_(?=or_)/).map(&:to_sym)
          if condition && [:or_older, :or_newer].exclude?(condition)
            raise FormulaSpecificationError, "Invalid OS condition: #{condition.inspect}"
          end
          unless LegacyMacOSVersion::RELEASES.key?(version)
            raise FormulaSpecificationError, "Unknown historical macOS release: #{version.inspect}"
          end
          next super(linux, macos:, &block) if MacOSVersion::SYMBOLS.key?(version)

          if Homebrew::SimulateSystem.current_os == :linux
            on_linux(&block)
          else
            on_macos do
              target = LegacyMacOS.target_version
              matches = case condition
              when :or_older then target <= version
              when :or_newer then target >= version
              else target == version
              end
              block.call if matches
            end
          end
        end
        define_method(:build) do
          options = super()
          options.singleton_class.class_eval { public :include? }
          options
        end
        # From April 2020 to June 2021 `date:` and `because:` were optional and
        # an undated call took effect immediately.
        define_method(:deprecate!) do |date: nil, because: nil, **options|
          next super(date:, because:, **options) if date

          raise FormulaSpecificationError, "Undated `deprecate!` cannot name a replacement" if options.present?

          instance_variable_set(:@deprecation_reason, because)
          instance_variable_set(:@deprecated, true)
        end
        define_method(:disable!) do |date: nil, because: nil, **options|
          next super(date:, because:, **options) if date

          raise FormulaSpecificationError, "Undated `disable!` cannot name a replacement" if options.present?

          instance_variable_set(:@disable_reason, because)
          instance_variable_set(:@disabled, true)
        end
        define_method(:cxxstdlib_check) { |_value| nil }
        define_method(:devel) { nil }
        define_method(:plist_options) { |**_options| nil }
        # Historical option checks must fail the load, not exit the consumer.
        define_method(:odie) { |error| raise FormulaSpecificationError, error.to_s }
        define_method(:bottle) do |*args, &block|
          next if args == [:unneeded] && block.nil?

          super(*args, &block)
        end

        define_method(:inherited) do |child|
          super(child)
          [child.stable, child.head].compact.each do |spec|
            spec.extend(LegacySoftwareSpec)
            spec.instance_variable_set(:@bottle_specification, LegacyBottleSpecification.new)
          end
        end
      end
    end
  end

  IGNORED_EXCEPTIONS = [
    ArgumentError, NameError, SyntaxError, TypeError, LegacyDSLError,
    FormulaSpecificationError, FormulaValidationError,
    ErrorDuringExecution, LoadError, MethodDeprecatedError
  ].freeze

  # With `simulated_target`, historical `MacOS` queries answer only from
  # {Homebrew::SimulateSystem}'s target.
  sig { params(formula: Formula, simulated_target: T::Boolean).void }
  def initialize(formula, simulated_target: false)
    @simulated_target = simulated_target
    @name = T.let(formula.name, String)
    @path = T.let(formula.tap_path, Pathname)
    @repository = T.let(formula.tap!.path, Pathname)
    @relative_path = T.let(@path.relative_path_from(repository).to_s, String)
    # Also look at e.g. older homebrew-core paths before sharding.
    if (match = @relative_path.match(%r{^(HomebrewFormula|Formula)/(?:[a-z]|lib)/(.+)}))
      @old_relative_path = T.let("#{match[1]}/#{match[2]}", T.nilable(String))
    end
    @formula_at_revision = T.let({}, T::Hash[String, Formula])
    @load_error = T.let(nil, T.nilable(Exception))
  end

  # The original error from the most recent failed historical load.
  sig { returns(T.nilable(Exception)) }
  attr_reader :load_error

  # Full history includes earlier lifetimes of a deleted and re-added path.
  # Vulns::History skips proven absent paths, which are not formula builds.
  sig {
    params(branch: String, all_history: T::Boolean, _block: T.proc.params(revision: String, path: String).void).void
  }
  def rev_list(branch, all_history: false, &_block)
    repository.cd do
      rev_list_cmd = ["git", "rev-list", "--abbrev-commit"]
      rev_list_cmd << "--remove-empty" unless all_history
      [relative_path, old_relative_path].compact.each do |entry|
        Utils.popen_read(*rev_list_cmd, branch, "--", entry, safe: all_history)
             .each_line(chomp: true) { |revision| yield revision, entry }
      end
    end
  end

  sig {
    type_parameters(:U)
      .params(
        revision:              String,
        formula_relative_path: String,
        _block:                T.proc.params(arg0: Formula).returns(T.type_parameter(:U)),
      ).returns(T.nilable(T.type_parameter(:U)))
  }
  def formula_at_revision(revision, formula_relative_path = relative_path, &_block)
    @load_error = nil
    Homebrew.raise_deprecation_exceptions = true
    LegacyMacOS.simulated_target = @simulated_target

    # rev_list visits the current path first. At a sharding rename, the old
    # path is absent in the same commit; reuse the already-loaded new path.
    formula = @formula_at_revision[revision] || begin
      nostdout do
        Formulary.from_contents(
          name,
          path,
          file_contents_at_revision(revision, formula_relative_path)
            .sub(/\A(?:(?:[ \t]*#[^\n]*\n|[ \t]*\n)|(?:=begin[^\n]*(?:\n|\z).*?^=end[^\n]*(?:\n|\z)))*/m) do |header|
              "#{header}Formula = ScriptFileFormula = ::FormulaVersions.legacy_formula_class;"
            end,
          ignore_errors: true,
        )
      end
    rescue FormulaUnavailableError => e
      @load_error = e.cause || e
      nil
    rescue Homebrew::UntrustedTapError, MacOSVersion::Error
      raise
    rescue StandardError, ScriptError => e
      @load_error = e
      raise if Homebrew::EnvConfig.disable_load_formula?

      require "utils/backtrace"

      # We rescue these so that we can skip bad versions and
      # continue walking the history
      odebug "#{e} in #{name} at revision #{revision}", Utils::Backtrace.clean(e)
      nil
    end

    return if formula.nil?

    @formula_at_revision[revision] = formula
    yield formula
  ensure
    Homebrew.raise_deprecation_exceptions = false
    LegacyMacOS.simulated_target = false
  end

  # Only a successful tree lookup proves absence; a failed Git command must
  # not turn unreadable history into a skipped revision.
  sig { params(revision: String, relative_path: String).returns(T::Boolean) }
  def path_absent_at_revision?(revision, relative_path)
    repository.cd do
      Utils.popen_read("git", "ls-tree", "--full-tree", "--name-only", "-z",
                       revision, "--", relative_path, safe: true).empty?
    end
  end

  private

  sig { returns(String) }
  attr_reader :name, :relative_path

  sig { returns(T.nilable(String)) }
  attr_reader :old_relative_path

  sig { returns(Pathname) }
  attr_reader :path, :repository

  sig { params(revision: String, relative_path: String).returns(String) }
  def file_contents_at_revision(revision, relative_path)
    repository.cd { Utils.popen_read("git", "cat-file", "blob", "#{revision}:#{relative_path}") }
  end

  sig {
    type_parameters(:U)
      .params(block: T.proc.returns(T.type_parameter(:U)))
      .returns(T.type_parameter(:U))
  }
  def nostdout(&block)
    if verbose?
      yield
    else
      Utils::Output.redirect_stdout(File::NULL, &block)
    end
  end
end
