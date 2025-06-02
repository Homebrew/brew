# frozen_string_literal: true

module RBS
  module Collection
    class Installer
      attr_reader :lockfile
      attr_reader :stdout

      def initialize(lockfile_path:, stdout: $stdout)
        @lockfile = Config.from_path(lockfile_path)
        @stdout = stdout
      end

      def install_from_lockfile
        install_to = lockfile.repo_path
        install_to.mkpath
        lockfile.gems.each do |config_entry|
          source_for(config_entry).install(dest: install_to, config_entry: config_entry, stdout: stdout)
        end
        stdout.puts "It's done! #{lockfile.gems.size} gems' RBSs now installed."
      end

      private def source_for(config_entry)
        @source_for ||= {}
        key = config_entry['source']
        unless key
          raise "Cannot find source of '#{config_entry['name']}' gem"
        end
        @source_for[key] ||= Sources.from_config_entry(key)
      end
    end
  end
end
