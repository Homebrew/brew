# frozen_string_literal: true

module Bundler
  class Settings
    autoload :Mirror,  File.expand_path("mirror", __dir__)
    autoload :Mirrors, File.expand_path("mirror", __dir__)
    autoload :Validator, File.expand_path("settings/validator", __dir__)

    BOOL_KEYS = %w[
      allow_deployment_source_credential_changes
      allow_offline_install
      auto_clean_without_path
      auto_install
      cache_all
      cache_all_platforms
      clean
      default_install_uses_path
      deployment
      disable_checksum_validation
      disable_exec_load
      disable_local_branch_check
      disable_local_revision_check
      disable_shared_gems
      disable_version_check
      force_ruby_platform
      forget_cli_options
      frozen
      gem.changelog
      gem.coc
      gem.mit
      git.allow_insecure
      global_gem_cache
      ignore_messages
      init_gems_rb
      inline
      no_install
      no_prune
      path_relative_to_cwd
      path.system
      plugins
      prefer_patch
      print_only_version_number
      setup_makes_kernel_gem_public
      silence_deprecations
      silence_root_warning
      suppress_install_using_messages
      update_requires_all_flag
    ].freeze

    NUMBER_KEYS = %w[
      jobs
      redirect
      retry
      ssl_verify_mode
      timeout
    ].freeze

    ARRAY_KEYS = %w[
      only
      with
      without
    ].freeze

    STRING_KEYS = %w[
      bin
      cache_path
      console
      gem.ci
      gem.github_username
      gem.linter
      gem.rubocop
      gem.test
      gemfile
      path
      shebang
      system_bindir
      trust-policy
    ].freeze

    DEFAULT_CONFIG = {
      "BUNDLE_SILENCE_DEPRECATIONS" => false,
      "BUNDLE_DISABLE_VERSION_CHECK" => true,
      "BUNDLE_PREFER_PATCH" => false,
      "BUNDLE_REDIRECT" => 5,
      "BUNDLE_RETRY" => 3,
      "BUNDLE_TIMEOUT" => 10,
    }.freeze

    def initialize(root = nil)
      @root            = root
      @local_config    = load_config(local_config_file)
      @env_config      = ENV.to_h.select {|key, _value| key =~ /\ABUNDLE_.+/ }
      @global_config   = load_config(global_config_file)
      @temporary       = {}
    end

    def [](name)
      key = key_for(name)
      value = configs.values.map {|config| config[key] }.compact.first

      converted_value(value, name)
    end

    def set_command_option(key, value)
      if Bundler.feature_flag.forget_cli_options?
        temporary(key => value)
        value
      else
        set_local(key, value)
      end
    end

    def set_command_option_if_given(key, value)
      return if value.nil?
      set_command_option(key, value)
    end

    def set_local(key, value)
      local_config_file || raise(GemfileNotFound, "Could not locate Gemfile")

      set_key(key, value, @local_config, local_config_file)
    end

    def temporary(update)
      existing = Hash[update.map {|k, _| [k, @temporary[key_for(k)]] }]
      update.each do |k, v|
        set_key(k, v, @temporary, nil)
      end
      return unless block_given?
      begin
        yield
      ensure
        existing.each {|k, v| set_key(k, v, @temporary, nil) }
      end
    end

    def set_global(key, value)
      set_key(key, value, @global_config, global_config_file)
    end

    def all
      keys = @temporary.keys | @global_config.keys | @local_config.keys | @env_config.keys

      keys.map do |key|
        key.sub(/^BUNDLE_/, "").gsub(/___/, "-").gsub(/__/, ".").downcase
      end.sort
    end

    def local_overrides
      repos = {}
      all.each do |k|
        repos[$'] = self[k] if k =~ /^local\./
      end
      repos
    end

    def mirror_for(uri)
      if uri.is_a?(String)
        require_relative "vendored_uri"
        uri = Bundler::URI(uri)
      end

      gem_mirrors.for(uri.to_s).uri
    end

    def credentials_for(uri)
      self[uri.to_s] || self[uri.host]
    end

    def gem_mirrors
      all.inject(Mirrors.new) do |mirrors, k|
        mirrors.parse(k, self[k]) if k.start_with?("mirror.")
        mirrors
      end
    end

    def locations(key)
      key = key_for(key)
      configs.keys.inject({}) do |partial_locations, level|
        value_on_level = configs[level][key]
        partial_locations[level] = value_on_level unless value_on_level.nil?
        partial_locations
      end
    end

    def pretty_values_for(exposed_key)
      key = key_for(exposed_key)

      locations = []

      if value = @temporary[key]
        locations << "Set for the current command: #{printable_value(value, exposed_key).inspect}"
      end

      if value = @local_config[key]
        locations << "Set for your local app (#{local_config_file}): #{printable_value(value, exposed_key).inspect}"
      end

      if value = @env_config[key]
        locations << "Set via #{key}: #{printable_value(value, exposed_key).inspect}"
      end

      if value = @global_config[key]
        locations << "Set for the current user (#{global_config_file}): #{printable_value(value, exposed_key).inspect}"
      end

      return ["You have not configured a value for `#{exposed_key}`"] if locations.empty?
      locations
    end

    def processor_count
      require "etc"
      Etc.nprocessors
    rescue StandardError
      1
    end

    # for legacy reasons, in Bundler 2, we do not respect :disable_shared_gems
    def path
      configs.each do |_level, settings|
        path = value_for("path", settings)
        path = "vendor/bundle" if value_for("deployment", settings) && path.nil?
        path_system = value_for("path.system", settings)
        disabled_shared_gems = value_for("disable_shared_gems", settings)
        next if path.nil? && path_system.nil? && disabled_shared_gems.nil?
        system_path = path_system || (disabled_shared_gems == false)
        return Path.new(path, system_path)
      end

      Path.new(nil, false)
    end

    Path = Struct.new(:explicit_path, :system_path) do
      def path
        path = base_path
        path = File.join(path, Bundler.ruby_scope) unless use_system_gems?
        path
      end

      def use_system_gems?
        return true if system_path
        return false if explicit_path
        !Bundler.feature_flag.default_install_uses_path?
      end

      def base_path
        path = explicit_path
        path ||= ".bundle" unless use_system_gems?
        path ||= Bundler.rubygems.gem_dir
        path
      end

      def base_path_relative_to_pwd
        base_path = Pathname.new(self.base_path)
        expanded_base_path = base_path.expand_path(Bundler.root)
        relative_path = expanded_base_path.relative_path_from(Pathname.pwd)
        if relative_path.to_s.start_with?("..")
          relative_path = base_path if base_path.absolute?
        else
          relative_path = Pathname.new(File.join(".", relative_path))
        end
        relative_path
      rescue ArgumentError
        expanded_base_path
      end

      def validate!
        return unless explicit_path && system_path
        path = Bundler.settings.pretty_values_for(:path)
        path.unshift(nil, "path:") unless path.empty?
        system_path = Bundler.settings.pretty_values_for("path.system")
        system_path.unshift(nil, "path.system:") unless system_path.empty?
        disable_shared_gems = Bundler.settings.pretty_values_for(:disable_shared_gems)
        disable_shared_gems.unshift(nil, "disable_shared_gems:") unless disable_shared_gems.empty?
        raise InvalidOption,
          "Using a custom path while using system gems is unsupported.\n#{path.join("\n")}\n#{system_path.join("\n")}\n#{disable_shared_gems.join("\n")}"
      end
    end

    def allow_sudo?
      key = key_for(:path)
      path_configured = @temporary.key?(key) || @local_config.key?(key)
      !path_configured
    end

    def ignore_config?
      ENV["BUNDLE_IGNORE_CONFIG"]
    end

    def app_cache_path
      @app_cache_path ||= self[:cache_path] || "vendor/cache"
    end

    def validate!
      all.each do |raw_key|
        [@local_config, @env_config, @global_config].each do |settings|
          value = value_for(raw_key, settings)
          Validator.validate!(raw_key, value, settings.dup)
        end
      end
    end

    def key_for(key)
      self.class.key_for(key)
    end

    private

    def configs
      {
        :temporary => @temporary,
        :local => @local_config,
        :env => @env_config,
        :global => @global_config,
        :default => DEFAULT_CONFIG,
      }
    end

    def value_for(name, config)
      converted_value(config[key_for(name)], name)
    end

    def parent_setting_for(name)
      split_specific_setting_for(name)[0]
    end

    def specific_gem_for(name)
      split_specific_setting_for(name)[1]
    end

    def split_specific_setting_for(name)
      name.split(".")
    end

    def is_bool(name)
      BOOL_KEYS.include?(name.to_s) || BOOL_KEYS.include?(parent_setting_for(name.to_s))
    end

    def is_string(name)
      STRING_KEYS.include?(name.to_s) || name.to_s.start_with?("local.") || name.to_s.start_with?("mirror.") || name.to_s.start_with?("build.")
    end

    def to_bool(value)
      case value
      when nil, /\A(false|f|no|n|0|)\z/i, false
        false
      else
        true
      end
    end

    def is_num(key)
      NUMBER_KEYS.include?(key.to_s)
    end

    def is_array(key)
      ARRAY_KEYS.include?(key.to_s)
    end

    def is_credential(key)
      key == "gem.push_key"
    end

    def is_userinfo(value)
      value.include?(":")
    end

    def to_array(value)
      return [] unless value
      value.tr(" ", ":").split(":").map(&:to_sym)
    end

    def array_to_s(array)
      array = Array(array)
      return nil if array.empty?
      array.join(":").tr(" ", ":")
    end

    def set_key(raw_key, value, hash, file)
      raw_key = raw_key.to_s
      value = array_to_s(value) if is_array(raw_key)

      key = key_for(raw_key)

      return if hash[key] == value

      hash[key] = value
      hash.delete(key) if value.nil?

      Validator.validate!(raw_key, converted_value(value, raw_key), hash)

      return unless file
      SharedHelpers.filesystem_access(file) do |p|
        FileUtils.mkdir_p(p.dirname)
        require_relative "yaml_serializer"
        p.open("w") {|f| f.write(YAMLSerializer.dump(hash)) }
      end
    end

    def converted_value(value, key)
      if is_array(key)
        to_array(value)
      elsif value.nil?
        nil
      elsif is_bool(key) || value == "false"
        to_bool(value)
      elsif is_num(key)
        value.to_i
      else
        value.to_s
      end
    end

    def printable_value(value, key)
      converted = converted_value(value, key)
      return converted unless converted.is_a?(String)

      if is_string(key)
        converted
      elsif is_credential(key)
        "[REDACTED]"
      elsif is_userinfo(converted)
        username, pass = converted.split(":", 2)

        if pass == "x-oauth-basic"
          username = "[REDACTED]"
        else
          pass = "[REDACTED]"
        end

        [username, pass].join(":")
      else
        converted
      end
    end

    def global_config_file
      if ENV["BUNDLE_CONFIG"] && !ENV["BUNDLE_CONFIG"].empty?
        Pathname.new(ENV["BUNDLE_CONFIG"])
      elsif ENV["BUNDLE_USER_CONFIG"] && !ENV["BUNDLE_USER_CONFIG"].empty?
        Pathname.new(ENV["BUNDLE_USER_CONFIG"])
      elsif ENV["BUNDLE_USER_HOME"] && !ENV["BUNDLE_USER_HOME"].empty?
        Pathname.new(ENV["BUNDLE_USER_HOME"]).join("config")
      elsif Bundler.rubygems.user_home && !Bundler.rubygems.user_home.empty?
        Pathname.new(Bundler.rubygems.user_home).join(".bundle/config")
      end
    end

    def local_config_file
      Pathname.new(@root).join("config") if @root
    end

    def load_config(config_file)
      return {} if !config_file || ignore_config?
      SharedHelpers.filesystem_access(config_file, :read) do |file|
        valid_file = file.exist? && !file.size.zero?
        return {} unless valid_file
        require_relative "yaml_serializer"
        YAMLSerializer.load(file.read).inject({}) do |config, (k, v)|
          new_k = k

          if k.include?("-")
            Bundler.ui.warn "Your #{file} config includes `#{k}`, which contains the dash character (`-`).\n" \
              "This is deprecated, because configuration through `ENV` should be possible, but `ENV` keys cannot include dashes.\n" \
              "Please edit #{file} and replace any dashes in configuration keys with a triple underscore (`___`)."

            new_k = k.gsub("-", "___")
          end

          config[new_k] = v
          config
        end
      end
    end

    PER_URI_OPTIONS = %w[
      fallback_timeout
    ].freeze

    NORMALIZE_URI_OPTIONS_PATTERN =
      /
        \A
        (\w+\.)? # optional prefix key
        (https?.*?) # URI
        (\.#{Regexp.union(PER_URI_OPTIONS)})? # optional suffix key
        \z
      /ix.freeze

    def self.key_for(key)
      key = normalize_uri(key).to_s if key.is_a?(String) && key.start_with?("http", "mirror.http")
      key = key.to_s.gsub(".", "__").gsub("-", "___").upcase
      "BUNDLE_#{key}"
    end

    # TODO: duplicates Rubygems#normalize_uri
    # TODO: is this the correct place to validate mirror URIs?
    def self.normalize_uri(uri)
      uri = uri.to_s
      if uri =~ NORMALIZE_URI_OPTIONS_PATTERN
        prefix = $1
        uri = $2
        suffix = $3
      end
      uri = "#{uri}/" unless uri.end_with?("/")
      require_relative "vendored_uri"
      uri = Bundler::URI(uri)
      unless uri.absolute?
        raise ArgumentError, format("Gem sources must be absolute. You provided '%s'.", uri)
      end
      "#{prefix}#{uri}#{suffix}"
    end
  end
end
