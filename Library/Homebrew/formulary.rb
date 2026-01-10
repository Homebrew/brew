# typed: strict
# frozen_string_literal: true

require "digest/sha2"
require "cachable"
require "tab"
require "utils"
require "utils/bottles"
require "utils/output"
require "utils/path"
require "service"
require "utils/curl"
require "deprecate_disable"
require "extend/hash/deep_transform_values"
require "extend/hash/keys"
require "tap"

# The {Formulary} is responsible for creating instances of {Formula}.
# It is not meant to be used directly from formulae.
module Formulary
  extend Context
  extend Cachable
  extend Utils::Output::Mixin
  include Utils::Output::Mixin

  ALLOWED_URL_SCHEMES = %w[file].freeze
  private_constant :ALLOWED_URL_SCHEMES

  # Enable the factory cache.
  #
  # @api internal
  sig { void }
  def self.enable_factory_cache!
    @factory_cache_enabled = T.let(true, T.nilable(TrueClass))
    cache[platform_cache_tag] ||= {}
    cache[platform_cache_tag][:formulary_factory] ||= {}
  end

  sig { returns(T::Boolean) }
  def self.factory_cached?
    !!@factory_cache_enabled
  end

  sig { returns(String) }
  def self.platform_cache_tag
    "#{Homebrew::SimulateSystem.current_os}_#{Homebrew::SimulateSystem.current_arch}"
  end
  private_class_method :platform_cache_tag

  sig {
    returns({
      api:               T.nilable(T::Hash[String, T.class_of(Formula)]),
      # TODO: the hash values should be Formula instances, but the linux tests were failing
      formulary_factory: T.nilable(T::Hash[String, T.untyped]),
      path:              T.nilable(T::Hash[String, T.class_of(Formula)]),
      stub:              T.nilable(T::Hash[String, T.class_of(Formula)]),
    })
  }
  def self.platform_cache
    cache[platform_cache_tag] ||= {}
  end

  sig { returns(T::Hash[String, Formula]) }
  def self.factory_cache
    cache[platform_cache_tag] ||= {}
    cache[platform_cache_tag][:formulary_factory] ||= {}
  end

  sig { params(path: T.any(String, Pathname)).returns(T::Boolean) }
  def self.formula_class_defined_from_path?(path)
    platform_cache.key?(:path) && platform_cache.fetch(:path).key?(path.to_s)
  end

  sig { params(name: String).returns(T::Boolean) }
  def self.formula_class_defined_from_api?(name)
    platform_cache.key?(:api) && platform_cache.fetch(:api).key?(name)
  end

  sig { params(name: String).returns(T::Boolean) }
  def self.formula_class_defined_from_stub?(name)
    platform_cache.key?(:stub) && platform_cache.fetch(:stub).key?(name)
  end

  sig { params(path: T.any(String, Pathname)).returns(T.class_of(Formula)) }
  def self.formula_class_get_from_path(path)
    platform_cache.fetch(:path).fetch(path.to_s)
  end

  sig { params(name: String).returns(T.class_of(Formula)) }
  def self.formula_class_get_from_api(name)
    platform_cache.fetch(:api).fetch(name)
  end

  sig { params(name: String).returns(T.class_of(Formula)) }
  def self.formula_class_get_from_stub(name)
    platform_cache.fetch(:stub).fetch(name)
  end

  sig { void }
  def self.clear_cache
    platform_cache.each do |type, cached_objects|
      next if type == :formulary_factory

      cached_objects.each_value do |klass|
        class_name = klass.name

        # Already removed from namespace.
        next if class_name.nil?

        namespace = Utils.deconstantize(class_name)
        next if Utils.deconstantize(namespace) != name

        remove_const(Utils.demodulize(namespace).to_sym)
      end
    end

    super
  end

  sig {
    params(
      name:          String,
      path:          Pathname,
      contents:      String,
      namespace:     String,
      flags:         T::Array[String],
      ignore_errors: T::Boolean,
    ).returns(T.class_of(Formula))
  }
  def self.load_formula(name, path, contents, namespace, flags:, ignore_errors:)
    raise "Formula loading disabled by `$HOMEBREW_DISABLE_LOAD_FORMULA`!" if Homebrew::EnvConfig.disable_load_formula?

    require "formula"
    require "ignorable"
    require "stringio"

    # Capture stdout to prevent formulae from printing to stdout unexpectedly.
    old_stdout = $stdout
    $stdout = StringIO.new

    mod = Module.new
    namespace = namespace.to_sym
    remove_const(namespace) if const_defined?(namespace)
    const_set(namespace, mod)

    eval_formula = lambda do
      # Set `BUILD_FLAGS` in the formula's namespace so we can
      # access them from within the formula's class scope.
      mod.const_set(:BUILD_FLAGS, flags)
      mod.module_eval(contents, path.to_s)
    rescue NameError, ArgumentError, ScriptError, MethodDeprecatedError, MacOSVersion::Error => e
      if e.is_a?(Ignorable::ExceptionMixin)
        e.ignore
      else
        remove_const(namespace)
        raise FormulaUnreadableError.new(name, e)
      end
    end
    if ignore_errors
      Ignorable.hook_raise(&eval_formula)
    else
      eval_formula.call
    end

    class_name = class_s(name)

    begin
      mod.const_get(class_name)
    rescue NameError => e
      class_list = mod.constants
                      .map { |const_name| mod.const_get(const_name) }
                      .grep(Class)
      new_exception = FormulaClassUnavailableError.new(name, path, class_name, class_list)
      remove_const(namespace)
      raise new_exception, "", e.backtrace
    end
  ensure
    # TODO: Make printing to stdout an error so that we can print a tap name.
    #       See discussion at https://github.com/Homebrew/brew/pull/20226#discussion_r2195886888
    if (printed_to_stdout = $stdout.string.strip.presence)
      opoo <<~WARNING
        Formula #{name} attempted to print the following while being loaded:
        #{printed_to_stdout}
      WARNING
    end
    $stdout = old_stdout
  end

  sig { params(identifier: String).returns(String) }
  def self.namespace_key(identifier)
    Digest::SHA2.hexdigest(
      "#{Homebrew::SimulateSystem.current_os}_#{Homebrew::SimulateSystem.current_arch}:#{identifier}",
    )
  end

  sig { params(string: String).returns(String) }
  def self.replace_placeholders(string)
    string.gsub(HOMEBREW_PREFIX_PLACEHOLDER, HOMEBREW_PREFIX)
          .gsub(HOMEBREW_CELLAR_PLACEHOLDER, HOMEBREW_CELLAR)
          .gsub(HOMEBREW_HOME_PLACEHOLDER, Dir.home)
  end

  sig {
    params(name: String, path: Pathname, flags: T::Array[String], ignore_errors: T::Boolean)
      .returns(T.class_of(Formula))
  }
  def self.load_formula_from_path(name, path, flags:, ignore_errors:)
    contents = path.open("r") { |f| ensure_utf8_encoding(f).read }
    namespace = "FormulaNamespace#{namespace_key(path.to_s)}"
    klass = load_formula(name, path, contents, namespace, flags:, ignore_errors:)
    platform_cache[:path] ||= {}
    platform_cache.fetch(:path)[path.to_s] = klass
  end

  sig { params(name: String, json_formula_with_variations: T::Hash[String, T.untyped], flags: T::Array[String]).returns(T.class_of(Formula)) }
  def self.load_formula_from_json!(name, json_formula_with_variations, flags:)
    namespace = :"FormulaNamespaceAPI#{namespace_key(json_formula_with_variations.to_json)}"

    mod = Module.new
    remove_const(namespace) if const_defined?(namespace)
    const_set(namespace, mod)

    mod.const_set(:BUILD_FLAGS, flags)

    class_name = class_s(name)
    formula_struct = Homebrew::API::Formula.generate_formula_struct_hash(json_formula_with_variations)

    klass = Class.new(::Formula) do
      @loaded_from_api = T.let(true, T.nilable(T::Boolean))
      @api_source = T.let(json_formula_with_variations, T.nilable(T::Hash[String, T.untyped]))

      desc formula_struct.desc
      homepage formula_struct.homepage
      license formula_struct.license
      revision formula_struct.revision
      version_scheme formula_struct.version_scheme

      if formula_struct.stable?
        stable do
          url(*formula_struct.stable_url_args)
          version formula_struct.stable_version
          if (checksum = formula_struct.stable_checksum)
            sha256 checksum
          end

          formula_struct.stable_dependencies.each do |dep|
            depends_on dep
          end

          formula_struct.stable_uses_from_macos.each do |args|
            uses_from_macos(*args)
          end
        end
      end

      if formula_struct.head?
        head do
          url(*formula_struct.head_url_args)

          formula_struct.head_dependencies.each do |dep|
            depends_on dep
          end

          formula_struct.head_uses_from_macos.each do |args|
            uses_from_macos(*args)
          end
        end
      end

      no_autobump!(**formula_struct.no_autobump_args) if formula_struct.no_autobump_message?

      if formula_struct.bottle?
        bottle do
          if Homebrew::EnvConfig.bottle_domain == HOMEBREW_BOTTLE_DEFAULT_DOMAIN
            root_url HOMEBREW_BOTTLE_DEFAULT_DOMAIN
          else
            root_url Homebrew::EnvConfig.bottle_domain
          end
          rebuild formula_struct.bottle_rebuild
          formula_struct.bottle_checksums.each do |args|
            sha256(**args)
          end
        end
      end

      pour_bottle?(**formula_struct.pour_bottle_args) if formula_struct.pour_bottle?

      keg_only(*formula_struct.keg_only_args) if formula_struct.keg_only?

      deprecate!(**formula_struct.deprecate_args) if formula_struct.deprecate?
      disable!(**formula_struct.disable_args) if formula_struct.disable?

      formula_struct.conflicts.each do |name, args|
        conflicts_with(name, **args)
      end

      formula_struct.link_overwrite_paths.each do |path|
        link_overwrite path
      end

      define_method(:install) do
        raise NotImplementedError, "Cannot build from source from abstract formula."
      end

      @post_install_defined_boolean = T.let(formula_struct.post_install_defined, T.nilable(T::Boolean))
      define_method(:post_install_defined?) do
        self.class.instance_variable_get(:@post_install_defined_boolean)
      end

      if formula_struct.service?
        service do
          run(*formula_struct.service_run_args, **formula_struct.service_run_kwargs) if formula_struct.service_run?
          name(**formula_struct.service_name_args) if formula_struct.service_name?

          formula_struct.service_args.each do |key, arg|
            public_send(key, arg)
          end
        end
      end

      @caveats_string = T.let(formula_struct.caveats, T.nilable(String))
      define_method(:caveats) do
        self.class.instance_variable_get(:@caveats_string)
      end

      @tap_git_head_string = T.let(formula_struct.tap_git_head, T.nilable(String))
      define_method(:tap_git_head) do
        self.class.instance_variable_get(:@tap_git_head_string)
      end

      @oldnames_array = T.let(formula_struct.oldnames, T.nilable(T::Array[String]))
      define_method(:oldnames) do
        self.class.instance_variable_get(:@oldnames_array)
      end

      @aliases_array = T.let(formula_struct.aliases, T.nilable(T::Array[String]))
      define_method(:aliases) do
        self.class.instance_variable_get(:@aliases_array)
      end

      @versioned_formulae_array = T.let(formula_struct.versioned_formulae, T.nilable(T::Array[String]))
      define_method(:versioned_formulae_names) do
        self.class.instance_variable_get(:@versioned_formulae_array)
      end

      @ruby_source_path_string = T.let(formula_struct.ruby_source_path, T.nilable(String))
      define_method(:ruby_source_path) do
        self.class.instance_variable_get(:@ruby_source_path_string)
      end

      @ruby_source_checksum_string = T.let(formula_struct.ruby_source_checksum, T.nilable(String))
      define_method(:ruby_source_checksum) do
        checksum = self.class.instance_variable_get(:@ruby_source_checksum_string)
        Checksum.new(checksum) if checksum
      end
    end

    mod.const_set(class_name, klass)

    platform_cache[:api] ||= {}
    platform_cache.fetch(:api)[name] = klass
  end

  sig { params(name: String, formula_stub: Homebrew::FormulaStub, flags: T::Array[String]).returns(T.class_of(Formula)) }
  def self.load_formula_from_stub!(name, formula_stub, flags:)
    namespace = :"FormulaNamespaceStub#{namespace_key(formula_stub.to_json)}"

    mod = Module.new
    remove_const(namespace) if const_defined?(namespace)
    const_set(namespace, mod)

    mod.const_set(:BUILD_FLAGS, flags)

    class_name = class_s(name)

    klass = Class.new(::Formula) do
      @loaded_from_api = T.let(true, T.nilable(T::Boolean))
      @loaded_from_stub = T.let(true, T.nilable(T::Boolean))

      url "formula-stub://#{name}/#{formula_stub.pkg_version}"
      version formula_stub.version.to_s
      revision formula_stub.revision

      bottle do
        if Homebrew::EnvConfig.bottle_domain == HOMEBREW_BOTTLE_DEFAULT_DOMAIN
          root_url HOMEBREW_BOTTLE_DEFAULT_DOMAIN
        else
          root_url Homebrew::EnvConfig.bottle_domain
        end
        rebuild formula_stub.rebuild
        sha256 Utils::Bottles.tag.to_sym => formula_stub.sha256
      end

      define_method :install do
        raise NotImplementedError, "Cannot build from source from abstract stubbed formula."
      end

      @aliases_array = formula_stub.aliases
      define_method(:aliases) do
        self.class.instance_variable_get(:@aliases_array)
      end

      @oldnames_array = formula_stub.oldnames
      define_method(:oldnames) do
        self.class.instance_variable_get(:@oldnames_array)
      end
    end

    mod.const_set(class_name, klass)

    platform_cache[:stub] ||= {}
    platform_cache.fetch(:stub)[name] = klass
  end

  sig {
    params(name: String, spec: T.nilable(Symbol), force_bottle: T::Boolean, flags: T::Array[String], prefer_stub: T::Boolean).returns(Formula)
  }
  def self.resolve(
    name,
    spec: nil,
    force_bottle: false,
    flags: [],
    prefer_stub: false
  )
    if name.include?("/") || File.exist?(name)
      f = factory(name, *spec, force_bottle:, flags:, prefer_stub:)
      if f.any_version_installed?
        tab = Tab.for_formula(f)
        resolved_spec = spec || tab.spec
        f.active_spec = resolved_spec if f.send(resolved_spec)
        f.build = tab
        if f.head? && tab.tabfile
          k = Keg.new(tab.tabfile.parent)
          f.version.update_commit(k.version.version.commit) if k.version.head?
        end
      end
    else
      rack = to_rack(name)
      alias_path = factory_stub(name, force_bottle:, flags:).alias_path
      f = from_rack(rack, *spec, alias_path:, force_bottle:, flags:)
    end

    # If this formula was installed with an alias that has since changed,
    # then it was specified explicitly in ARGV. (Using the alias would
    # instead have found the new formula.)
    #
    # Because of this, the user is referring to this specific formula,
    # not any formula targeted by the same alias, so in this context
    # the formula shouldn't be considered outdated if the alias used to
    # install it has changed.
    f.follow_installed_alias = false

    f
  end

  sig { params(io: IO).returns(IO) }
  def self.ensure_utf8_encoding(io)
    io.set_encoding(Encoding::UTF_8)
  end

  sig { params(name: String).returns(String) }
  def self.class_s(name)
    class_name = name.capitalize
    class_name.gsub!(/[-_.\s]([a-zA-Z0-9])/) { T.must(Regexp.last_match(1)).upcase }
    class_name.tr!("+", "x")
    class_name.sub!(/(.)@(\d)/, "\\1AT\\2")
    class_name
  end

  # A {FormulaLoader} returns instances of formulae.
  # Subclasses implement loaders for particular sources of formulae.
  class FormulaLoader
    include Context
    include Utils::Output::Mixin

    # The formula's name.
    sig { returns(String) }
    attr_reader :name

    # The formula file's path.
    sig { returns(Pathname) }
    attr_reader :path

    # The name used to install the formula.
    sig { returns(T.nilable(T.any(Pathname, String))) }
    attr_reader :alias_path

    # The formula's tap (`nil` if it should be implicitly determined).
    sig { returns(T.nilable(Tap)) }
    attr_reader :tap

    sig {
      params(name: String, path: Pathname, alias_path: T.nilable(T.any(Pathname, String)), tap: T.nilable(Tap)).void
    }
    def initialize(name, path, alias_path: nil, tap: nil)
      @name = name
      @path = path
      @alias_path = alias_path
      @tap = tap
    end

    # Gets the formula instance.
    # `alias_path` can be overridden here in case an alias was used to refer to
    # a formula that was loaded in another way.
    sig {
      overridable.params(
        spec:          Symbol,
        alias_path:    T.nilable(T.any(Pathname, String)),
        force_bottle:  T::Boolean,
        flags:         T::Array[String],
        ignore_errors: T::Boolean,
      ).returns(Formula)
    }
    def get_formula(spec, alias_path: nil, force_bottle: false, flags: [], ignore_errors: false)
      alias_path ||= self.alias_path
      alias_path = Pathname(alias_path) if alias_path.is_a?(String)
      klass(flags:, ignore_errors:)
        .new(name, path, spec, alias_path:, tap:, force_bottle:)
    end

    sig { overridable.params(flags: T::Array[String], ignore_errors: T::Boolean).returns(T.class_of(Formula)) }
    def klass(flags:, ignore_errors:)
      load_file(flags:, ignore_errors:) unless Formulary.formula_class_defined_from_path?(path)
      Formulary.formula_class_get_from_path(path)
    end

    private

    sig { overridable.params(flags: T::Array[String], ignore_errors: T::Boolean).void }
    def load_file(flags:, ignore_errors:)
      raise FormulaUnavailableError, name unless path.file?

      Formulary.load_formula_from_path(name, path, flags:, ignore_errors:)
    end
  end

  # Loads a formula from a bottle.
  class FromBottleLoader < FormulaLoader
    include Utils::Output::Mixin

    sig {
      params(ref: T.any(String, Pathname, URI::Generic), from: T.nilable(Symbol), warn: T::Boolean)
        .returns(T.nilable(T.attached_class))
    }
    def self.try_new(ref, from: nil, warn: false)
      return if Homebrew::EnvConfig.forbid_packages_from_paths?

      ref = ref.to_s

      new(ref) if HOMEBREW_BOTTLES_EXTNAME_REGEX.match?(ref) && File.exist?(ref)
    end

    sig { params(bottle_name: String, warn: T::Boolean).void }
    def initialize(bottle_name, warn: false)
      @bottle_path = T.let(Pathname(bottle_name).realpath, Pathname)
      name, full_name = Utils::Bottles.resolve_formula_names(@bottle_path)
      super name, Formulary.path(full_name)
    end

    sig {
      override.params(
        spec:          Symbol,
        alias_path:    T.nilable(T.any(Pathname, String)),
        force_bottle:  T::Boolean,
        flags:         T::Array[String],
        ignore_errors: T::Boolean,
      ).returns(Formula)
    }
    def get_formula(spec, alias_path: nil, force_bottle: false, flags: [], ignore_errors: false)
      formula = begin
        contents = Utils::Bottles.formula_contents(@bottle_path, name:)
        Formulary.from_contents(name, path, contents, spec, force_bottle:,
                                flags:, ignore_errors:)
      rescue FormulaUnreadableError => e
        opoo <<~EOS
          Unreadable formula in #{@bottle_path}:
          #{e}
        EOS
        super
      rescue BottleFormulaUnavailableError => e
        opoo <<~EOS
          #{e}
          Falling back to non-bottle formula.
        EOS
        super
      end
      formula.local_bottle_path = @bottle_path
      formula
    end
  end

  # Loads formulae from disk using a path.
  class FromPathLoader < FormulaLoader
    sig {
      params(ref: T.any(String, Pathname, URI::Generic), from: T.nilable(Symbol), warn: T::Boolean)
        .returns(T.nilable(T.attached_class))
    }
    def self.try_new(ref, from: nil, warn: false)
      path = case ref
      when String
        Pathname(ref)
      when Pathname
        ref
      else
        return
      end

      return unless path.expand_path.exist?
      return unless ::Utils::Path.loadable_package_path?(path, :formula)

      if Homebrew::EnvConfig.use_internal_api?
        # If the path is for an installed keg, use FromKegLoader instead
        begin
          keg = Keg.for(path)
          loader = FromKegLoader.try_new(keg.name, from:, warn:)
          return T.cast(loader, T.attached_class)
        rescue NotAKegError
          # Not a keg path, continue
        end
      end

      if (tap = Tap.from_path(path))
        # Only treat symlinks in taps as aliases.
        if path.symlink?
          alias_path = path
          path = alias_path.resolved_path
        end
      else
        # Don't treat cache symlinks as aliases.
        tap = Homebrew::API.tap_from_source_download(path)
      end

      return if path.extname != ".rb"

      new(path, alias_path:, tap:)
    end

    sig { params(path: T.any(Pathname, String), alias_path: T.nilable(Pathname), tap: T.nilable(Tap)).void }
    def initialize(path, alias_path: nil, tap: nil)
      path = Pathname(path).expand_path
      name = path.basename(".rb").to_s
      alias_path = alias_path&.expand_path
      alias_dir = alias_path&.dirname

      alias_path = nil if alias_dir != tap&.alias_dir

      super(name, path, alias_path:, tap:)
    end
  end

  # Loads formula from a URI.
  class FromURILoader < FormulaLoader
    sig {
      params(ref: T.any(String, Pathname, URI::Generic), from: T.nilable(Symbol), warn: T::Boolean)
        .returns(T.nilable(T.attached_class))
    }
    def self.try_new(ref, from: nil, warn: false)
      return if Homebrew::EnvConfig.forbid_packages_from_paths?

      # Cache compiled regex
      @uri_regex ||= T.let(begin
        uri_regex = ::URI::RFC2396_PARSER.make_regexp
        Regexp.new("\\A#{uri_regex.source}\\Z", uri_regex.options)
      end, T.nilable(Regexp))

      uri = ref.to_s
      return unless uri.match?(@uri_regex)

      uri = URI(uri)
      return unless uri.path
      return unless uri.scheme.present?

      new(uri, from:)
    end

    sig { returns(T.any(URI::Generic, String)) }
    attr_reader :url

    sig { params(url: T.any(URI::Generic, String), from: T.nilable(Symbol)).void }
    def initialize(url, from: nil)
      @url = url
      @from = from
      uri_path = URI(url).path
      raise ArgumentError, "URL has no path component" unless uri_path

      formula = File.basename(uri_path, ".rb")
      super formula, HOMEBREW_CACHE_FORMULA/File.basename(uri_path)
    end

    sig { override.params(flags: T::Array[String], ignore_errors: T::Boolean).void }
    def load_file(flags:, ignore_errors:)
      url_scheme = URI(url).scheme
      if ALLOWED_URL_SCHEMES.exclude?(url_scheme)
        raise UnsupportedInstallationMethod,
              "Non-checksummed download of #{name} formula file from an arbitrary URL is unsupported! " \
              "Use `brew extract` or `brew create` and `brew tap-new` to create a formula file in a tap " \
              "on GitHub instead."
      end
      HOMEBREW_CACHE_FORMULA.mkpath
      FileUtils.rm_f(path)
      Utils::Curl.curl_download url.to_s, to: path
      super
    rescue MethodDeprecatedError => e
      if (match_data = url.to_s.match(%r{github.com/(?<user>[\w-]+)/(?<repo>[\w-]+)/}).presence)
        e.issues_url = "https://github.com/#{match_data[:user]}/#{match_data[:repo]}/issues/new"
      end
      raise
    end
  end

  # Loads tapped formulae.
  class FromTapLoader < FormulaLoader
    sig { returns(Tap) }
    attr_reader :tap

    sig { returns(Pathname) }
    attr_reader :path

    sig {
      params(ref: T.any(String, Pathname, URI::Generic), from: T.nilable(Symbol), warn: T::Boolean)
        .returns(T.nilable(T.attached_class))
    }
    def self.try_new(ref, from: nil, warn: false)
      ref = ref.to_s

      return unless (name_tap_type = Formulary.tap_formula_name_type(ref, warn:))

      name, tap, type = name_tap_type
      path = Formulary.find_formula_in_tap(name, tap)

      if type == :alias
        # TODO: Simplify this by making `tap_formula_name_type` return the alias name.
        alias_name = T.must(ref[HOMEBREW_TAP_FORMULA_REGEX, :name]).downcase
      end

      if type == :migration && tap.core_tap? && (loader = FromAPILoader.try_new(name))
        T.cast(loader, T.attached_class)
      else
        new(name, path, tap:, alias_name:)
      end
    end

    sig { params(name: String, path: Pathname, tap: Tap, alias_name: T.nilable(String)).void }
    def initialize(name, path, tap:, alias_name: nil)
      alias_path = tap.alias_dir/alias_name if alias_name

      super(name, path, alias_path:, tap:)
      @tap = tap
    end

    sig {
      override.params(
        spec:          Symbol,
        alias_path:    T.nilable(T.any(Pathname, String)),
        force_bottle:  T::Boolean,
        flags:         T::Array[String],
        ignore_errors: T::Boolean,
      ).returns(Formula)
    }
    def get_formula(spec, alias_path: nil, force_bottle: false, flags: [], ignore_errors: false)
      super
    rescue FormulaUnreadableError => e
      raise TapFormulaUnreadableError.new(tap, name, e.formula_error), "", e.backtrace
    rescue FormulaClassUnavailableError => e
      raise TapFormulaClassUnavailableError.new(tap, name, e.path, e.class_name, e.class_list), "", e.backtrace
    rescue FormulaUnavailableError => e
      raise TapFormulaUnavailableError.new(tap, name), "", e.backtrace
    end

    sig { override.params(flags: T::Array[String], ignore_errors: T::Boolean).void }
    def load_file(flags:, ignore_errors:)
      super
    rescue MethodDeprecatedError => e
      e.issues_url = tap.issues_url || tap.to_s
      raise
    end
  end

  # Loads a formula from a name, as long as it exists only in a single tap.
  class FromNameLoader < FromTapLoader
    sig {
      override.params(ref: T.any(String, Pathname, URI::Generic), from: T.nilable(Symbol), warn: T::Boolean)
              .returns(T.nilable(T.attached_class))
    }
    def self.try_new(ref, from: nil, warn: false)
      return unless ref.is_a?(String)
      return unless ref.match?(/\A#{HOMEBREW_TAP_FORMULA_NAME_REGEX}\Z/o)

      name = ref

      # If it exists in the default tap, never treat it as ambiguous with another tap.
      if (core_tap = CoreTap.instance).installed? &&
         (core_loader = super("#{core_tap}/#{name}", warn:))&.path&.exist?
        return core_loader
      end

      loaders = Tap.select { |tap| tap.installed? && !tap.core_tap? }
                   .filter_map { |tap| super("#{tap}/#{name}", warn:) }
                   .uniq(&:path)
                   .select { |loader| loader.is_a?(FromAPILoader) || loader.path.exist? }

      case loaders.count
      when 1
        loaders.first
      when 2..Float::INFINITY
        raise TapFormulaAmbiguityError.new(name, loaders)
      end
    end
  end

  # Loads a formula from a formula file in a keg.
  class FromKegLoader < FormulaLoader
    sig {
      params(ref: T.any(String, Pathname, URI::Generic), from: T.nilable(Symbol), warn: T::Boolean)
        .returns(T.nilable(T.attached_class))
    }
    def self.try_new(ref, from: nil, warn: false)
      ref = ref.to_s

      keg_directory = HOMEBREW_PREFIX/"opt/#{ref}"
      return unless keg_directory.directory?

      # The formula file in `.brew` will use the canonical name, whereas `ref` can be an alias.
      # Use `Keg#name` to get the canonical name.
      keg = Keg.new(keg_directory)
      return unless (keg_formula = keg_directory/".brew/#{keg.name}.rb").file?

      new(keg.name, keg_formula, tap: keg.tab.tap)
    end
  end

  # Loads a formula from a cached formula file.
  class FromCacheLoader < FormulaLoader
    sig {
      params(ref: T.any(String, Pathname, URI::Generic), from: T.nilable(Symbol), warn: T::Boolean)
        .returns(T.nilable(T.attached_class))
    }
    def self.try_new(ref, from: nil, warn: false)
      ref = ref.to_s

      return unless (cached_formula = HOMEBREW_CACHE_FORMULA/"#{ref}.rb").file?

      new(ref, cached_formula)
    end
  end

  # Pseudo-loader which will raise a {FormulaUnavailableError} when trying to load the corresponding formula.
  class NullLoader < FormulaLoader
    sig {
      params(ref: T.any(String, Pathname, URI::Generic), from: T.nilable(Symbol), warn: T::Boolean)
        .returns(T.nilable(T.attached_class))
    }
    def self.try_new(ref, from: nil, warn: false)
      return if ref.is_a?(URI::Generic)

      new(ref)
    end

    sig { params(ref: T.any(String, Pathname)).void }
    def initialize(ref)
      name = File.basename(ref, ".rb")
      super name, Formulary.core_path(name)
    end

    sig {
      override.params(
        _spec:         Symbol,
        alias_path:    T.nilable(T.any(Pathname, String)),
        force_bottle:  T::Boolean,
        flags:         T::Array[String],
        ignore_errors: T::Boolean,
      ).returns(Formula)
    }
    def get_formula(_spec, alias_path: nil, force_bottle: false, flags: [], ignore_errors: false)
      raise FormulaUnavailableError, name
    end
  end

  # Load formulae directly from their contents.
  class FormulaContentsLoader < FormulaLoader
    # The formula's contents.
    sig { returns(String) }
    attr_reader :contents

    sig { params(name: String, path: Pathname, contents: String).void }
    def initialize(name, path, contents)
      @contents = contents
      super name, path
    end

    sig { override.params(flags: T::Array[String], ignore_errors: T::Boolean).returns(T.class_of(Formula)) }
    def klass(flags:, ignore_errors:)
      namespace = "FormulaNamespace#{Digest::MD5.hexdigest(contents.to_s)}"
      Formulary.load_formula(name, path, contents, namespace, flags:, ignore_errors:)
    end
  end

  # Load a formula from the API.
  class FromAPILoader < FormulaLoader
    sig {
      params(ref: T.any(String, Pathname, URI::Generic), from: T.nilable(Symbol), warn: T::Boolean)
        .returns(T.nilable(T.attached_class))
    }
    def self.try_new(ref, from: nil, warn: false)
      return if Homebrew::EnvConfig.no_install_from_api?
      return unless ref.is_a?(String)
      return unless (name = ref[HOMEBREW_DEFAULT_TAP_FORMULA_REGEX, :name])
      if Homebrew::API.formula_names.exclude?(name) &&
         !Homebrew::API.formula_aliases.key?(name) &&
         !Homebrew::API.formula_renames.key?(name)
        return
      end

      alias_name = name

      ref = "#{CoreTap.instance}/#{name}"

      return unless (name_tap_type = Formulary.tap_formula_name_type(ref, warn:))

      name, tap, type = name_tap_type

      alias_name = (type == :alias) ? alias_name.downcase : nil

      new(name, tap:, alias_name:)
    end

    sig { params(name: String, tap: T.nilable(Tap), alias_name: T.nilable(String)).void }
    def initialize(name, tap: nil, alias_name: nil)
      alias_path = CoreTap.instance.alias_dir/alias_name if alias_name

      super(name, Formulary.core_path(name), alias_path:, tap:)
    end

    sig { override.params(flags: T::Array[String], ignore_errors: T::Boolean).returns(T.class_of(Formula)) }
    def klass(flags:, ignore_errors:)
      load_from_api(flags:) unless Formulary.formula_class_defined_from_api?(name)
      Formulary.formula_class_get_from_api(name)
    end

    private

    sig { overridable.params(flags: T::Array[String]).void }
    def load_from_api(flags:)
      json_formula = if Homebrew::EnvConfig.use_internal_api?
        Homebrew::API::Formula.formula_json(name)
      else
        Homebrew::API::Formula.all_formulae[name]
      end

      raise FormulaUnavailableError, name if json_formula.nil?

      Formulary.load_formula_from_json!(name, json_formula, flags:)
    end
  end

  # Load formulae directly from their JSON contents.
  class FormulaJSONContentsLoader < FromAPILoader
    sig { params(name: String, contents: T::Hash[String, T.untyped], tap: T.nilable(Tap), alias_name: T.nilable(String)).void }
    def initialize(name, contents, tap: nil, alias_name: nil)
      @contents = contents
      super(name, tap: tap, alias_name: alias_name)
    end

    private

    sig { override.params(flags: T::Array[String]).void }
    def load_from_api(flags:)
      Formulary.load_formula_from_json!(name, @contents, flags:)
    end
  end

  # Load a formula stub from the internal API.
  class FormulaStubLoader < FromAPILoader
    sig {
      override.params(ref: T.any(String, Pathname, URI::Generic), from: T.nilable(Symbol), warn: T::Boolean)
              .returns(T.nilable(T.attached_class))
    }
    def self.try_new(ref, from: nil, warn: false)
      return unless Homebrew::EnvConfig.use_internal_api?

      super
    end

    sig { override.params(flags: T::Array[String], ignore_errors: T::Boolean).returns(T.class_of(Formula)) }
    def klass(flags:, ignore_errors:)
      load_from_api(flags:) unless Formulary.formula_class_defined_from_stub?(name)
      Formulary.formula_class_get_from_stub(name)
    end

    private

    sig { override.params(flags: T::Array[String]).void }
    def load_from_api(flags:)
      formula_stub = Homebrew::API::Internal.formula_stub(name)

      Formulary.load_formula_from_stub!(name, formula_stub, flags:)
    end
  end

  # Return a {Formula} instance for the given reference.
  # `ref` is a string containing:
  #
  # * a formula name
  # * a formula pathname
  # * a formula URL
  # * a local bottle reference
  #
  # @api internal
  sig {
    params(
      ref:           T.any(Pathname, String),
      spec:          Symbol,
      alias_path:    T.nilable(T.any(Pathname, String)),
      from:          T.nilable(Symbol),
      warn:          T::Boolean,
      force_bottle:  T::Boolean,
      flags:         T::Array[String],
      ignore_errors: T::Boolean,
      prefer_stub:   T::Boolean,
    ).returns(Formula)
  }
  def self.factory(
    ref,
    spec = :stable,
    alias_path: nil,
    from: nil,
    warn: false,
    force_bottle: false,
    flags: [],
    ignore_errors: false,
    prefer_stub: false
  )
    cache_key = "#{ref}-#{spec}-#{alias_path}-#{from}-#{prefer_stub}"
    return factory_cache.fetch(cache_key) if factory_cached? && factory_cache.key?(cache_key)

    loader = FormulaStubLoader.try_new(ref, from:, warn:) if prefer_stub
    loader ||= loader_for(ref, from:, warn:)
    formula = loader.get_formula(spec, alias_path:, force_bottle:, flags:, ignore_errors:)

    factory_cache[cache_key] ||= formula if factory_cached?

    formula
  end

  # A shortcut for calling `factory` with `prefer_stub: true`.
  #
  # Note: this method returns a stubbed formula which will include only:
  #
  # * name
  # * version
  # * revision
  # * version_scheme
  # * bottle information (for the current OS's bottle, only)
  # * aliases
  # * oldnames
  # * any other data that can be computed using only this information
  #
  # Only use the output for operations that do not require full formula data.
  #
  # @see .factory
  # @api internal
  sig {
    params(
      ref:           T.any(Pathname, String),
      spec:          Symbol,
      alias_path:    T.nilable(T.any(Pathname, String)),
      from:          T.nilable(Symbol),
      warn:          T::Boolean,
      force_bottle:  T::Boolean,
      flags:         T::Array[String],
      ignore_errors: T::Boolean,
    ).returns(Formula)
  }
  def self.factory_stub(
    ref,
    spec = :stable,
    alias_path: nil,
    from: nil,
    warn: false,
    force_bottle: false,
    flags: [],
    ignore_errors: false
  )
    factory(ref, spec, alias_path:, from:, warn:, force_bottle:, flags:, ignore_errors:, prefer_stub: true)
  end

  # Return a {Formula} instance for the given rack.
  #
  # @param spec when nil, will auto resolve the formula's spec.
  # @param alias_path will be used if the formula is found not to be
  #   installed and discarded if it is installed because the `alias_path` used
  #   to install the formula will be set instead.
  sig {
    params(
      rack:         Pathname,
      # Automatically resolves the formula's spec if not specified.
      spec:         T.nilable(Symbol),
      alias_path:   T.nilable(T.any(Pathname, String)),
      force_bottle: T::Boolean,
      flags:        T::Array[String],
      keg:          T.nilable(Keg),
    ).returns(Formula)
  }
  def self.from_rack(rack, spec = nil, alias_path: nil, force_bottle: false, flags: [], keg: Keg.from_rack(rack))
    options = {
      alias_path:,
      force_bottle:,
      flags:,
    }.compact

    if keg
      from_keg(keg, *spec, **options)
    else
      factory(rack.basename.to_s, *spec, from: :rack, warn: false, **options)
    end
  end

  # Return whether given rack is keg-only.
  sig { params(rack: Pathname).returns(T::Boolean) }
  def self.keg_only?(rack)
    Formulary.from_rack(rack).keg_only?
  rescue FormulaUnavailableError, TapFormulaAmbiguityError
    false
  end

  # Return a {Formula} instance for the given keg.
  sig {
    params(
      keg:          Keg,
      # Automatically resolves the formula's spec if not specified.
      spec:         T.nilable(Symbol),
      alias_path:   T.nilable(T.any(Pathname, String)),
      force_bottle: T::Boolean,
      flags:        T::Array[String],
    ).returns(Formula)
  }
  def self.from_keg(
    keg,
    spec = nil,
    alias_path: nil,
    force_bottle: false,
    flags: []
  )
    tab = keg.tab
    tap = tab.tap
    spec ||= tab.spec

    formula_name = keg.rack.basename.to_s

    options = {
      alias_path:,
      from:         :keg,
      warn:         false,
      force_bottle:,
      flags:,
    }.compact

    f = if Homebrew::EnvConfig.use_internal_api? && (loader = FromKegLoader.try_new(keg.name, warn: false))
      begin
        loader.get_formula(spec, alias_path:, force_bottle:, flags:)
      rescue FormulaUnreadableError
        nil
      end
    end

    f ||= if tap.nil?
      factory(formula_name, spec, **options)
    else
      begin
        factory("#{tap}/#{formula_name}", spec, **options)
      rescue FormulaUnavailableError
        # formula may be migrated to different tap. Try to search in core and all taps.
        factory(formula_name, spec, **options)
      end
    end
    f.build = tab
    T.cast(f.build, Tab).used_options = Tab.remap_deprecated_options(f.deprecated_options, tab.used_options).as_flags
    f.version.update_commit(keg.version.version.commit) if f.head? && keg.version.head?
    f
  end

  # Return a {Formula} instance directly from contents.
  sig {
    params(
      name:          String,
      path:          Pathname,
      contents:      String,
      spec:          Symbol,
      alias_path:    T.nilable(Pathname),
      force_bottle:  T::Boolean,
      flags:         T::Array[String],
      ignore_errors: T::Boolean,
    ).returns(Formula)
  }
  def self.from_contents(
    name,
    path,
    contents,
    spec = :stable,
    alias_path: nil,
    force_bottle: false,
    flags: [],
    ignore_errors: false
  )
    FormulaContentsLoader.new(name, path, contents)
                         .get_formula(spec, alias_path:, force_bottle:, flags:, ignore_errors:)
  end

  # Return a {Formula} instance directly from JSON contents.
  sig {
    params(
      name:          String,
      contents:      T::Hash[String, T.untyped],
      spec:          Symbol,
      alias_path:    T.nilable(Pathname),
      force_bottle:  T::Boolean,
      flags:         T::Array[String],
      ignore_errors: T::Boolean,
    ).returns(Formula)
  }
  def self.from_json_contents(
    name,
    contents,
    spec = :stable,
    alias_path: nil,
    force_bottle: false,
    flags: [],
    ignore_errors: false
  )
    FormulaJSONContentsLoader.new(name, contents)
                             .get_formula(spec, alias_path:, force_bottle:, flags:, ignore_errors:)
  end

  sig { params(ref: String).returns(Pathname) }
  def self.to_rack(ref)
    # If using a fully-scoped reference, check if the formula can be resolved.
    factory(ref) if ref.include? "/"

    # Check whether the rack with the given name exists.
    if (rack = HOMEBREW_CELLAR/File.basename(ref, ".rb")).directory?
      return rack.resolved_path
    end

    # Use canonical name to locate rack.
    (HOMEBREW_CELLAR/canonical_name(ref)).resolved_path
  end

  sig { params(ref: String).returns(String) }
  def self.canonical_name(ref)
    loader_for(ref).name
  rescue TapFormulaAmbiguityError
    # If there are multiple tap formulae with the name of ref,
    # then ref is the canonical name
    ref.downcase
  end

  sig { params(ref: String).returns(Pathname) }
  def self.path(ref)
    loader_for(ref).path
  end

  sig { params(tapped_name: String, warn: T::Boolean).returns(T.nilable([String, Tap, T.nilable(Symbol)])) }
  def self.tap_formula_name_type(tapped_name, warn:)
    return unless (tap_with_name = Tap.with_formula_name(tapped_name))

    tap, name = tap_with_name

    type = nil

    # FIXME: Remove the need to do this here.
    alias_table_key = tap.core_tap? ? name : "#{tap}/#{name}"

    if (possible_alias = tap.alias_table[alias_table_key].presence)
      # FIXME: Remove the need to split the name and instead make
      #        the alias table only contain short names.
      name = possible_alias.split("/").fetch(-1)
      type = :alias
    elsif (new_name = tap.formula_renames[name].presence)
      old_name = tap.core_tap? ? name : tapped_name
      name = new_name
      new_name = tap.core_tap? ? name : "#{tap}/#{name}"
      type = :rename
    elsif (new_tap_name = tap.tap_migrations[name].presence)
      new_tap, new_name = Tap.with_formula_name(new_tap_name)
      unless new_tap
        if new_tap_name.include?("/")
          new_tap = Tap.fetch(new_tap_name)
          new_name = name
        else
          new_tap = tap
          new_name = new_tap_name
        end
      end
      new_tap.ensure_installed!
      new_tapped_name = "#{new_tap}/#{new_name}"

      if tapped_name != new_tapped_name
        old_name = tap.core_tap? ? name : tapped_name
        return unless (name_tap_type = tap_formula_name_type(new_tapped_name, warn: false))

        name, tap, = name_tap_type

        new_name = new_tap.core_tap? ? name : "#{tap}/#{name}"
        type = :migration
      end
    end

    opoo "Formula #{old_name} was renamed to #{new_name}." if warn && old_name && new_name

    [name, tap, type]
  end

  sig { params(ref: T.any(String, Pathname), from: T.nilable(Symbol), warn: T::Boolean).returns(FormulaLoader) }
  def self.loader_for(ref, from: nil, warn: true)
    [
      FromBottleLoader,
      FromURILoader,
      FromAPILoader,
      FromTapLoader,
      FromPathLoader,
      FromNameLoader,
      FromKegLoader,
      FromCacheLoader,
    ].each do |loader_class|
      if (loader = loader_class.try_new(ref, from:, warn:))
        $stderr.puts "#{$PROGRAM_NAME} (#{loader_class}): loading #{ref}" if verbose? && debug?
        return loader
      end
    end

    NullLoader.new(ref)
  end

  sig { params(name: String).returns(Pathname) }
  def self.core_path(name)
    find_formula_in_tap(name.to_s.downcase, CoreTap.instance)
  end

  sig { params(name: String, tap: Tap).returns(Pathname) }
  def self.find_formula_in_tap(name, tap)
    filename = if name.end_with?(".rb")
      name
    else
      "#{name}.rb"
    end

    tap.formula_files_by_name.fetch(name, tap.formula_dir/filename)
  end
end
