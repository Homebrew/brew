# frozen_string_literal: true

require_relative './sources/base'
require_relative './sources/git'
require_relative './sources/stdlib'
require_relative './sources/rubygems'

module RBS
  module Collection
    module Sources
      def self.from_config_entry(source_entry)
        case source_entry['type']
        when 'git', nil # git source by default
          __skip__ = Git.new(**source_entry.slice('name', 'revision', 'remote', 'repo_dir').transform_keys(&:to_sym))
        when 'stdlib'
          Stdlib.instance
        when 'rubygems'
          Rubygems.instance
        else
          raise
        end
      end
    end
  end
end
