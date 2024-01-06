# typed: true
# frozen_string_literal: true

require "digest/md5"
require "extend/cachable"
require "tab"
require "utils/bottles"
require "service"
require "utils/curl"
require "deprecate_disable"

require "active_support/core_ext/hash/deep_transform_values"

# The {Formulary} is responsible for creating instances of {Formula}.
# It is not meant to be used directly from formulae.
#
# @api private
module Formulary
  extend Cachable

  URL_START_REGEX = %r{(https?|ftp|file)://}.freeze

  # :codesign and custom requirement classes are not supported
  API_SUPPORTED_REQUIREMENTS = [:arch, :linux, :macos, :maximum_macos, :xcode].freeze

  sig { void }
  def self.enable_factory_cache!
    @factory_cache = true
  end

  def self.factory_cached?
    !@factory_cache.nil?
  end

  def self.formula_class_defined_from_path?(path)
    cache.key?(:path) && cache[:path].key?(path)
  end

  def self.formula_class_defined_from_api?(name)
    cache.key?(:api) && cache[:api].key?(name)
  end

  def self.formula_class_get_from_path(path)
    cache[:path].fetch(path)
  end

  def self.formula_class_get_from_api(name)
    cache[:api].fetch(name)
  end

  def self.clear_cache
    cache.each do |type, cached_objects|
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

  # @private
  module PathnameWriteMkpath
    refine Pathname do
      def write(content, offset = nil, **open_args)
        T.bind(self, Pathname)
        raise "Will not overwrite #{self}" if exist? && !offset && !open_args[:mode]&.match?(/^a\+?$/)

        dirname.mkpath

        super
      end
    end
  end

  using PathnameWriteMkpath
  def self.load_formula(name, path, contents, namespace, flags:, ignore_errors:)
    raise "Formula loading disabled by HOMEBREW_DISABLE_LOAD_FORMULA!" if Homebrew::EnvConfig.disable_load_formula?

    require "formula"
    require "ignorable"

    mod = Module.new
    remove_const(namespace) if const_defined?(namespace)
    const_set(namespace, mod)

    eval_formula = lambda do
      # Set `BUILD_FLAGS` in the formula's namespace so we can
      # access them from within the formula's class scope.
      mod.const_set(:BUILD_FLAGS, flags)
      mod.module_eval(contents, path)
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
                      .select { |const| const.is_a?(Class) }
      new_exception = FormulaClassUnavailableError.new(name, path, class_name, class_list)
      remove_const(namespace)
      raise new_exception, "", e.backtrace
    end
  end

  sig {
    params(name: String, path: Pathname, flags: T::Array[String], ignore_errors: T::Boolean)
      .returns(T.class_of(Formula))
  }
  def self.load_formula_from_path(name, path, flags:, ignore_errors:)
    contents = path.open("r") { |f| ensure_utf8_encoding(f).read }
    namespace = "FormulaNamespace#{Digest::MD5.hexdigest(path.to_s)}"
    klass = load_formula(name, path, contents, namespace, flags: flags, ignore_errors: ignore_errors)
    cache[:path] ||= {}
    cache[:path][path] = klass
  end

  sig { params(name: String, flags: T::Array[String]).returns(T.class_of(Formula)) }
  def self.load_formula_from_api(name, flags:)
    namespace = :"FormulaNamespaceAPI#{Digest::MD5.hexdigest(name)}"

    mod = Module.new
    remove_const(namespace) if const_defined?(namespace)
    const_set(namespace, mod)

    mod.const_set(:BUILD_FLAGS, flags)

    class_name = class_s(name)
    json_formula = Homebrew::API::Formula.all_formulae[name]
    raise FormulaUnavailableError, name if json_formula.nil?

    json_formula = Homebrew::API.merge_variations(json_formula)

    uses_from_macos_names = json_formula["uses_from_macos"]&.map do |dep|
      next dep unless dep.is_a? Hash

      dep.keys.first
    end

    requirements = {}
    json_formula["requirements"]&.map do |req|
      req_name = req["name"].to_sym
      next if API_SUPPORTED_REQUIREMENTS.exclude?(req_name)

      req_version = case req_name
      when :arch
        req["version"]&.to_sym
      when :macos, :maximum_macos
        MacOSVersion::SYMBOLS.key(req["version"])
      else
        req["version"]
      end

      req_tags = []
      req_tags << req_version if req_version.present?
      req_tags += req["contexts"]&.map do |tag|
        case tag
        when String
          tag.to_sym
        when Hash
          tag.deep_transform_keys(&:to_sym)
        else
          tag
        end
      end

      spec_hash = req_tags.empty? ? req_name : { req_name => req_tags }

      specs = req["specs"]
      specs ||= ["stable", "head"] # backwards compatibility
      specs.each do |spec|
        requirements[spec.to_sym] ||= []
        requirements[spec.to_sym] << spec_hash
      end
    end

    add_deps = lambda do |spec|
      T.bind(self, SoftwareSpec)

      dep_json = json_formula.fetch("#{spec}_dependencies", json_formula)

      dep_json["dependencies"]&.each do |dep|
        # Backwards compatibility check - uses_from_macos used to be a part of dependencies on Linux
        next if !json_formula.key?("uses_from_macos_bounds") && uses_from_macos_names.include?(dep) &&
                !Homebrew::SimulateSystem.simulating_or_running_on_macos?

        depends_on dep
      end

      [:build, :test, :recommended, :optional].each do |type|
        dep_json["#{type}_dependencies"]&.each do |dep|
          # Backwards compatibility check - uses_from_macos used to be a part of dependencies on Linux
          next if !json_formula.key?("uses_from_macos_bounds") && uses_from_macos_names.include?(dep) &&
                  !Homebrew::SimulateSystem.simulating_or_running_on_macos?

          depends_on dep => type
        end
      end

      dep_json["uses_from_macos"]&.each_with_index do |dep, index|
        bounds = dep_json.fetch("uses_from_macos_bounds", [])[index] || {}
        bounds.deep_transform_keys!(&:to_sym)
        bounds.deep_transform_values! { |val| val.is_a?(String) ? val.to_sym : val }

        if dep.is_a?(Hash)
          uses_from_macos dep.deep_transform_values(&:to_sym).merge(bounds)
        else
          uses_from_macos dep, bounds
        end
      end
    end

    klass = Class.new(::Formula) do
      @loaded_from_api = true

      desc json_formula["desc"]
      homepage json_formula["homepage"]
      license SPDX.string_to_license_expression(json_formula["license"])
      revision json_formula["revision"]
      version_scheme json_formula["version_scheme"]

      if (urls_stable = json_formula["urls"]["stable"].presence)
        stable do
          url_spec = {
            tag:      urls_stable["tag"],
            revision: urls_stable["revision"],
            using:    urls_stable["using"]&.to_sym,
          }.compact
          url urls_stable["url"], **url_spec
          version json_formula["versions"]["stable"]
          sha256 urls_stable["checksum"] if urls_stable["checksum"].present?

          instance_exec(:stable, &add_deps)

          requirements[:stable]&.each do |req|
            depends_on req
          end
        end
      end

      if (urls_head = json_formula["urls"]["head"].presence)
        head do
          url_spec = {
            branch: urls_head["branch"],
            using:  urls_head["using"]&.to_sym,
          }.compact
          url urls_head["url"], **url_spec

          instance_exec(:head, &add_deps)

          requirements[:head]&.each do |req|
            depends_on req
          end
        end
      end

      if (bottles_stable = json_formula["bottle"]["stable"].presence)
        bottle do
          if Homebrew::EnvConfig.bottle_domain == HOMEBREW_BOTTLE_DEFAULT_DOMAIN
            root_url HOMEBREW_BOTTLE_DEFAULT_DOMAIN
          else
            root_url Homebrew::EnvConfig.bottle_domain
          end
          rebuild bottles_stable["rebuild"]
          bottles_stable["files"].each do |tag, bottle_spec|
            cellar = Formulary.convert_to_string_or_symbol bottle_spec["cellar"]
            sha256 cellar: cellar, tag.to_sym => bottle_spec["sha256"]
          end
        end
      end

      if (pour_bottle_only_if = json_formula["pour_bottle_only_if"])
        pour_bottle? only_if: pour_bottle_only_if.to_sym
      end

      if (keg_only_reason = json_formula["keg_only_reason"].presence)
        reason = Formulary.convert_to_string_or_symbol keg_only_reason["reason"]
        keg_only reason, keg_only_reason["explanation"]
      end

      if (deprecation_date = json_formula["deprecation_date"].presence)
        reason = DeprecateDisable.to_reason_string_or_symbol json_formula["deprecation_reason"], type: :formula
        deprecate! date: deprecation_date, because: reason
      end

      if (disable_date = json_formula["disable_date"].presence)
        reason = DeprecateDisable.to_reason_string_or_symbol json_formula["disable_reason"], type: :formula
        disable! date: disable_date, because: reason
      end

      json_formula["conflicts_with"]&.each_with_index do |conflict, index|
        conflicts_with conflict, because: json_formula.dig("conflicts_with_reasons", index)
      end

      json_formula["link_overwrite"]&.each do |overwrite_path|
        link_overwrite overwrite_path
      end

      def install
        raise "Cannot build from source from abstract formula."
      end

      @post_install_defined_boolean = json_formula["post_install_defined"]
      @post_install_defined_boolean = true if @post_install_defined_boolean.nil? # Backwards compatibility
      def post_install_defined?
        self.class.instance_variable_get(:@post_install_defined_boolean)
      end

      if (service_hash = json_formula["service"].presence)
        service_hash = Homebrew::Service.deserialize(service_hash)
        service do
          T.bind(self, Homebrew::Service)

          if (run_params = service_hash.delete(:run).presence)
            case run_params
            when Hash
              run(**run_params)
            when Array, String
              run run_params
            end
          end

          if (name_params = service_hash.delete(:name).presence)
            name(**name_params)
          end

          service_hash.each do |key, arg|
            public_send(key, arg)
          end
        end
      end

      @caveats_string = json_formula["caveats"]
      def caveats
        self.class.instance_variable_get(:@caveats_string)
            &.gsub(HOMEBREW_PREFIX_PLACEHOLDER, HOMEBREW_PREFIX)
            &.gsub(HOMEBREW_CELLAR_PLACEHOLDER, HOMEBREW_CELLAR)
            &.gsub(HOMEBREW_HOME_PLACEHOLDER, Dir.home)
      end

      @tap_git_head_string = json_formula["tap_git_head"]
      def tap_git_head
        self.class.instance_variable_get(:@tap_git_head_string)
      end

      @oldnames_array = json_formula["oldnames"] || [json_formula["oldname"]].compact
      def oldnames
        self.class.instance_variable_get(:@oldnames_array)
      end

      @aliases_array = json_formula["aliases"]
      def aliases
        self.class.instance_variable_get(:@aliases_array)
      end

      @versioned_formulae_array = json_formula["versioned_formulae"]
      def versioned_formulae_names
        self.class.instance_variable_get(:@versioned_formulae_array)
      end

      @ruby_source_path_string = json_formula["ruby_source_path"]
      def ruby_source_path
        self.class.instance_variable_get(:@ruby_source_path_string)
      end

      @ruby_source_checksum_hash = json_formula["ruby_source_checksum"]
      def ruby_source_checksum
        checksum_hash = self.class.instance_variable_get(:@ruby_source_checksum_hash)
        Checksum.new(checksum_hash["sha256"]) if checksum_hash&.key?("sha256")
      end
    end

    klass = T.cast(klass, T.class_of(Formula))
    mod.const_set(class_name, klass)

    cache[:api] ||= {}
    cache[:api][name] = klass
  end

  sig { params(name: String, spec: Symbol, force_bottle: T::Boolean, flags: T::Array[String]).returns(Formula) }
  def self.resolve(
    name,
    spec: T.unsafe(nil),
    force_bottle: T.unsafe(nil),
    flags: T.unsafe(nil)
  )
    options = {
      force_bottle: force_bottle,
      flags:        flags,
    }.compact

    if name.include?("/") || File.exist?(name)
      f = factory(name, *spec, **options)
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
      if (alias_path = factory(name, **options).alias_path)
        options[:alias_path] = alias_path
      end
      f = from_rack(rack, *spec, **options)
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

  def self.ensure_utf8_encoding(io)
    io.set_encoding(Encoding::UTF_8)
  end

  def self.class_s(name)
    class_name = name.capitalize
    class_name.gsub!(/[-_.\s]([a-zA-Z0-9])/) { T.must(Regexp.last_match(1)).upcase }
    class_name.tr!("+", "x")
    class_name.sub!(/(.)@(\d)/, "\\1AT\\2")
    class_name
  end

  def self.convert_to_string_or_symbol(string)
    return string[1..].to_sym if string.start_with?(":")

    string
  end

  # A {FormulaLoader} returns instances of formulae.
  # Subclasses implement loaders for particular sources of formulae.
  class FormulaLoader
    include Context

    # The formula's name
    attr_reader :name
    # The formula's ruby file's path or filename
    attr_reader :path
    # The name used to install the formula
    attr_reader :alias_path
    # The formula's tap (nil if it should be implicitly determined)
    attr_reader :tap

    def initialize(name, path, tap: nil)
      @name = name
      @path = path
      @tap = tap
    end

    # Gets the formula instance.
    # `alias_path` can be overridden here in case an alias was used to refer to
    # a formula that was loaded in another way.
    def get_formula(spec, alias_path: nil, force_bottle: false, flags: [], ignore_errors: false)
      alias_path ||= self.alias_path
      klass(flags: flags, ignore_errors: ignore_errors)
        .new(name, path, spec, alias_path: alias_path, tap: tap, force_bottle: force_bottle)
    end

    def klass(flags:, ignore_errors:)
      load_file(flags: flags, ignore_errors: ignore_errors) unless Formulary.formula_class_defined_from_path?(path)
      Formulary.formula_class_get_from_path(path)
    end

    private

    def load_file(flags:, ignore_errors:)
      $stderr.puts "#{$PROGRAM_NAME} (#{self.class.name}): loading #{path}" if debug?
      raise FormulaUnavailableError, name unless path.file?

      Formulary.load_formula_from_path(name, path, flags: flags, ignore_errors: ignore_errors)
    end
  end

  # Loads a formula from a bottle.
  class BottleLoader < FormulaLoader
    def initialize(bottle_name)
      case bottle_name
      when URL_START_REGEX
        # The name of the formula is found between the last slash and the last hyphen.
        formula_name = File.basename(bottle_name)[/(.+)-/, 1]
        resource = Resource.new(formula_name) { url bottle_name }
        resource.specs[:bottle] = true
        downloader = resource.downloader
        cached = downloader.cached_location.exist?
        downloader.fetch
        ohai "Pouring the cached bottle" if cached
        @bottle_filename = downloader.cached_location
      else
        @bottle_filename = Pathname(bottle_name).realpath
      end
      name, full_name = Utils::Bottles.resolve_formula_names @bottle_filename
      super name, Formulary.path(full_name)
    end

    def get_formula(spec, force_bottle: false, flags: [], ignore_errors: false, **)
      formula = begin
        contents = Utils::Bottles.formula_contents @bottle_filename, name: name
        Formulary.from_contents(name, path, contents, spec, force_bottle: force_bottle,
                                flags: flags, ignore_errors: ignore_errors)
      rescue FormulaUnreadableError => e
        opoo <<~EOS
          Unreadable formula in #{@bottle_filename}:
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
      formula.local_bottle_path = @bottle_filename
      formula
    end
  end

  # Loads a formula from a path to an alias.
  class AliasLoader < FormulaLoader
    def initialize(alias_path)
      path = alias_path.resolved_path
      name = path.basename(".rb").to_s
      super name, path
      @alias_path = alias_path.to_s
    end
  end

  # Loads formulae from disk using a path.
  class FromPathLoader < FormulaLoader
    def initialize(path)
      path = Pathname.new(path).expand_path
      name = path.basename(".rb").to_s
      super name, path, tap: Homebrew::API.tap_from_source_download(path)
    end
  end

  # Loads formulae from URLs.
  class FromUrlLoader < FormulaLoader
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

    def load_file(flags:, ignore_errors:)
      match = url.match(%r{githubusercontent.com/[\w-]+/[\w-]+/[a-f0-9]{40}(?:/Formula)?/(?<name>[\w+-.@]+).rb})
      if match
        raise UnsupportedInstallationMethod,
              "Installation of #{match[:name]} from a GitHub commit URL is unsupported! " \
              "`brew extract #{match[:name]}` to a stable tap on GitHub instead."
      elsif url.match?(%r{^(https?|ftp)://})
        raise UnsupportedInstallationMethod,
              "Non-checksummed download of #{name} formula file from an arbitrary URL is unsupported! " \
              "`brew extract` or `brew create` and `brew tap-new` to create a formula file in a tap " \
              "on GitHub instead."
      end
      HOMEBREW_CACHE_FORMULA.mkpath
      FileUtils.rm_f(path)
      Utils::Curl.curl_download url, to: path
      super
    rescue MethodDeprecatedError => e
      if (match_data = url.match(%r{github.com/(?<user>[\w-]+)/(?<repo>[\w-]+)/}).presence)
        e.issues_url = "https://github.com/#{match_data[:user]}/#{match_data[:repo]}/issues/new"
      end
      raise
    end
  end

  # Loads tapped formulae.
  class TapLoader < FormulaLoader
    def get_formula(spec, alias_path: nil, force_bottle: false, flags: [], ignore_errors: false)
      super
    rescue FormulaUnreadableError => e
      raise TapFormulaUnreadableError.new(tap, name, e.formula_error), "", e.backtrace
    rescue FormulaClassUnavailableError => e
      raise TapFormulaClassUnavailableError.new(tap, name, e.path, e.class_name, e.class_list), "", e.backtrace
    rescue FormulaUnavailableError => e
      raise TapFormulaUnavailableError.new(tap, name), "", e.backtrace
    end

    def load_file(flags:, ignore_errors:)
      super
    rescue MethodDeprecatedError => e
      e.issues_url = tap.issues_url || tap.to_s
      raise
    end

    private

    def find_formula_from_name(name, tap)
      Formulary.find_formula_in_tap(name, tap)
    end
  end

  # Pseudo-loader which will raise a {FormulaUnavailableError} when trying to load the corresponding formula.
  class NullLoader < FormulaLoader
    def initialize(name)
      super name, Formulary.core_path(name)
    end

    def get_formula(*)
      raise FormulaUnavailableError, name
    end
  end

  # Load formulae directly from their contents.
  class FormulaContentsLoader < FormulaLoader
    # The formula's contents.
    attr_reader :contents

    def initialize(name, path, contents)
      @contents = contents
      super name, path
    end

    def klass(flags:, ignore_errors:)
      $stderr.puts "#{$PROGRAM_NAME} (#{self.class.name}): loading #{path}" if debug?
      namespace = "FormulaNamespace#{Digest::MD5.hexdigest(contents.to_s)}"
      Formulary.load_formula(name, path, contents, namespace, flags: flags, ignore_errors: ignore_errors)
    end
  end

  # Load formulae from the API.
  class FormulaAPILoader < FormulaLoader
    def initialize(name)
      super name, Formulary.core_path(name)
    end

    def klass(flags:, ignore_errors:)
      load_from_api(flags: flags) unless Formulary.formula_class_defined_from_api?(name)
      Formulary.formula_class_get_from_api(name)
    end

    private

    def load_from_api(flags:)
      $stderr.puts "#{$PROGRAM_NAME} (#{self.class.name}): loading #{name} from API" if debug?

      Formulary.load_formula_from_api(name, flags: flags)
    end
  end

  # Load aliases from the API.
  class AliasAPILoader < FormulaAPILoader
    def initialize(alias_name)
      super Homebrew::API::Formula.all_aliases[alias_name]
      @alias_path = Formulary.core_alias_path(alias_name).to_s
    end
  end

  # Return a {Formula} instance for the given reference.
  # `ref` is a string containing:
  #
  # * a formula name
  # * a formula pathname
  # * a formula URL
  # * a local bottle reference
  sig {
    params(
      ref:           T.any(Pathname, String),
      spec:          Symbol,
      alias_path:    T.any(NilClass, Pathname, String),
      from:          Symbol,
      warn:          T::Boolean,
      force_bottle:  T::Boolean,
      flags:         T::Array[String],
      ignore_errors: T::Boolean,
    ).returns(Formula)
  }
  def self.factory(
    ref,
    spec = :stable,
    alias_path: nil,
    from: T.unsafe(nil),
    warn: T.unsafe(nil),
    force_bottle: T.unsafe(nil),
    flags: T.unsafe(nil),
    ignore_errors: T.unsafe(nil)
  )
    cache_key = "#{ref}-#{spec}-#{alias_path}-#{from}"
    return cache[:formulary_factory][cache_key] if factory_cached? && cache[:formulary_factory]&.key?(cache_key)

    loader_options = { from: from, warn: warn }.compact
    formula_options = { alias_path:    alias_path,
                        force_bottle:  force_bottle,
                        flags:         flags,
                        ignore_errors: ignore_errors }.compact
    formula = loader_for(ref, **loader_options)
              .get_formula(spec, **formula_options)

    if factory_cached?
      cache[:formulary_factory] ||= {}
      cache[:formulary_factory][cache_key] ||= formula
    end

    formula
  end

  # Return a {Formula} instance for the given rack.
  #
  # @param spec when nil, will auto resolve the formula's spec.
  # @param :alias_path will be used if the formula is found not to be
  #   installed, and discarded if it is installed because the `alias_path` used
  #   to install the formula will be set instead.
  sig {
    params(
      rack:         Pathname,
      # Automatically resolves the formula's spec if not specified.
      spec:         Symbol,
      alias_path:   T.any(Pathname, String),
      force_bottle: T::Boolean,
      flags:        T::Array[String],
    ).returns(Formula)
  }
  def self.from_rack(
    rack, spec = T.unsafe(nil),
    alias_path: T.unsafe(nil),
    force_bottle: T.unsafe(nil),
    flags: T.unsafe(nil)
  )
    kegs = rack.directory? ? rack.subdirs.map { |d| Keg.new(d) } : []
    keg = kegs.find(&:linked?) || kegs.find(&:optlinked?) || kegs.max_by(&:version)

    options = {
      alias_path:   alias_path,
      force_bottle: force_bottle,
      flags:        flags,
    }.compact

    if keg
      from_keg(keg, *spec, **options)
    else
      factory(rack.basename.to_s, *spec, from: :rack, warn: false, **options)
    end
  end

  # Return whether given rack is keg-only.
  def self.keg_only?(rack)
    Formulary.from_rack(rack).keg_only?
  rescue FormulaUnavailableError, TapFormulaAmbiguityError, TapFormulaWithOldnameAmbiguityError
    false
  end

  # Return a {Formula} instance for the given keg.
  sig {
    params(
      keg:          Keg,
      # Automatically resolves the formula's spec if not specified.
      spec:         Symbol,
      alias_path:   T.any(Pathname, String),
      force_bottle: T::Boolean,
      flags:        T::Array[String],
    ).returns(Formula)
  }
  def self.from_keg(
    keg,
    spec = T.unsafe(nil),
    alias_path: T.unsafe(nil),
    force_bottle: T.unsafe(nil),
    flags: T.unsafe(nil)
  )
    tab = Tab.for_keg(keg)
    tap = tab.tap
    spec ||= tab.spec

    formula_name = keg.rack.basename.to_s

    options = {
      alias_path:   alias_path,
      from:         :keg,
      warn:         false,
      force_bottle: force_bottle,
      flags:        flags,
    }.compact

    f = if tap.nil?
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
      alias_path:    Pathname,
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
    alias_path: T.unsafe(nil),
    force_bottle: T.unsafe(nil),
    flags: T.unsafe(nil),
    ignore_errors: T.unsafe(nil)
  )
    options = {
      alias_path:    alias_path,
      force_bottle:  force_bottle,
      flags:         flags,
      ignore_errors: ignore_errors,
    }.compact
    FormulaContentsLoader.new(name, path, contents).get_formula(spec, **options)
  end

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

  def self.canonical_name(ref)
    loader_for(ref).name
  rescue TapFormulaAmbiguityError
    # If there are multiple tap formulae with the name of ref,
    # then ref is the canonical name
    ref.downcase
  end

  def self.path(ref)
    loader_for(ref).path
  end

  def self.tap_formula_name_path(tapped_name, warn:)
    user, repo, name = tapped_name.split("/", 3).map(&:downcase)
    tap = Tap.fetch user, repo
    path = Formulary.find_formula_in_tap(name, tap)

    unless path.file?
      if (possible_alias = tap.alias_dir/name).file?
        path = possible_alias.resolved_path
        name = path.basename(".rb").to_s
      elsif (new_name = tap.formula_renames[name].presence) &&
            (new_path = Formulary.find_formula_in_tap(new_name, tap)).file?
        old_name = name
        path = new_path
        name = new_name
        new_name = tap.core_tap? ? name : "#{tap}/#{name}"
      elsif (new_tap_name = tap.tap_migrations[name].presence)
        new_tap_user, new_tap_repo, = new_tap_name.split("/")
        new_tap_name = "#{new_tap_user}/#{new_tap_repo}"
        new_tap = Tap.fetch new_tap_name
        new_tap.ensure_installed!
        new_tapped_name = "#{new_tap_name}/#{name}"
        name, path, tap = Formulary.tap_formula_name_path(new_tapped_name, warn: false)
        old_name = tapped_name
        new_name = new_tap.core_tap? ? name : new_tapped_name
      end

      opoo "Formula #{old_name} was renamed to #{new_name}." if warn && old_name && new_name
    end

    [name, path, tap]
  end

  def self.tap_loader_for(tapped_name, warn:)
    name, path, tap = Formulary.tap_formula_name_path(tapped_name, warn: warn)

    if tap.core_tap? && !Homebrew::EnvConfig.no_install_from_api? &&
       Homebrew::API::Formula.all_formulae.key?(name)
      FormulaAPILoader.new(name)
    else
      TapLoader.new(name, path, tap: tap)
    end
  end

  def self.loader_for(ref, from: nil, warn: true)
    case ref
    when HOMEBREW_BOTTLES_EXTNAME_REGEX
      return BottleLoader.new(ref)
    when URL_START_REGEX
      return FromUrlLoader.new(ref, from: from)
    when HOMEBREW_TAP_FORMULA_REGEX
      if ref.match?(%r{^homebrew/(?:homebrew-)?core/}i) && !Homebrew::EnvConfig.no_install_from_api?
        name = ref.split("/", 3).last
        return FormulaAPILoader.new(name) if Homebrew::API::Formula.all_formulae.key?(name)
        return AliasAPILoader.new(name) if Homebrew::API::Formula.all_aliases.key?(name)
      end

      return Formulary.tap_loader_for(ref, warn: warn)
    end

    pathname_ref = Pathname.new(ref)
    return FromPathLoader.new(ref) if File.extname(ref) == ".rb" && pathname_ref.expand_path.exist?

    unless Homebrew::EnvConfig.no_install_from_api?
      return FormulaAPILoader.new(ref) if Homebrew::API::Formula.all_formulae.key?(ref)
      return AliasAPILoader.new(ref) if Homebrew::API::Formula.all_aliases.key?(ref)
    end

    formula_with_that_name = core_path(ref)
    return FormulaLoader.new(ref, formula_with_that_name) if formula_with_that_name.file?

    possible_alias = if pathname_ref.absolute?
      pathname_ref
    else
      core_alias_path(ref)
    end
    return AliasLoader.new(possible_alias) if possible_alias.symlink?

    possible_tap_formulae = tap_paths(ref)
    raise TapFormulaAmbiguityError.new(ref, possible_tap_formulae) if possible_tap_formulae.size > 1

    if possible_tap_formulae.size == 1
      path = possible_tap_formulae.first.resolved_path
      name = path.basename(".rb").to_s
      return FormulaLoader.new(name, path)
    end

    if CoreTap.instance.formula_renames.key?(ref)
      unless Homebrew::EnvConfig.no_install_from_api?
        return FormulaAPILoader.new(CoreTap.instance.formula_renames[ref])
      end

      return Formulary.tap_loader_for("#{CoreTap.instance}/#{ref}", warn: warn)
    end

    possible_taps = Tap.select { |tap| tap.formula_renames.key?(ref) }

    if possible_taps.size > 1
      possible_tap_newname_formulae = possible_taps.map { |tap| "#{tap}/#{tap.formula_renames[ref]}" }
      raise TapFormulaWithOldnameAmbiguityError.new(ref, possible_tap_newname_formulae)
    end

    return Formulary.tap_loader_for("#{possible_taps.first}/#{ref}", warn: warn) unless possible_taps.empty?

    possible_keg_formula = Pathname.new("#{HOMEBREW_PREFIX}/opt/#{ref}/.brew/#{ref}.rb")
    return FormulaLoader.new(ref, possible_keg_formula) if possible_keg_formula.file?

    possible_cached_formula = Pathname.new("#{HOMEBREW_CACHE_FORMULA}/#{ref}.rb")
    return FormulaLoader.new(ref, possible_cached_formula) if possible_cached_formula.file?

    NullLoader.new(ref)
  end

  def self.core_path(name)
    find_formula_in_tap(name.to_s.downcase, CoreTap.instance)
  end

  def self.core_alias_path(name)
    CoreTap.instance.alias_dir/name.to_s.downcase
  end

  def self.tap_paths(name, taps = Tap)
    name = name.to_s.downcase
    taps.map do |tap|
      formula_path = find_formula_in_tap(name, tap)

      alias_path = tap.alias_dir/name
      next alias_path if !formula_path.exist? && alias_path.exist?

      formula_path
    end.select(&:file?)
  end

  sig { params(name: String, tap: Tap).returns(Pathname) }
  def self.find_formula_in_tap(name, tap)
    filename = if name.end_with?(".rb")
      name
    else
      "#{name}.rb"
    end

    Tap.formula_files_by_name(tap)
       .fetch(name, tap.formula_dir/filename)
  end
end
