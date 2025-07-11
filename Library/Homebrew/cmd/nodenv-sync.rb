# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "formula"

module Homebrew
  module Cmd
    class NodenvSync < AbstractCommand
      cmd_args do
        description <<~EOS
          Create symlinks for Homebrew's installed NodeJS versions in `~/.nodenv/versions`.

          Note that older version symlinks will also be created so e.g. NodeJS 19.1.0 will
          also be symlinked to 19.0.0.
        EOS

        named_args :none
      end

      sig { override.void }
      def run
        nodenv_root = Pathname(ENV.fetch("HOMEBREW_NODENV_ROOT", Pathname(Dir.home)/".nodenv"))

        # Don't run multiple times at once.
        nodenv_sync_running = nodenv_root/".nodenv_sync_running"
        return if nodenv_sync_running.exist?

        begin
          nodenv_versions = nodenv_root/"versions"
          nodenv_versions.mkpath
          FileUtils.touch nodenv_sync_running

          HOMEBREW_CELLAR.glob("node{,@*}")
                         .flat_map(&:children)
                         .each { |path| link_nodenv_versions(path, nodenv_versions) }

          nodenv_versions.children
                         .select(&:symlink?)
                         .reject(&:exist?)
                         .each { |path| FileUtils.rm_f path }
        ensure
          nodenv_sync_running.unlink if nodenv_sync_running.exist?
        end
      end

      private

      sig { params(path: Pathname, nodenv_versions: Pathname).void }
      def link_nodenv_versions(path, nodenv_versions)
        nodenv_versions.mkpath

        version = Keg.new(path).version
        major_version = version.major.to_i
        minor_version = version.minor.to_i
        patch_version = version.patch.to_i

        minor_version_range, patch_version_range = if Homebrew::EnvConfig.env_sync_strict?
          # Only create symlinks for the exact installed patch version.
          # e.g. 23.9.0 => 23.9.0
          [[minor_version], [patch_version]]
        else
          # Create folder symlinks for all patch versions to the latest patch version
          # e.g. 23.9.0 => 23.10.1
          [0..minor_version, 0..patch_version]
        end

        minor_version_range.each do |minor|
          patch_version_range.each do |patch|
            link_path = nodenv_versions/"#{major_version}.#{minor}.#{patch}"
            # Don't clobber existing user installations.
            next if link_path.exist? && !link_path.symlink?

            FileUtils.rm_f link_path
            FileUtils.ln_s path, link_path
          end
        end
      end
    end
  end
end
