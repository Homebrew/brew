# frozen_string_literal: true

module Bundler
  class CLI::Pristine
    def initialize(gems)
      @gems = gems
    end

    def run
      CLI::Common.ensure_all_gems_in_lockfile!(@gems)
      definition = Bundler.definition
      definition.validate_runtime!
      installer = Bundler::Installer.new(Bundler.root, definition)

      Bundler.load.specs.each do |spec|
        next if spec.name == "bundler" # Source::Rubygems doesn't install bundler
        next if !@gems.empty? && !@gems.include?(spec.name)

        gem_name = "#{spec.name} (#{spec.version}#{spec.git_version})"
        gem_name += " (#{spec.platform})" if !spec.platform.nil? && spec.platform != Gem::Platform::RUBY

        case source = spec.source
        when Source::Rubygems
          cached_gem = spec.cache_file
          unless File.exist?(cached_gem)
            Bundler.ui.error("Failed to pristine #{gem_name}. Cached gem #{cached_gem} does not exist.")
            next
          end

          FileUtils.rm_rf spec.full_gem_path
        when Source::Git
          if source.local?
            Bundler.ui.warn("Cannot pristine #{gem_name}. Gem is locally overridden.")
            next
          end

          source.remote!
          if extension_cache_path = source.extension_cache_path(spec)
            FileUtils.rm_rf extension_cache_path
          end
          FileUtils.rm_rf spec.extension_dir
          FileUtils.rm_rf spec.full_gem_path
        else
          Bundler.ui.warn("Cannot pristine #{gem_name}. Gem is sourced from local path.")
          next
        end

        Bundler::GemInstaller.new(spec, installer, false, 0, true).install_from_spec
      end
    end
  end
end
