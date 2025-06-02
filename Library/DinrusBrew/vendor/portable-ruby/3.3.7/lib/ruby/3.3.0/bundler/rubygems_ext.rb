# frozen_string_literal: true

require "rubygems" unless defined?(Gem)

# We can't let `Gem::Source` be autoloaded in the `Gem::Specification#source`
# redefinition below, so we need to load it upfront. The reason is that if
# Bundler monkeypatches are loaded before RubyGems activates an executable (for
# example, through `ruby -rbundler -S irb`), gem activation might end up calling
# the redefined `Gem::Specification#source` and triggering the `Gem::Source`
# autoload. That would result in requiring "rubygems/source" inside another
# require, which would trigger a monitor error and cause the `autoload` to
# eventually fail. A better solution is probably to completely avoid autoloading
# `Gem::Source` from the redefined `Gem::Specification#source`.
require "rubygems/source"

# Cherry-pick fixes to `Gem.ruby_version` to be useful for modern Bundler
# versions and ignore patchlevels
# (https://github.com/rubygems/rubygems/pull/5472,
# https://github.com/rubygems/rubygems/pull/5486). May be removed once RubyGems
# 3.3.12 support is dropped.
unless Gem.ruby_version.to_s == RUBY_VERSION || RUBY_PATCHLEVEL == -1
  Gem.instance_variable_set(:@ruby_version, Gem::Version.new(RUBY_VERSION))
end

module Gem
  # Can be removed once RubyGems 3.5.11 support is dropped
  unless Gem.respond_to?(:freebsd_platform?)
    def self.freebsd_platform?
      RbConfig::CONFIG["host_os"].to_s.include?("bsd")
    end
  end

  # Can be removed once RubyGems 3.5.18 support is dropped
  unless Gem.respond_to?(:open_file_with_lock)
    class << self
      remove_method :open_file_with_flock if Gem.respond_to?(:open_file_with_flock)

      def open_file_with_flock(path, &block)
        # read-write mode is used rather than read-only in order to support NFS
        mode = IO::RDWR | IO::APPEND | IO::CREAT | IO::BINARY
        mode |= IO::SHARE_DELETE if IO.const_defined?(:SHARE_DELETE)

        File.open(path, mode) do |io|
          begin
            io.flock(File::LOCK_EX)
          rescue Errno::ENOSYS, Errno::ENOTSUP
          end
          yield io
        end
      end

      def open_file_with_lock(path, &block)
        file_lock = "#{path}.lock"
        open_file_with_flock(file_lock, &block)
      ensure
        FileUtils.rm_f file_lock
      end
    end
  end

  require "rubygems/specification"

  # Can be removed once RubyGems 3.5.14 support is dropped
  VALIDATES_FOR_RESOLUTION = Specification.new.respond_to?(:validate_for_resolution).freeze

  # Can be removed once RubyGems 3.3.15 support is dropped
  FLATTENS_REQUIRED_PATHS = Specification.new.respond_to?(:flatten_require_paths).freeze

  class Specification
    # Can be removed once RubyGems 3.5.15 support is dropped
    correct_array_attributes = @@default_value.select {|_k,v| v.is_a?(Array) }.keys
    unless @@array_attributes == correct_array_attributes
      @@array_attributes = correct_array_attributes # rubocop:disable Style/ClassVars
    end

    require_relative "match_metadata"
    require_relative "match_platform"

    include ::Bundler::MatchMetadata
    include ::Bundler::MatchPlatform

    attr_accessor :remote, :location, :relative_loaded_from

    remove_method :source
    attr_writer :source
    def source
      (defined?(@source) && @source) || Gem::Source::Installed.new
    end

    alias_method :rg_full_gem_path, :full_gem_path
    alias_method :rg_loaded_from,   :loaded_from

    def full_gem_path
      if source.respond_to?(:root)
        File.expand_path(File.dirname(loaded_from), source.root)
      else
        rg_full_gem_path
      end
    end

    def loaded_from
      if relative_loaded_from
        source.path.join(relative_loaded_from).to_s
      else
        rg_loaded_from
      end
    end

    def load_paths
      full_require_paths
    end

    alias_method :rg_extension_dir, :extension_dir
    def extension_dir
      # following instance variable is already used in original method
      # and that is the reason to prefix it with bundler_ and add rubocop exception
      @bundler_extension_dir ||= if source.respond_to?(:extension_dir_name) # rubocop:disable Naming/MemoizedInstanceVariableName
        unique_extension_dir = [source.extension_dir_name, File.basename(full_gem_path)].uniq.join("-")
        File.expand_path(File.join(extensions_dir, unique_extension_dir))
      else
        rg_extension_dir
      end
    end

    remove_method :gem_dir
    def gem_dir
      full_gem_path
    end

    unless const_defined?(:LATEST_RUBY_WITHOUT_PATCH_VERSIONS)
      LATEST_RUBY_WITHOUT_PATCH_VERSIONS = Gem::Version.new("2.1")

      alias_method :rg_required_ruby_version=, :required_ruby_version=
      def required_ruby_version=(req)
        self.rg_required_ruby_version = req

        @required_ruby_version.requirements.map! do |op, v|
          if v >= LATEST_RUBY_WITHOUT_PATCH_VERSIONS && v.release.segments.size == 4
            [op == "~>" ? "=" : op, Gem::Version.new(v.segments.tap {|s| s.delete_at(3) }.join("."))]
          else
            [op, v]
          end
        end
      end
    end

    def groups
      @groups ||= []
    end

    def git_version
      return unless loaded_from && source.is_a?(Bundler::Source::Git)
      " #{source.revision[0..6]}"
    end

    def to_gemfile(path = nil)
      gemfile = String.new("source 'https://rubygems.org'\n")
      gemfile << dependencies_to_gemfile(nondevelopment_dependencies)
      unless development_dependencies.empty?
        gemfile << "\n"
        gemfile << dependencies_to_gemfile(development_dependencies, :development)
      end
      gemfile
    end

    def nondevelopment_dependencies
      dependencies - development_dependencies
    end

    def deleted_gem?
      !default_gem? && !File.directory?(full_gem_path)
    end

    unless VALIDATES_FOR_RESOLUTION
      def validate_for_resolution
        SpecificationPolicy.new(self).validate_for_resolution
      end
    end

    unless FLATTENS_REQUIRED_PATHS
      def flatten_require_paths
        return unless raw_require_paths.first.is_a?(Array)

        warn "#{name} #{version} includes a gemspec with `require_paths` set to an array of arrays. Newer versions of this gem might've already fixed this"
        raw_require_paths.flatten!
      end

      class << self
        module RequirePathFlattener
          def from_yaml(input)
            spec = super(input)
            spec.flatten_require_paths
            spec
          end
        end

        prepend RequirePathFlattener
      end
    end

    private

    def dependencies_to_gemfile(dependencies, group = nil)
      gemfile = String.new
      if dependencies.any?
        gemfile << "group :#{group} do\n" if group
        dependencies.each do |dependency|
          gemfile << "  " if group
          gemfile << %(gem "#{dependency.name}")
          req = dependency.requirements_list.first
          gemfile << %(, "#{req}") if req
          gemfile << "\n"
        end
        gemfile << "end\n" if group
      end
      gemfile
    end
  end

  unless VALIDATES_FOR_RESOLUTION
    class SpecificationPolicy
      def validate_for_resolution
        validate_required!
      end
    end
  end

  module BetterPermissionError
    def data
      super
    rescue Errno::EACCES
      raise Bundler::PermissionError.new(loaded_from, :read)
    end
  end

  require "rubygems/stub_specification"

  class StubSpecification
    prepend BetterPermissionError
  end

  class Dependency
    require_relative "force_platform"

    include ::Bundler::ForcePlatform

    attr_reader :force_ruby_platform

    attr_accessor :source, :groups

    alias_method :eql?, :==

    unless method_defined?(:encode_with, false)
      def encode_with(coder)
        [:@name, :@requirement, :@type, :@prerelease, :@version_requirements].each do |ivar|
          coder[ivar.to_s.sub(/^@/, "")] = instance_variable_get(ivar)
        end
      end
    end

    def to_lock
      out = String.new("  #{name}")
      unless requirement.none?
        reqs = requirement.requirements.map {|o, v| "#{o} #{v}" }.sort.reverse
        out << " (#{reqs.join(", ")})"
      end
      out
    end

    if Gem.rubygems_version < Gem::Version.new("3.5.22")
      module FilterIgnoredSpecs
        def matching_specs(platform_only = false)
          super.reject(&:ignored?)
        end
      end

      prepend FilterIgnoredSpecs
    end
  end

  # Requirements using lambda operator differentiate trailing zeros since rubygems 3.2.6
  if Gem::Requirement.new("~> 2.0").hash == Gem::Requirement.new("~> 2.0.0").hash
    class Requirement
      module CorrectHashForLambdaOperator
        def hash
          if requirements.any? {|r| r.first == "~>" }
            requirements.map {|r| r.first == "~>" ? [r[0], r[1].to_s] : r }.sort.hash
          else
            super
          end
        end
      end

      prepend CorrectHashForLambdaOperator
    end
  end

  require "rubygems/platform"

  class Platform
    JAVA  = Gem::Platform.new("java")
    MSWIN = Gem::Platform.new("mswin32")
    MSWIN64 = Gem::Platform.new("mswin64")
    MINGW = Gem::Platform.new("x86-mingw32")
    X64_MINGW = [Gem::Platform.new("x64-mingw32"),
                 Gem::Platform.new("x64-mingw-ucrt")].freeze
    WINDOWS = [MSWIN, MSWIN64, MINGW, X64_MINGW].flatten.freeze
    X64_LINUX = Gem::Platform.new("x86_64-linux")
    X64_LINUX_MUSL = Gem::Platform.new("x86_64-linux-musl")

    if X64_LINUX === X64_LINUX_MUSL
      remove_method :===

      def ===(other)
        return nil unless Gem::Platform === other

        # universal-mingw32 matches x64-mingw-ucrt
        return true if (@cpu == "universal" || other.cpu == "universal") &&
                       @os.start_with?("mingw") && other.os.start_with?("mingw")

        # cpu
        ([nil,"universal"].include?(@cpu) || [nil, "universal"].include?(other.cpu) || @cpu == other.cpu ||
        (@cpu == "arm" && other.cpu.start_with?("armv"))) &&

          # os
          @os == other.os &&

          # version
          (
            (@os != "linux" && (@version.nil? || other.version.nil?)) ||
            (@os == "linux" && (normalized_linux_version_ext == other.normalized_linux_version_ext || ["musl#{@version}", "musleabi#{@version}", "musleabihf#{@version}"].include?(other.version))) ||
            @version == other.version
          )
      end

      # This is a copy of RubyGems 3.3.23 or higher `normalized_linux_method`.
      # Once only 3.3.23 is supported, we can use the method in RubyGems.
      def normalized_linux_version_ext
        return nil unless @version

        without_gnu_nor_abi_modifiers = @version.sub(/\Agnu/, "").sub(/eabi(hf)?\Z/, "")
        return nil if without_gnu_nor_abi_modifiers.empty?

        without_gnu_nor_abi_modifiers
      end
    end

    if RUBY_ENGINE == "truffleruby" && !defined?(REUSE_AS_BINARY_ON_TRUFFLERUBY)
      REUSE_AS_BINARY_ON_TRUFFLERUBY = %w[libv8 libv8-node sorbet-static].freeze
    end
  end

  Platform.singleton_class.module_eval do
    unless Platform.singleton_methods.include?(:match_spec?)
      def match_spec?(spec)
        match_gem?(spec.platform, spec.name)
      end

      def match_gem?(platform, gem_name)
        match_platforms?(platform, Gem.platforms)
      end
    end

    match_platforms_defined = Gem::Platform.respond_to?(:match_platforms?, true)

    if !match_platforms_defined || Gem::Platform.send(:match_platforms?, Gem::Platform::X64_LINUX_MUSL, [Gem::Platform::X64_LINUX])

      private

      remove_method :match_platforms? if match_platforms_defined

      def match_platforms?(platform, platforms)
        platforms.any? do |local_platform|
          platform.nil? ||
            local_platform == platform ||
            (local_platform != Gem::Platform::RUBY && platform =~ local_platform)
        end
      end
    end
  end

  # On universal Rubies, resolve the "universal" arch to the real CPU arch, without changing the extension directory.
  class BasicSpecification
    if /^universal\.(?<arch>.*?)-/ =~ (CROSS_COMPILING || RUBY_PLATFORM)
      local_platform = Platform.local
      if local_platform.cpu == "universal"
        ORIGINAL_LOCAL_PLATFORM = local_platform.to_s.freeze

        local_platform.cpu = if arch == "arm64e" # arm64e is only permitted for Apple system binaries
          "arm64"
        else
          arch
        end

        def extensions_dir
          @extensions_dir ||=
            Gem.default_ext_dir_for(base_dir) || File.join(base_dir, "extensions", ORIGINAL_LOCAL_PLATFORM, Gem.extension_api_version)
        end
      end
    end

    # Can be removed once RubyGems 3.5.22 support is dropped
    unless new.respond_to?(:ignored?)
      def ignored?
        return @ignored unless @ignored.nil?

        @ignored = missing_extensions?
      end
    end
  end

  require "rubygems/name_tuple"

  class NameTuple
    # Versions of RubyGems before about 3.5.0 don't to_s the platform.
    unless Gem::NameTuple.new("a", Gem::Version.new("1"), Gem::Platform.new("x86_64-linux")).platform.is_a?(String)
      alias_method :initialize_with_platform, :initialize

      def initialize(name, version, platform=Gem::Platform::RUBY)
        if Gem::Platform === platform
          initialize_with_platform(name, version, platform.to_s)
        else
          initialize_with_platform(name, version, platform)
        end
      end
    end

    def lock_name
      if platform == Gem::Platform::RUBY
        "#{name} (#{version})"
      else
        "#{name} (#{version}-#{platform})"
      end
    end
  end

  unless Gem.rubygems_version >= Gem::Version.new("3.5.19")
    class Resolver::ActivationRequest
      remove_method :installed?

      def installed?
        case @spec
        when Gem::Resolver::VendorSpecification then
          true
        else
          this_spec = full_spec

          Gem::Specification.any? do |s|
            s == this_spec && s.base_dir == this_spec.base_dir
          end
        end
      end
    end
  end
end
