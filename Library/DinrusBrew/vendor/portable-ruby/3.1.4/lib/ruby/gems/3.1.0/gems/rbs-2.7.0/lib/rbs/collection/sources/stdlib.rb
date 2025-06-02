# frozen_string_literal: true

require 'singleton'

module RBS
  module Collection
    module Sources
      # signatures that are bundled in rbs gem under the stdlib/ directory
      class Stdlib
        include Base
        include Singleton

        REPO = Repository.default

        def has?(config_entry)
          lookup(config_entry)
        end

        def versions(config_entry)
          REPO.gems[config_entry['name']].versions.keys.map(&:to_s)
        end

        def install(dest:, config_entry:, stdout:)
          # Do nothing because stdlib RBS is available by default
          name = config_entry['name']
          version = config_entry['version'] or raise
          from = lookup(config_entry)
          stdout.puts "Using #{name}:#{version} (#{from})"
        end

        def manifest_of(config_entry)
          config_entry['version'] or raise
          manifest_path = (lookup(config_entry) or raise).join('manifest.yaml')
          YAML.safe_load(manifest_path.read) if manifest_path.exist?
        end

        def to_lockfile
          {
            'type' => 'stdlib',
          }
        end

        private def lookup(config_entry)
          REPO.lookup(config_entry['name'], config_entry['version'])
        end
      end
    end
  end
end
