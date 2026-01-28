# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "autobump_constants"
require "locale"
require "lazy_object"
require "livecheck"
require "utils/output"

require "cask/artifact"
require "cask/artifact_set"

require "cask/caskroom"
require "cask/exceptions"

require "cask/dsl/base"
require "cask/dsl/caveats"
require "cask/dsl/conflicts_with"
require "cask/dsl/container"
require "cask/dsl/depends_on"
require "cask/dsl/postflight"
require "cask/dsl/preflight"
require "cask/dsl/rename"
require "cask/dsl/uninstall_postflight"
require "cask/dsl/uninstall_preflight"
require "cask/dsl/version"

require "cask/url"
require "cask/utils"

require "on_system"

module Cask
  # Class representing the domain-specific language used for casks.
  class DSL
    include ::Utils::Output::Mixin

    ORDINARY_ARTIFACT_CLASSES = [
      Artifact::Installer,
      Artifact::App,
      Artifact::Artifact,
      Artifact::AudioUnitPlugin,
      Artifact::Binary,
      Artifact::Colorpicker,
      Artifact::Dictionary,
      Artifact::Font,
      Artifact::InputMethod,
      Artifact::InternetPlugin,
      Artifact::KeyboardLayout,
      Artifact::Manpage,
      Artifact::Pkg,
      Artifact::Prefpane,
      Artifact::Qlplugin,
      Artifact::Mdimporter,
      Artifact::ScreenSaver,
      Artifact::Service,
      Artifact::StageOnly,
      Artifact::Suite,
      Artifact::VstPlugin,
      Artifact::Vst3Plugin,
      Artifact::ZshCompletion,
      Artifact::FishCompletion,
      Artifact::BashCompletion,
      Artifact::Uninstall,
      Artifact::Zap,
    ].freeze

    ACTIVATABLE_ARTIFACT_CLASSES = (ORDINARY_ARTIFACT_CLASSES - [Artifact::StageOnly]).freeze

    ARTIFACT_BLOCK_CLASSES = [
      Artifact::PreflightBlock,
      Artifact::PostflightBlock,
    ].freeze

    DSL_METHODS = Set.new([
      :arch,
      :artifacts,
      :auto_updates,
      :caveats,
      :conflicts_with,
      :container,
      :desc,
      :depends_on,
      :homepage,
      :language,
      :name,
      :os,
      :rename,
      :sha256,
      :staged_path,
      :url,
      :version,
      :appdir,
      :deprecate!,
      :deprecated?,
      :deprecation_date,
      :deprecation_reason,
      :deprecation_replacement_cask,
      :deprecation_replacement_formula,
      :deprecate_args,
      :disable!,
      :disabled?,
      :disable_date,
      :disable_reason,
      :disable_replacement_cask,
      :disable_replacement_formula,
      :disable_args,
      :livecheck,
      :livecheck_defined?,
      :no_autobump!,
      :autobump?,
      :no_autobump_message,
      :on_system_blocks_exist?,
      :on_system_block_min_os,
      :depends_on_set_in_block?,
      *ORDINARY_ARTIFACT_CLASSES.map(&:dsl_key),
      *ACTIVATABLE_ARTIFACT_CLASSES.map(&:dsl_key),
      *ARTIFACT_BLOCK_CLASSES.flat_map { |klass| [klass.dsl_key, klass.uninstall_dsl_key] },
    ]).freeze

    include OnSystem::MacOSAndLinux

    attr_reader :cask, :token, :no_autobump_message, :artifacts, :deprecation_date, :deprecation_reason,
                :deprecation_replacement_cask, :deprecation_replacement_formula, :deprecate_args,
                :disable_date, :disable_reason, :disable_replacement_cask,
                :disable_replacement_formula, :disable_args, :on_system_block_min_os

    sig { params(cask: Cask).void }
    def initialize(cask)
      # NOTE: `:"@#{stanza}"` variables set by `set_unique_stanza` must be
      # initialized to `nil`.
      @arch = T.let(nil, T.nilable(String))
      @arch_set_in_block = T.let(false, T::Boolean)
      @artifacts = T.let(ArtifactSet.new, ArtifactSet)
      @auto_updates = T.let(nil, T.nilable(T::Boolean))
      @auto_updates_set_in_block = T.let(false, T::Boolean)
      @autobump = T.let(true, T::Boolean)
      @called_in_on_system_block = T.let(false, T::Boolean)
      @cask = T.let(cask, Cask)
      @caveats = T.let(DSL::Caveats.new(cask), DSL::Caveats)
      @conflicts_with = T.let(nil, T.nilable(DSL::ConflictsWith))
      @conflicts_with_set_in_block = T.let(false, T::Boolean)
      @container = T.let(nil, T.nilable(DSL::Container))
      @container_set_in_block = T.let(false, T::Boolean)
      @depends_on = T.let(DSL::DependsOn.new, DSL::DependsOn)
      @depends_on_set_in_block = T.let(false, T::Boolean)
      @deprecated = T.let(false, T::Boolean)
      @deprecation_date = T.let(nil, T.nilable(Date))
      @deprecation_reason = T.let(nil, T.nilable(T.any(String, Symbol)))
      @deprecation_replacement_cask = T.let(nil, T.nilable(String))
      @deprecation_replacement_formula = T.let(nil, T.nilable(String))
      @deprecate_args = T.let(nil, T.nilable(T::Hash[Symbol, T.nilable(T.any(String, Symbol))]))
      @desc = T.let(nil, T.nilable(String))
      @desc_set_in_block = T.let(false, T::Boolean)
      @disable_date = T.let(nil, T.nilable(Date))
      @disable_reason = T.let(nil, T.nilable(T.any(String, Symbol)))
      @disable_replacement_cask = T.let(nil, T.nilable(String))
      @disable_replacement_formula = T.let(nil, T.nilable(String))
      @disable_args = T.let(nil, T.nilable(T::Hash[Symbol, T.nilable(T.any(String, Symbol))]))
      @disabled = T.let(false, T::Boolean)
      @homepage = T.let(nil, T.nilable(String))
      @homepage_set_in_block = T.let(false, T::Boolean)
      @language_blocks = T.let({}, T::Hash[T::Array[String], Proc])
      @language_eval = T.let(nil, T.nilable(String))
      @livecheck = T.let(Livecheck.new(cask), Livecheck)
      @livecheck_defined = T.let(false, T::Boolean)
      @name = T.let([], T::Array[String])
      @no_autobump_defined = T.let(false, T::Boolean)
      @on_system_blocks_exist = T.let(false, T::Boolean)
      @on_system_block_min_os = T.let(nil, T.nilable(MacOSVersion))
      @os = T.let(nil, T.nilable(String))
      @os_set_in_block = T.let(false, T::Boolean)
      @rename = T.let([], T::Array[DSL::Rename])
      @sha256 = T.let(nil, T.nilable(T.any(Checksum, Symbol)))
      @sha256_set_in_block = T.let(false, T::Boolean)
      @staged_path = T.let(nil, T.nilable(Pathname))
      @token = T.let(cask.token, String)
      @url = T.let(nil, T.nilable(URL))
      @url_set_in_block = T.let(false, T::Boolean)
      @version = T.let(nil, T.nilable(DSL::Version))
      @version_set_in_block = T.let(false, T::Boolean)
    end

    sig { returns(T::Boolean) }
    def depends_on_set_in_block? = @depends_on_set_in_block

    sig { returns(T::Boolean) }
    def deprecated? = @deprecated

    sig { returns(T::Boolean) }
    def disabled? = @disabled

    sig { returns(T::Boolean) }
    def livecheck_defined? = @livecheck_defined

    sig { returns(T::Boolean) }
    def on_system_blocks_exist? = @on_system_blocks_exist

    # Specifies the cask's name.
    #
    # NOTE: Multiple names can be specified.
    #
    # ### Example
    #
    # ```ruby
    # name "Visual Studio Code"
    # ```
    #
    # @api public
    def name(*args)
      return @name if args.empty?

      @name.concat(args.flatten)
    end

    # Describes the cask.
    #
    # ### Example
    #
    # ```ruby
    # desc "Open-source code editor"
    # ```
    #
    # @api public
    def desc(description = nil)
      set_unique_stanza(:desc, description.nil?) { description }
    end

    def set_unique_stanza(stanza, should_return)
      return instance_variable_get(:"@#{stanza}") if should_return

      unless @cask.allow_reassignment
        if !instance_variable_get(:"@#{stanza}").nil? && !@called_in_on_system_block
          raise CaskInvalidError.new(cask, "'#{stanza}' stanza may only appear once.")
        end

        if instance_variable_get(:"@#{stanza}_set_in_block") && @called_in_on_system_block
          raise CaskInvalidError.new(cask, "'#{stanza}' stanza may only be overridden once.")
        end
      end

      instance_variable_set(:"@#{stanza}_set_in_block", true) if @called_in_on_system_block
      instance_variable_set(:"@#{stanza}", yield)
    rescue CaskInvalidError
      raise
    rescue => e
      raise CaskInvalidError.new(cask, "'#{stanza}' stanza failed with: #{e}")
    end

    # Sets the cask's homepage.
    #
    # ### Example
    #
    # ```ruby
    # homepage "https://code.visualstudio.com/"
    # ```
    #
    # @api public
    def homepage(homepage = nil)
      set_unique_stanza(:homepage, homepage.nil?) { homepage }
    end

    def language(*args, default: false, &block)
      if args.empty?
        language_eval
      elsif block
        @language_blocks[args] = block

        return unless default

        if !@cask.allow_reassignment && @language_blocks.default.present?
          raise CaskInvalidError.new(cask, "Only one default language may be defined.")
        end

        @language_blocks.default = block
      else
        raise CaskInvalidError.new(cask, "No block given to language stanza.")
      end
    end

    def language_eval
      return @language_eval unless @language_eval.nil?

      return @language_eval = nil if @language_blocks.empty?

      if (language_blocks_default = @language_blocks.default).nil?
        raise CaskInvalidError.new(cask, "No default language specified.")
      end

      locales = cask.config.languages
                    .filter_map do |language|
                      Locale.parse(language)
                    rescue Locale::ParserError
                      nil
                    end

      locales.each do |locale|
        key = locale.detect(@language_blocks.keys)
        next if key.nil? || (language_block = @language_blocks[key]).nil?

        return @language_eval = language_block.call
      end

      @language_eval = language_blocks_default.call
    end

    def languages
      @language_blocks.keys.flatten
    end

    # Sets the cask's download URL.
    #
    # ### Example
    #
    # ```ruby
    # url "https://update.code.visualstudio.com/#{version}/#{arch}/stable"
    # ```
    #
    # @api public
    def url(*args, **options)
      caller_location = T.must(caller_locations).fetch(0)

      set_unique_stanza(:url, args.empty? && options.empty?) do
        URL.new(*args, **options, caller_location:)
      end
    end

    # Sets the cask's container type or nested container path.
    #
    # ### Examples
    #
    # The container is a nested disk image:
    #
    # ```ruby
    # container nested: "orca-#{version}.dmg"
    # ```
    #
    # The container should not be unarchived:
    #
    # ```ruby
    # container type: :naked
    # ```
    #
    # @api public
    def container(**kwargs)
      set_unique_stanza(:container, kwargs.empty?) do
        DSL::Container.new(**kwargs)
      end
    end

    # Renames files after extraction.
    #
    # This is useful when the downloaded file has unpredictable names
    # that need to be normalized for proper artifact installation.
    #
    # ### Example
    #
    # ```ruby
    # rename "RØDECaster App*.pkg", "RØDECaster App.pkg"
    # ```
    #
    # @api public
    sig {
      params(from: String,
             to:   String).returns(T::Array[DSL::Rename])
    }
    def rename(from = T.unsafe(nil), to = T.unsafe(nil))
      return @rename if from.nil?

      @rename << DSL::Rename.new(T.must(from), T.must(to))
    end

    # Sets the cask's version.
    #
    # ### Example
    #
    # ```ruby
    # version "1.88.1"
    # ```
    #
    # @see DSL::Version
    # @api public
    sig { params(arg: T.nilable(T.any(String, Symbol))).returns(T.nilable(DSL::Version)) }
    def version(arg = nil)
      set_unique_stanza(:version, arg.nil?) do
        if !arg.is_a?(String) && arg != :latest
          raise CaskInvalidError.new(cask, "invalid 'version' value: #{arg.inspect}")
        end

        no_autobump! because: :latest_version if arg == :latest

        DSL::Version.new(arg)
      end
    end

    # Sets the cask's download checksum.
    #
    # ### Example
    #
    # For universal or single-architecture downloads:
    #
    # ```ruby
    # sha256 "7bdb497080ffafdfd8cc94d8c62b004af1be9599e865e5555e456e2681e150ca"
    # ```
    #
    # For architecture-dependent downloads:
    #
    # ```ruby
    # sha256 arm:          "7bdb497080ffafdfd8cc94d8c62b004af1be9599e865e5555e456e2681e150ca",
    #        x86_64:       "b3c1c2442480a0219b9e05cf91d03385858c20f04b764ec08a3fa83d1b27e7b2"
    #        x86_64_linux: "1a2aee7f1ddc999993d4d7d42a150c5e602bc17281678050b8ed79a0500cc90f"
    #        arm64_linux:  "bd766af7e692afceb727a6f88e24e6e68d9882aeb3e8348412f6c03d96537c75"
    # ```
    #
    # @api public
    sig {
      params(
        arg:          T.nilable(T.any(String, Symbol)),
        arm:          T.nilable(String),
        intel:        T.nilable(String),
        x86_64:       T.nilable(String),
        x86_64_linux: T.nilable(String),
        arm64_linux:  T.nilable(String),
      ).returns(T.nilable(T.any(Symbol, Checksum)))
    }
    def sha256(arg = nil, arm: nil, intel: nil, x86_64: nil, x86_64_linux: nil, arm64_linux: nil)
      should_return = arg.nil? && arm.nil? && (intel.nil? || x86_64.nil?) && x86_64_linux.nil? && arm64_linux.nil?

      x86_64 ||= intel if intel.present? && x86_64.nil?
      set_unique_stanza(:sha256, should_return) do
        if arm.present? || x86_64.present? || x86_64_linux.present? || arm64_linux.present?
          @on_system_blocks_exist = true
        end

        val = arg || on_system_conditional(
          macos: on_arch_conditional(arm:, intel: x86_64),
          linux: on_arch_conditional(arm: arm64_linux, intel: x86_64_linux),
        )
        case val
        when :no_check
          val
        when String
          Checksum.new(val)
        else
          raise CaskInvalidError.new(cask, "invalid 'sha256' value: #{val.inspect}")
        end
      end
    end

    # Sets the cask's architecture strings.
    #
    # ### Example
    #
    # ```ruby
    # arch arm: "darwin-arm64", intel: "darwin"
    # ```
    #
    # @api public
    def arch(arm: nil, intel: nil)
      should_return = arm.nil? && intel.nil?

      set_unique_stanza(:arch, should_return) do
        @on_system_blocks_exist = true

        on_arch_conditional(arm:, intel:)
      end
    end

    # Sets the cask's os strings.
    #
    # ### Example
    #
    # ```ruby
    # os macos: "darwin", linux: "tux"
    # ```
    #
    # @api public
    sig {
      params(
        macos: T.nilable(String),
        linux: T.nilable(String),
      ).returns(T.nilable(String))
    }
    def os(macos: nil, linux: nil)
      should_return = macos.nil? && linux.nil?

      set_unique_stanza(:os, should_return) do
        @on_system_blocks_exist = true

        on_system_conditional(macos:, linux:)
      end
    end

    # Declare dependencies and requirements for a cask.
    #
    # NOTE: Multiple dependencies can be specified.
    #
    # @api public
    def depends_on(**kwargs)
      @depends_on_set_in_block = true if @called_in_on_system_block
      return @depends_on if kwargs.empty?

      begin
        @depends_on.load(**kwargs)
      rescue RuntimeError => e
        raise CaskInvalidError.new(cask, e)
      end
      @depends_on
    end

    # @api private
    def add_implicit_macos_dependency
      return if (cask_depends_on = @depends_on).present? && cask_depends_on.macos.present?

      depends_on macos: ">= #{MacOSVersion.new(HOMEBREW_MACOS_OLDEST_ALLOWED).to_sym.inspect}"
    end

    # Declare conflicts that keep a cask from installing or working correctly.
    #
    # @api public
    def conflicts_with(**kwargs)
      # TODO: Remove this constraint and instead merge multiple `conflicts_with` stanzas
      set_unique_stanza(:conflicts_with, kwargs.empty?) { DSL::ConflictsWith.new(**kwargs) }
    end

    sig { returns(Pathname) }
    def caskroom_path
      cask.caskroom_path
    end

    # The staged location for this cask, including version number.
    #
    # @api public
    sig { returns(Pathname) }
    def staged_path
      return @staged_path if @staged_path

      cask_version = version || :unknown
      @staged_path = caskroom_path.join(cask_version.to_s)
    end

    # Provide the user with cask-specific information at install time.
    #
    # @api public
    def caveats(*strings, &block)
      if block
        @caveats.eval_caveats(&block)
      elsif strings.any?
        strings.each do |string|
          @caveats.eval_caveats { string }
        end
      else
        return @caveats.to_s
      end
      @caveats
    end

    # Asserts that the cask artifacts auto-update.
    #
    # @api public
    def auto_updates(auto_updates = nil)
      set_unique_stanza(:auto_updates, auto_updates.nil?) { auto_updates }
    end

    # Automatically fetch the latest version of a cask from changelogs.
    #
    # @api public
    def livecheck(&block)
      return @livecheck unless block

      if !@cask.allow_reassignment && @livecheck_defined
        raise CaskInvalidError.new(cask, "'livecheck' stanza may only appear once.")
      end

      @livecheck_defined = true
      @livecheck.instance_eval(&block)
      no_autobump! because: :extract_plist if @livecheck.strategy == :extract_plist
      @livecheck
    end

    # Excludes the cask from autobump list.
    #
    # TODO: limit this method to the official taps only
    #       (e.g. raise an error if `!tap.official?`)
    #
    # @api public
    sig { params(because: T.any(String, Symbol)).void }
    def no_autobump!(because:)
      if because.is_a?(Symbol) && !NO_AUTOBUMP_REASONS_LIST.key?(because)
        raise ArgumentError, "'because' argument should use valid symbol or a string!"
      end

      if !@cask.allow_reassignment && @no_autobump_defined
        raise CaskInvalidError.new(cask, "'no_autobump_defined' stanza may only appear once.")
      end

      @no_autobump_defined = true
      @no_autobump_message = because
      @autobump = false
    end

    # Is the cask in autobump list?
    def autobump?
      @autobump == true
    end

    # Is no_autobump! method defined?
    def no_autobump_defined?
      @no_autobump_defined == true
    end

    # Declare that a cask is no longer functional or supported.
    #
    # NOTE: A warning will be shown when trying to install this cask.
    #
    # @api public
    def deprecate!(date:, because:, replacement: nil, replacement_formula: nil, replacement_cask: nil)
      if [replacement, replacement_formula, replacement_cask].filter_map(&:presence).length > 1
        raise ArgumentError, "more than one of replacement, replacement_formula and/or replacement_cask specified!"
      end

      if replacement
        odeprecated(
          "deprecate!(:replacement)",
          "deprecate!(:replacement_formula) or deprecate!(:replacement_cask)",
        )
      end

      @deprecate_args = { date:, because:, replacement_formula:, replacement_cask: }

      @deprecation_date = Date.parse(date)
      return if @deprecation_date > Date.today

      @deprecation_reason = because
      @deprecation_replacement_formula = replacement_formula.presence || replacement
      @deprecation_replacement_cask = replacement_cask.presence || replacement
      @deprecated = true
    end

    # Declare that a cask is no longer functional or supported.
    #
    # NOTE: An error will be thrown when trying to install this cask.
    #
    # @api public
    def disable!(date:, because:, replacement: nil, replacement_formula: nil, replacement_cask: nil)
      if [replacement, replacement_formula, replacement_cask].filter_map(&:presence).length > 1
        raise ArgumentError, "more than one of replacement, replacement_formula and/or replacement_cask specified!"
      end

      # odeprecate: remove this remapping when the :unsigned reason is removed
      because = :fails_gatekeeper_check if because == :unsigned

      if replacement
        odeprecated(
          "disable!(:replacement)",
          "disable!(:replacement_formula) or disable!(:replacement_cask)",
        )
      end

      @disable_args = { date:, because:, replacement_formula:, replacement_cask: }

      @disable_date = Date.parse(date)

      if @disable_date > Date.today
        @deprecation_reason = because
        @deprecation_replacement_formula = replacement_formula.presence || replacement
        @deprecation_replacement_cask = replacement_cask.presence || replacement
        @deprecated = true
        return
      end

      @disable_reason = because
      @disable_replacement_formula = replacement_formula.presence || replacement
      @disable_replacement_cask = replacement_cask.presence || replacement
      @disabled = true
    end

    ORDINARY_ARTIFACT_CLASSES.each do |klass|
      define_method(klass.dsl_key) do |*args, **kwargs|
        T.bind(self, DSL)
        if [*artifacts.map(&:class), klass].include?(Artifact::StageOnly) &&
           artifacts.map(&:class).intersect?(ACTIVATABLE_ARTIFACT_CLASSES)
          raise CaskInvalidError.new(cask, "'stage_only' must be the only activatable artifact.")
        end

        artifacts.add(klass.from_args(cask, *args, **kwargs))
      rescue CaskInvalidError
        raise
      rescue => e
        raise CaskInvalidError.new(cask, "invalid '#{klass.dsl_key}' stanza: #{e}")
      end
    end

    ARTIFACT_BLOCK_CLASSES.each do |klass|
      [klass.dsl_key, klass.uninstall_dsl_key].each do |dsl_key|
        define_method(dsl_key) do |&block|
          T.bind(self, DSL)
          artifacts.add(klass.new(cask, dsl_key => block))
        end
      end
    end

    def method_missing(method, *)
      if method
        Utils.method_missing_message(method, token)
        nil
      else
        super
      end
    end

    def respond_to_missing?(*)
      true
    end

    sig { returns(T.nilable(MacOSVersion)) }
    def os_version
      nil
    end

    # The directory `app`s are installed into.
    #
    # @api public
    sig { returns(T.any(Pathname, String)) }
    def appdir
      return HOMEBREW_CASK_APPDIR_PLACEHOLDER if Cask.generating_hash?

      cask.config.appdir
    end
  end
end
