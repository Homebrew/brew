# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

# Settings for the build environment.
class BuildEnvironment
  sig { params(settings: Symbol).void }
  def initialize(*settings)
    @settings = Set.new(settings)
  end

  sig { params(args: T::Enumerable[Symbol]).returns(T.self_type) }
  def merge(*args)
    @settings.merge(*args)
    self
  end

  sig { params(option: Symbol).returns(T.self_type) }
  def <<(option)
    @settings << option
    self
  end

  sig { returns(T::Boolean) }
  def std?
    @settings.include? :std
  end

  # DSL for specifying build environment settings.
  module DSL
    # Initialise @env for each class which may use this DSL (e.g. each formula subclass).
    # `env` may never be called and it needs to be initialised before the class is frozen.
    def inherited(child)
      super
      child.instance_eval do
        @env = BuildEnvironment.new
      end
    end

    sig { params(settings: Symbol).returns(BuildEnvironment) }
    def env(*settings)
      @env.merge(settings)
    end
  end

  KEYS = %w[
    CC CXX LD OBJC OBJCXX
    HOMEBREW_CC HOMEBREW_CXX
    CFLAGS CXXFLAGS CPPFLAGS LDFLAGS SDKROOT MAKEFLAGS
    CMAKE_PREFIX_PATH CMAKE_INCLUDE_PATH CMAKE_LIBRARY_PATH CMAKE_FRAMEWORK_PATH
    MACOSX_DEPLOYMENT_TARGET PKG_CONFIG_PATH PKG_CONFIG_LIBDIR
    HOMEBREW_DEBUG HOMEBREW_MAKE_JOBS HOMEBREW_VERBOSE
    all_proxy ftp_proxy http_proxy https_proxy no_proxy
    HOMEBREW_SVN HOMEBREW_GIT
    HOMEBREW_SDKROOT
    MAKE GIT CPP
    ACLOCAL_PATH PATH CPATH
    LD_LIBRARY_PATH LD_RUN_PATH LD_PRELOAD LIBRARY_PATH
  ].freeze
  private_constant :KEYS

  sig { params(env: T::Hash[String, T.nilable(T.any(String, Pathname))]).returns(T::Array[String]) }
  def self.keys(env)
    KEYS & env.keys
  end

  sig { params(env: T::Hash[String, T.nilable(T.any(String, Pathname))], out: IO).void }
  def self.dump(env, out = $stdout)
    keys = self.keys(env)
    keys -= %w[CC CXX OBJC OBJCXX] if env["CC"] == env["HOMEBREW_CC"]

    keys.each do |key|
      value = env.fetch(key)

      string = "#{key}: #{value}"
      case key
      when "CC", "CXX", "LD"
        string << " => #{Pathname.new(value).realpath}" if value.present? && File.symlink?(value)
      end
      string.freeze
      out.puts string
    end
  end
end
