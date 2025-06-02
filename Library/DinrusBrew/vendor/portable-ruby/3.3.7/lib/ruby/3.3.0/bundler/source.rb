# frozen_string_literal: true

module Bundler
  class Source
    autoload :Gemspec,  File.expand_path("source/gemspec", __dir__)
    autoload :Git,      File.expand_path("source/git", __dir__)
    autoload :Metadata, File.expand_path("source/metadata", __dir__)
    autoload :Path,     File.expand_path("source/path", __dir__)
    autoload :Rubygems, File.expand_path("source/rubygems", __dir__)
    autoload :RubygemsAggregate, File.expand_path("source/rubygems_aggregate", __dir__)

    attr_accessor :dependency_names

    attr_reader :checksum_store

    def unmet_deps
      specs.unmet_dependency_names
    end

    def version_message(spec, locked_spec = nil)
      message = "#{spec.name} #{spec.version}"
      message += " (#{spec.platform})" if spec.platform != Gem::Platform::RUBY && !spec.platform.nil?

      if locked_spec
        locked_spec_version = locked_spec.version
        if locked_spec_version && spec.version != locked_spec_version
          message += Bundler.ui.add_color(" (was #{locked_spec_version})", version_color(spec.version, locked_spec_version))
        end
      end

      message
    end

    def can_lock?(spec)
      spec.source == self
    end

    def local!; end

    def local_only!; end

    def cached!; end

    def remote!; end

    def add_dependency_names(names)
      @dependency_names = Array(dependency_names) | Array(names)
    end

    # it's possible that gems from one source depend on gems from some
    # other source, so now we download gemspecs and iterate over those
    # dependencies, looking for gems we don't have info on yet.
    def double_check_for(*); end

    def dependency_names_to_double_check
      specs.dependency_names
    end

    def spec_names
      specs.spec_names
    end

    def include?(other)
      other == self
    end

    def inspect
      "#<#{self.class}:0x#{object_id} #{self}>"
    end

    def identifier
      to_s
    end

    def path?
      instance_of?(Bundler::Source::Path)
    end

    def extension_cache_path(spec)
      return unless Bundler.feature_flag.global_gem_cache?
      return unless source_slug = extension_cache_slug(spec)
      Bundler.user_cache.join(
        "extensions", Gem::Platform.local.to_s, Bundler.ruby_scope,
        source_slug, spec.full_name
      )
    end

    private

    def version_color(spec_version, locked_spec_version)
      if Gem::Version.correct?(spec_version) && Gem::Version.correct?(locked_spec_version)
        # display yellow if there appears to be a regression
        earlier_version?(spec_version, locked_spec_version) ? :yellow : :green
      else
        # default to green if the versions cannot be directly compared
        :green
      end
    end

    def earlier_version?(spec_version, locked_spec_version)
      Gem::Version.new(spec_version) < Gem::Version.new(locked_spec_version)
    end

    def print_using_message(message)
      if !message.include?("(was ")
        Bundler.ui.debug message
      else
        Bundler.ui.info message
      end
    end

    def extension_cache_slug(_)
      nil
    end
  end
end
