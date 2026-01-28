# typed: true  # rubocop:disable Sorbet/StrictSigil
# frozen_string_literal: true

# Never `require` anything in this file (except English). It needs to be able to
# work as the first item in `brew.rb` so we can load gems with Bundler when
# needed before anything else is loaded (e.g. `json`).

Homebrew::FastBootRequire.from_rubylibdir("English")

module Homebrew
  # Bump this whenever a committed vendored gem is later added to or exclusion removed from gitignore.
  # This will trigger it to reinstall properly if `brew install-bundler-gems` needs it.
  VENDOR_VERSION = 7
  private_constant :VENDOR_VERSION

  RUBY_BUNDLE_VENDOR_DIRECTORY = (HOMEBREW_LIBRARY_PATH/"vendor/bundle/ruby").freeze
  private_constant :RUBY_BUNDLE_VENDOR_DIRECTORY

  # This is tracked across Ruby versions.
  GEM_GROUPS_FILE = (RUBY_BUNDLE_VENDOR_DIRECTORY/".homebrew_gem_groups").freeze
  private_constant :GEM_GROUPS_FILE

  # This is tracked per Ruby version.
  VENDOR_VERSION_FILE = (
    RUBY_BUNDLE_VENDOR_DIRECTORY/"#{RbConfig::CONFIG["ruby_version"]}/.homebrew_vendor_version"
  ).freeze
  private_constant :VENDOR_VERSION_FILE

  def self.gemfile
    File.join(ENV.fetch("HOMEBREW_LIBRARY"), "Homebrew", "Gemfile")
  end
  private_class_method :gemfile

  def self.bundler_definition
    @bundler_definition ||= Bundler::Definition.build(Bundler.default_gemfile, Bundler.default_lockfile, false)
  end
  private_class_method :bundler_definition

  def self.valid_gem_groups
    require "bundler"

    Bundler.with_unbundled_env do
      ENV["BUNDLE_GEMFILE"] = gemfile
      groups = bundler_definition.groups
      groups.delete(:default)
      groups.map(&:to_s)
    end
  end

  def self.ruby_bindir
    "#{RbConfig::CONFIG["prefix"]}/bin"
  end

  def self.ohai_if_defined(message)
    if defined?(ohai)
      ohai message
    else
      $stderr.puts "==> #{message}"
    end
  end

  def self.opoo_if_defined(message)
    if defined?(opoo)
      opoo message
    else
      $stderr.puts "Warning: #{message}"
    end
  end

  def self.odie_if_defined(message)
    if defined?(odie)
      odie message
    else
      $stderr.puts "Error: #{message}"
      exit 1
    end
  end

  def self.setup_gem_environment!(setup_path: true)
    require "rubygems"
    raise "RubyGems too old!" if Gem::Version.new(Gem::VERSION) < Gem::Version.new("2.2.0")

    ENV["BUNDLER_NO_OLD_RUBYGEMS_WARNING"] = "1"

    # Match where our bundler gems are.
    gem_home = "#{RUBY_BUNDLE_VENDOR_DIRECTORY}/#{RbConfig::CONFIG["ruby_version"]}"
    homebrew_cache = ENV.fetch("HOMEBREW_CACHE", nil)
    gem_cache = "#{homebrew_cache}/gem-spec-cache" if homebrew_cache

    Gem.paths = {
      "GEM_HOME"       => gem_home,
      "GEM_PATH"       => gem_home,
      "GEM_SPEC_CACHE" => gem_cache,
    }.compact

    # Set TMPDIR so Xcode's `make` doesn't fall back to `/var/tmp/`,
    # which may be not user-writable.
    ENV["TMPDIR"] = ENV.fetch("HOMEBREW_TEMP", nil)

    return unless setup_path

    # Add necessary Ruby and Gem binary directories to `PATH`.
    paths = ENV.fetch("PATH").split(":")
    paths.unshift(ruby_bindir) unless paths.include?(ruby_bindir)
    paths.unshift(Gem.bindir) unless paths.include?(Gem.bindir)
    ENV["PATH"] = paths.compact.join(":")

    # Set envs so the above binaries can be invoked.
    # We don't do this unless requested as some formulae may invoke system Ruby instead of ours.
    ENV["GEM_HOME"] = gem_home
    ENV["GEM_PATH"] = gem_home
    ENV["GEM_SPEC_CACHE"] = gem_cache if gem_cache
  end

  def self.install_gem!(name, version: nil, setup_gem_environment: true)
    setup_gem_environment! if setup_gem_environment

    specs = Gem::Specification.find_all_by_name(name, version)

    if specs.empty?
      ohai_if_defined "Installing '#{name}' gem"
      # `document: []` is equivalent to --no-document
      # `build_args: []` stops ARGV being used as a default
      # `env_shebang: true` makes shebangs generic to allow switching between system and Portable Ruby
      specs = Gem.install name, version, document: [], build_args: [], env_shebang: true
    end

    specs += specs.flat_map(&:runtime_dependencies)
                  .flat_map(&:to_specs)

    # Add the specs to the $LOAD_PATH.
    specs.each do |spec|
      spec.require_paths.each do |path|
        full_path = File.join(spec.full_gem_path, path)
        $LOAD_PATH.unshift full_path unless $LOAD_PATH.include?(full_path)
      end
    end
  rescue Gem::UnsatisfiableDependencyError
    odie_if_defined "failed to install the '#{name}' gem."
  end

  def self.install_gem_setup_path!(name, version: nil, executable: name, setup_gem_environment: true)
    install_gem!(name, version:, setup_gem_environment:)
    return if find_in_path(executable)

    odie_if_defined <<~EOS
      the '#{name}' gem is installed but couldn't find '#{executable}' in the PATH:
        #{ENV.fetch("PATH")}
    EOS
  end

  def self.find_in_path(executable)
    ENV.fetch("PATH").split(":").find do |path|
      File.executable?(File.join(path, executable))
    end
  end
  private_class_method :find_in_path

  def self.user_gem_groups
    @user_gem_groups ||= if GEM_GROUPS_FILE.exist?
      GEM_GROUPS_FILE.readlines(chomp: true)
    else
      []
    end
  end
  private_class_method :user_gem_groups

  def self.write_user_gem_groups(groups)
    return if @user_gem_groups == groups && GEM_GROUPS_FILE.exist?

    # Write the file atomically, in case we're working parallel
    require "tempfile"
    tmpfile = Tempfile.new([GEM_GROUPS_FILE.basename.to_s, "~"], GEM_GROUPS_FILE.dirname)
    path = tmpfile.path
    return if path.nil?

    require "fileutils"
    begin
      FileUtils.chmod("+r", path)
      tmpfile.write(groups.join("\n"))
      tmpfile.close
      File.rename(path, GEM_GROUPS_FILE)
    ensure
      tmpfile.unlink
    end

    @user_gem_groups = groups
  end
  private_class_method :write_user_gem_groups

  def self.forget_user_gem_groups!
    GEM_GROUPS_FILE.truncate(0) if GEM_GROUPS_FILE.exist?
    @user_gem_groups = []
  end

  def self.user_vendor_version
    @user_vendor_version ||= if VENDOR_VERSION_FILE.exist?
      VENDOR_VERSION_FILE.read.to_i
    else
      0
    end
  end
  private_class_method :user_vendor_version

  def self.install_bundler_gems!(only_warn_on_failure: false, setup_path: true, groups: [])
    old_path = ENV.fetch("PATH", nil)
    old_gem_path = ENV.fetch("GEM_PATH", nil)
    old_gem_home = ENV.fetch("GEM_HOME", nil)
    old_gem_spec_cache = ENV.fetch("GEM_SPEC_CACHE", nil)
    old_bundle_gemfile = ENV.fetch("BUNDLE_GEMFILE", nil)
    old_bundle_with = ENV.fetch("BUNDLE_WITH", nil)
    old_bundle_frozen = ENV.fetch("BUNDLE_FROZEN", nil)

    invalid_groups = groups - valid_gem_groups
    raise ArgumentError, "Invalid gem groups: #{invalid_groups.join(", ")}" unless invalid_groups.empty?

    setup_gem_environment!
    # Tests should not modify the state of the repository.
    return if ENV["HOMEBREW_TESTS"]

    # Combine the passed groups with the ones stored in settings.
    groups |= (user_gem_groups & valid_gem_groups)
    groups.sort!

    if (homebrew_bundle_user_cache = ENV.fetch("HOMEBREW_BUNDLE_USER_CACHE", nil))
      ENV["BUNDLE_USER_CACHE"] = homebrew_bundle_user_cache
    end
    ENV["BUNDLE_GEMFILE"] = gemfile
    ENV["BUNDLE_WITH"] = groups.join(" ")
    ENV["BUNDLE_FROZEN"] = "true"

    if @bundle_installed_groups != groups
      bundle = File.join(find_in_path("bundle"), "bundle")
      bundle_check_output = `#{bundle} check 2>&1`
      bundle_check_failed = !$CHILD_STATUS.success?

      # for some reason sometimes the exit code lies so check the output too.
      bundle_install_required = bundle_check_failed || bundle_check_output.include?("Install missing gems")

      if user_vendor_version != VENDOR_VERSION
        # Check if the install is intact. This is useful if any gems are added to gitignore.
        # We intentionally map over everything and then call `any?` so that we remove the spec of each bad gem.
        specs = bundler_definition.resolve.materialize(bundler_definition.locked_dependencies)
        vendor_reinstall_required = specs.map do |spec|
          spec_file = "#{Gem.dir}/specifications/#{spec.full_name}.gemspec"
          next false unless File.exist?(spec_file)

          cache_file = "#{Gem.dir}/cache/#{spec.full_name}.gem"
          if File.exist?(cache_file)
            require "rubygems/package"
            package = Gem::Package.new(cache_file)

            package_install_intact = begin
              contents = package.contents

              # If the gem has contents, ensure we have every file installed it contains.
              contents&.all? do |gem_file|
                File.exist?("#{Gem.dir}/gems/#{spec.full_name}/#{gem_file}")
              end
            rescue Gem::Package::Error, Gem::Security::Exception
              # Malformed, assume broken
              File.unlink(cache_file)
              false
            end

            next false if package_install_intact
          end

          # Mark gem for reinstallation
          File.unlink(spec_file)
          true
        end.any?

        VENDOR_VERSION_FILE.dirname.mkpath
        VENDOR_VERSION_FILE.write(VENDOR_VERSION.to_s)

        bundle_install_required ||= vendor_reinstall_required
      end

      bundle_installed = if bundle_install_required
        Process.wait(fork do
          # Native build scripts fail if EUID != UID
          Process::UID.change_privilege(Process.euid) if Process.euid != Process.uid
          exec bundle, "install", out: :err
        end)
        if $CHILD_STATUS.success?
          Homebrew::Bootsnap.reset! if defined?(Homebrew::Bootsnap) # Gem install can run before Bootsnap loads
          true
        else
          message = <<~EOS
            failed to run `#{bundle} install`!
          EOS
          if only_warn_on_failure
            opoo_if_defined message
          else
            odie_if_defined message
          end
          false
        end
      elsif system bundle, "clean", out: :err # even if we have nothing to install, we may have removed gems
        true
      else
        message = <<~EOS
          failed to run `#{bundle} clean`!
        EOS
        if only_warn_on_failure
          opoo_if_defined message
        else
          odie_if_defined message
        end
        false
      end

      if bundle_installed
        write_user_gem_groups(groups)
        @bundle_installed_groups = groups
      end
    end

    setup_gem_environment!
  ensure
    unless setup_path
      # Reset the paths. We need to have at least temporarily changed them while invoking `bundle`.
      ENV["PATH"] = old_path
      ENV["GEM_PATH"] = old_gem_path
      ENV["GEM_HOME"] = old_gem_home
      ENV["GEM_SPEC_CACHE"] = old_gem_spec_cache
      ENV["BUNDLE_GEMFILE"] = old_bundle_gemfile
      ENV["BUNDLE_WITH"] = old_bundle_with
      ENV["BUNDLE_FROZEN"] = old_bundle_frozen
    end
  end
end
