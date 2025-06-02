# frozen_string_literal: true

require "rubygems/dependency"
require_relative "shared_helpers"
require_relative "rubygems_ext"

module Bundler
  class Dependency < Gem::Dependency
    attr_reader :autorequire
    attr_reader :groups, :platforms, :gemfile, :path, :git, :github, :branch, :ref, :glob

    ALL_RUBY_VERSIONS = (18..27).to_a.concat((30..34).to_a).freeze
    PLATFORM_MAP = {
      ruby: [Gem::Platform::RUBY, ALL_RUBY_VERSIONS],
      mri: [Gem::Platform::RUBY, ALL_RUBY_VERSIONS],
      rbx: [Gem::Platform::RUBY],
      truffleruby: [Gem::Platform::RUBY],
      jruby: [Gem::Platform::JAVA, [18, 19]],
      windows: [Gem::Platform::WINDOWS, ALL_RUBY_VERSIONS],
      # deprecated
      mswin: [Gem::Platform::MSWIN, ALL_RUBY_VERSIONS],
      mswin64: [Gem::Platform::MSWIN64, ALL_RUBY_VERSIONS - [18]],
      mingw: [Gem::Platform::MINGW, ALL_RUBY_VERSIONS],
      x64_mingw: [Gem::Platform::X64_MINGW, ALL_RUBY_VERSIONS - [18, 19]],
    }.each_with_object({}) do |(platform, spec), hash|
      hash[platform] = spec[0]
      spec[1]&.each {|version| hash[:"#{platform}_#{version}"] = spec[0] }
    end.freeze

    def initialize(name, version, options = {}, &blk)
      type = options["type"] || :runtime
      super(name, version, type)

      @autorequire    = nil
      @groups         = Array(options["group"] || :default).map(&:to_sym)
      @source         = options["source"]
      @path           = options["path"]
      @git            = options["git"]
      @github         = options["github"]
      @branch         = options["branch"]
      @ref            = options["ref"]
      @glob           = options["glob"]
      @platforms      = Array(options["platforms"])
      @env            = options["env"]
      @should_include = options.fetch("should_include", true)
      @gemfile        = options["gemfile"]
      @force_ruby_platform = options["force_ruby_platform"] if options.key?("force_ruby_platform")

      @autorequire = Array(options["require"] || []) if options.key?("require")
    end

    RUBY_PLATFORM_ARRAY = [Gem::Platform::RUBY].freeze
    private_constant :RUBY_PLATFORM_ARRAY

    # Returns the platforms this dependency is valid for, in the same order as
    # passed in the `valid_platforms` parameter
    def gem_platforms(valid_platforms)
      return RUBY_PLATFORM_ARRAY if force_ruby_platform
      return valid_platforms if @platforms.empty?

      valid_platforms.select {|p| expanded_platforms.include?(GemHelpers.generic(p)) }
    end

    def expanded_platforms
      @expanded_platforms ||= @platforms.map {|pl| PLATFORM_MAP[pl] }.compact.flatten.uniq
    end

    def should_include?
      @should_include && current_env? && current_platform?
    end

    def gemspec_dev_dep?
      type == :development
    end

    def current_env?
      return true unless @env
      if @env.is_a?(Hash)
        @env.all? do |key, val|
          ENV[key.to_s] && (val.is_a?(String) ? ENV[key.to_s] == val : ENV[key.to_s] =~ val)
        end
      else
        ENV[@env.to_s]
      end
    end

    def current_platform?
      return true if @platforms.empty?
      @platforms.any? do |p|
        Bundler.current_ruby.send("#{p}?")
      end
    end

    def to_lock
      out = super
      out << "!" if source
      out
    end

    def specific?
      super
    rescue NoMethodError
      requirement != ">= 0"
    end
  end
end
