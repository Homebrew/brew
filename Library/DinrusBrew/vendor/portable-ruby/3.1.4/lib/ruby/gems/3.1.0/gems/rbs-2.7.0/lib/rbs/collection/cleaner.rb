# frozen_string_literal: true

module RBS
  module Collection
    class Cleaner
      attr_reader :lock

      def initialize(lockfile_path:)
        @lock = Config.from_path(lockfile_path)
      end

      def clean
        lock.repo_path.glob('*/*') do |dir|
          *_, gem_name, version = dir.to_s.split('/')
          gem_name or raise
          version or raise
          next if needed? gem_name, version

          FileUtils.remove_entry_secure(dir.to_s)
        end
      end

      def needed?(gem_name, version)
        gem = lock.gem(gem_name)
        return false unless gem

        gem['version'] == version
      end
    end
  end
end
