# frozen_string_literal: true

module Bundler
  # SourceList object to be used while parsing the Gemfile, setting the
  # approptiate options to be used with Source classes for plugin installation
  module Plugin
    class SourceList < Bundler::SourceList
      def add_git_source(options = {})
        add_source_to_list Plugin::Installer::Git.new(options), git_sources
      end

      def add_path_source(options = {})
        add_source_to_list Plugin::Installer::Path.new(options), path_sources
      end

      def add_rubygems_source(options = {})
        add_source_to_list Plugin::Installer::Rubygems.new(options), @rubygems_sources
      end

      def all_sources
        path_sources + git_sources + rubygems_sources + [metadata_source]
      end

      private

      def rubygems_aggregate_class
        Plugin::Installer::Rubygems
      end
    end
  end
end
