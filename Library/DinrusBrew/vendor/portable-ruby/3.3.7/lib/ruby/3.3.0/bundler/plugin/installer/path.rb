# frozen_string_literal: true

module Bundler
  module Plugin
    class Installer
      class Path < Bundler::Source::Path
        def root
          SharedHelpers.in_bundle? ? Bundler.root : Plugin.root
        end

        def generate_bin(spec, disable_extensions = false)
          # Need to find a way without code duplication
          # For now, we can ignore this
        end
      end
    end
  end
end
