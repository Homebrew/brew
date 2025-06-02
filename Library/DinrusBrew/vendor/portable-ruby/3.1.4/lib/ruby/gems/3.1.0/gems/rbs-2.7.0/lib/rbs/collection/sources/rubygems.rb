# frozen_string_literal: true

require 'singleton'

module RBS
  module Collection
    module Sources
      # Signatures that are inclduded in gem package as sig/ directory.
      class Rubygems
        include Base
        include Singleton

        def has?(config_entry)
          gem_sig_path(config_entry)
        end

        def versions(config_entry)
          spec, _ = gem_sig_path(config_entry)
          spec or raise
          [spec.version.to_s]
        end

        def install(dest:, config_entry:, stdout:)
          # Do nothing because stdlib RBS is available by default
          name = config_entry['name']
          version = config_entry['version'] or raise
          _, from = gem_sig_path(config_entry)
          stdout.puts "Using #{name}:#{version} (#{from})"
        end

        def manifest_of(config_entry)
          _, sig_path = gem_sig_path(config_entry)
          sig_path or raise
          manifest_path = sig_path.join('manifest.yaml')
          YAML.safe_load(manifest_path.read) if manifest_path.exist?
        end

        def to_lockfile
          {
            'type' => 'rubygems',
          }
        end

        private def gem_sig_path(config_entry)
          RBS::EnvironmentLoader.gem_sig_path(config_entry['name'], config_entry['version'])
        end
      end
    end
  end
end
