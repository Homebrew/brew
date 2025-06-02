# frozen_string_literal: true

module RBS
  module Collection

    # This class represent the configration file.
    class Config
      class CollectionNotAvailable < StandardError
        def initialize
          super <<~MSG
            rbs collection is not initialized.
            Run `rbs collection install` to install RBSs from collection.
          MSG
        end
      end

      PATH = Pathname('rbs_collection.yaml')

      # Generate a rbs lockfile from Gemfile.lock to `config_path`.
      # If `with_lockfile` is true, it respects existing rbs lockfile.
      def self.generate_lockfile(config_path:, gemfile_lock_path:, with_lockfile: true)
        LockfileGenerator.generate(config_path: config_path, gemfile_lock_path: gemfile_lock_path, with_lockfile: with_lockfile)
      end

      def self.from_path(path)
        new(YAML.load(path.read), config_path: path)
      end

      def self.lockfile_of(config_path)
        lock_path = to_lockfile_path(config_path)
        from_path lock_path if lock_path.exist?
      end

      def self.to_lockfile_path(config_path)
        config_path.sub_ext('.lock' + config_path.extname)
      end

      def initialize(data, config_path:)
        @data = data
        @config_path = config_path
      end

      def add_gem(gem)
        gems << gem
      end

      def gem(gem_name)
        gems.find { |gem| gem['name'] == gem_name }
      end

      def repo_path
        @config_path.dirname.join @data['path']
      end

      def sources
        @sources ||= (
          @data['sources']
            .map { |c| Sources.from_config_entry(c) }
            .push(Sources::Stdlib.instance)
            .push(Sources::Rubygems.instance)
        )
      end

      def dump_to(io)
        YAML.dump(@data, io)
      end

      def gems
        @data['gems'] ||= []
      end

      # It raises an error when there are non-available libraries
      def check_rbs_availability!
        raise CollectionNotAvailable unless repo_path.exist?

        gems.each do |gem|
          case gem['source']['type']
          when 'git'
            meta_path = repo_path.join(gem['name'], gem['version'], Sources::Git::METADATA_FILENAME)
            raise CollectionNotAvailable unless meta_path.exist?
            raise CollectionNotAvailable unless gem == YAML.load(meta_path.read)
          end
        end
      end
    end
  end
end
