# frozen_string_literal: true

module Bundler
  module Plugin
    class Installer
      class Rubygems < Bundler::Source::Rubygems
        private

        def requires_sudo?
          false # Will change on implementation of project level plugins
        end

        def rubygems_dir
          Plugin.root
        end

        def cache_path
          Plugin.cache
        end
      end
    end
  end
end
