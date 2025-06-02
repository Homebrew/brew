# frozen_string_literal: true

module Gem
  DEFAULT_HOST = "https://rubygems.org"

  @post_install_hooks ||= []
  @done_installing_hooks ||= []
  @post_uninstall_hooks ||= []
  @pre_uninstall_hooks  ||= []
  @pre_install_hooks    ||= []

  ##
  # An Array of the default sources that come with RubyGems

  def self.default_sources
    %w[https://rubygems.org/]
  end

  ##
  # Default spec directory path to be used if an alternate value is not
  # specified in the environment

  def self.default_spec_cache_dir
    default_spec_cache_dir = File.join Gem.user_home, ".gem", "specs"

    unless File.exist?(default_spec_cache_dir)
      default_spec_cache_dir = File.join Gem.cache_home, "gem", "specs"
    end

    default_spec_cache_dir
  end

  ##
  # Default home directory path to be used if an alternate value is not
  # specified in the environment

  def self.default_dir
    @default_dir ||= File.join(RbConfig::CONFIG["rubylibprefix"], "gems", RbConfig::CONFIG["ruby_version"])
  end

  ##
  # Returns binary extensions dir for specified RubyGems base dir or nil
  # if such directory cannot be determined.
  #
  # By default, the binary extensions are located side by side with their
  # Ruby counterparts, therefore nil is returned

  def self.default_ext_dir_for(base_dir)
    nil
  end

  ##
  # Paths where RubyGems' .rb files and bin files are installed

  def self.default_rubygems_dirs
    nil # default to standard layout
  end

  ##
  # Path to specification files of default gems.

  def self.default_specifications_dir
    @default_specifications_dir ||= File.join(Gem.default_dir, "specifications", "default")
  end

  ##
  # Finds the user's home directory.
  #--
  # Some comments from the ruby-talk list regarding finding the home
  # directory:
  #
  #   I have HOME, USERPROFILE and HOMEDRIVE + HOMEPATH. Ruby seems
  #   to be depending on HOME in those code samples. I propose that
  #   it should fallback to USERPROFILE and HOMEDRIVE + HOMEPATH (at
  #   least on Win32).
  #++
  #--
  #
  #++

  def self.find_home
    Dir.home.dup
  rescue StandardError
    if Gem.win_platform?
      File.expand_path File.join(ENV["HOMEDRIVE"] || ENV["SystemDrive"], "/")
    else
      File.expand_path "/"
    end
  end

  private_class_method :find_home

  ##
  # The home directory for the user.

  def self.user_home
    @user_home ||= find_home
  end

  ##
  # Path for gems in the user's home directory

  def self.user_dir
    gem_dir = File.join(Gem.user_home, ".gem")
    gem_dir = File.join(Gem.data_home, "gem") unless File.exist?(gem_dir)
    parts = [gem_dir, ruby_engine]
    parts << RbConfig::CONFIG["ruby_version"] unless RbConfig::CONFIG["ruby_version"].empty?
    File.join parts
  end

  ##
  # The path to standard location of the user's configuration directory.

  def self.config_home
    @config_home ||= ENV["XDG_CONFIG_HOME"] || File.join(Gem.user_home, ".config")
  end

  ##
  # Finds the user's config file

  def self.find_config_file
    gemrc = File.join Gem.user_home, ".gemrc"
    if File.exist? gemrc
      gemrc
    else
      File.join Gem.config_home, "gem", "gemrc"
    end
  end

  ##
  # The path to standard location of the user's .gemrc file.

  def self.config_file
    @config_file ||= find_config_file
  end

  ##
  # The path to standard location of the user's state file.

  def self.state_file
    @state_file ||= File.join(Gem.state_home, "gem", "last_update_check")
  end

  ##
  # The path to standard location of the user's cache directory.

  def self.cache_home
    @cache_home ||= ENV["XDG_CACHE_HOME"] || File.join(Gem.user_home, ".cache")
  end

  ##
  # The path to standard location of the user's data directory.

  def self.data_home
    @data_home ||= ENV["XDG_DATA_HOME"] || File.join(Gem.user_home, ".local", "share")
  end

  ##
  # The path to standard location of the user's state directory.

  def self.state_home
    @state_home ||= ENV["XDG_STATE_HOME"] || File.join(Gem.user_home, ".local", "state")
  end

  ##
  # How String Gem paths should be split.  Overridable for esoteric platforms.

  def self.path_separator
    File::PATH_SEPARATOR
  end

  ##
  # Default gem load path

  def self.default_path
    path = []
    path << user_dir if user_home && File.exist?(user_home)
    path << default_dir
    path << vendor_dir if vendor_dir && File.directory?(vendor_dir)
    path
  end

  ##
  # Deduce Ruby's --program-prefix and --program-suffix from its install name

  def self.default_exec_format
    exec_format = begin
                    RbConfig::CONFIG["ruby_install_name"].sub("ruby", "%s")
                  rescue StandardError
                    "%s"
                  end

    unless exec_format.include?("%s")
      raise Gem::Exception,
        "[BUG] invalid exec_format #{exec_format.inspect}, no %s"
    end

    exec_format
  end

  ##
  # The default directory for binaries

  def self.default_bindir
    RbConfig::CONFIG["bindir"]
  end

  def self.ruby_engine
    RUBY_ENGINE
  end

  ##
  # The default signing key path

  def self.default_key_path
    default_key_path = File.join Gem.user_home, ".gem", "gem-private_key.pem"

    unless File.exist?(default_key_path)
      default_key_path = File.join Gem.data_home, "gem", "gem-private_key.pem"
    end

    default_key_path
  end

  ##
  # The default signing certificate chain path

  def self.default_cert_path
    default_cert_path = File.join Gem.user_home, ".gem", "gem-public_cert.pem"

    unless File.exist?(default_cert_path)
      default_cert_path = File.join Gem.data_home, "gem", "gem-public_cert.pem"
    end

    default_cert_path
  end

  ##
  # Enables automatic installation into user directory

  def self.default_user_install # :nodoc:
    if !ENV.key?("GEM_HOME") && (File.exist?(Gem.dir) && !File.writable?(Gem.dir))
      Gem.ui.say "Defaulting to user installation because default installation directory (#{Gem.dir}) is not writable."
      return true
    end

    false
  end

  ##
  # Install extensions into lib as well as into the extension directory.

  def self.install_extension_in_lib # :nodoc:
    true
  end

  ##
  # Directory where vendor gems are installed.

  def self.vendor_dir # :nodoc:
    if vendor_dir = ENV["GEM_VENDOR"]
      return vendor_dir.dup
    end

    return nil unless RbConfig::CONFIG.key? "vendordir"

    File.join RbConfig::CONFIG["vendordir"], "gems",
              RbConfig::CONFIG["ruby_version"]
  end

  ##
  # Default options for gem commands for Ruby packagers.
  #
  # The options here should be structured as an array of string "gem"
  # command names as keys and a string of the default options as values.
  #
  # Example:
  #
  # def self.operating_system_defaults
  #   {
  #       'install' => '--no-rdoc --no-ri --env-shebang',
  #       'update' => '--no-rdoc --no-ri --env-shebang'
  #   }
  # end

  def self.operating_system_defaults
    {}
  end

  ##
  # Default options for gem commands for Ruby implementers.
  #
  # The options here should be structured as an array of string "gem"
  # command names as keys and a string of the default options as values.
  #
  # Example:
  #
  # def self.platform_defaults
  #   {
  #       'install' => '--no-rdoc --no-ri --env-shebang',
  #       'update' => '--no-rdoc --no-ri --env-shebang'
  #   }
  # end

  def self.platform_defaults
    {}
  end
end
