# frozen_string_literal: true

module RBS
  module Collection

    # This class represent the configration file.
    class Config
      class LockfileGenerator
        attr_reader :config, :lock, :gemfile_lock, :lock_path

        def self.generate(config_path:, gemfile_lock_path:, with_lockfile: true)
          new(config_path: config_path, gemfile_lock_path: gemfile_lock_path, with_lockfile: with_lockfile).generate
        end

        def initialize(config_path:, gemfile_lock_path:, with_lockfile:)
          @config = Config.from_path config_path
          @lock_path = Config.to_lockfile_path(config_path)
          @lock = Config.from_path(lock_path) if lock_path.exist? && with_lockfile
          @gemfile_lock = Bundler::LockfileParser.new(gemfile_lock_path.read)
          @gem_queue = []
        end

        def generate
          config.gems.each do |gem|
            @gem_queue.push({ name: gem['name'], version: gem['version'] })
          end

          gemfile_lock_gems do |spec|
            @gem_queue.push({ name: spec.name, version: spec.version })
          end

          while gem = @gem_queue.shift
            assign_gem(**gem)
          end
          remove_ignored_gems!

          config.dump_to(lock_path)
          config
        end

        private def assign_gem(name:, version:)
          # @type var locked: gem_entry?
          locked = lock&.gem(name)
          specified = config.gem(name)

          return if specified&.dig('ignore')
          return if specified&.dig('source') # skip if the source is already filled

          # If rbs_collection.lock.yaml contain the gem, use it.
          # Else find the gem from gem_collection.
          unless locked
            source = find_source(name: name)
            return unless source

            installed_version = version
            best_version = find_best_version(version: installed_version, versions: source.versions({ 'name' => name }))

            locked = {
              'name' => name,
              'version' => best_version.to_s,
              'source' => source.to_lockfile,
            }
          end

          locked or raise

          upsert_gem specified, locked
          source = Sources.from_config_entry(locked['source'] || raise)
          source.dependencies_of(locked)&.each do |dep|
            @gem_queue.push({ name: dep['name'], version: nil} )
          end
        end

        private def upsert_gem(old, new)
          if old
            old.merge! new
          else
            config.add_gem new
          end
        end

        private def remove_ignored_gems!
          config.gems.reject! { |gem| gem['ignore'] }
        end

        private def gemfile_lock_gems(&block)
          gemfile_lock.specs.each do |spec|
            yield spec
          end
        end

        private def find_source(name:)
          sources = config.sources

          sources.find { |c| c.has?({ 'name' => name, 'revision' => nil } ) }
        end

        private def find_best_version(version:, versions:)
          candidates = versions.map { |v| Gem::Version.create(v) or raise }
          return candidates.max || raise unless version

          v = Gem::Version.create(version) or raise
          Repository.find_best_version(v, candidates)
        end
      end
    end
  end
end
