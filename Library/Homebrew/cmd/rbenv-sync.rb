# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "formula"

module Homebrew
  module Cmd
    class RbenvSync < AbstractCommand
      cmd_args do
        description <<~EOS
          Create symlinks for Homebrew's installed Ruby versions in `~/.rbenv/versions`.

          Note that older version symlinks will also be created so e.g. Ruby 3.2.1 will
          also be symlinked to 3.2.0.
        EOS

        named_args :none
      end

      sig { override.void }
      def run
        rbenv_root = Pathname(ENV.fetch("HOMEBREW_RBENV_ROOT", Pathname(Dir.home)/".rbenv"))

        # Don't run multiple times at once.
        rbenv_sync_running = rbenv_root/".rbenv_sync_running"
        return if rbenv_sync_running.exist?

        begin
          rbenv_versions = rbenv_root/"versions"
          rbenv_versions.mkpath
          FileUtils.touch rbenv_sync_running

          HOMEBREW_CELLAR.glob("ruby{,@*}")
                         .flat_map(&:children)
                         .each { |path| link_rbenv_versions(path, rbenv_versions) }

          rbenv_versions.children
                        .select(&:symlink?)
                        .reject(&:exist?)
                        .each { |path| FileUtils.rm_f path }
        ensure
          rbenv_sync_running.unlink if rbenv_sync_running.exist?
        end
      end

      private

      sig { params(path: Pathname, rbenv_versions: Pathname).void }
      def link_rbenv_versions(path, rbenv_versions)
        rbenv_versions.mkpath

        version = Keg.new(path).version
        major_version = version.major.to_i
        minor_version = version.minor.to_i
        patch_version = version.patch.to_i

        patch_version_range = if Homebrew::EnvConfig.env_sync_strict?
          # Only create symlinks for the exact installed patch version.
          # e.g. 3.4.0 => 3.4.0
          [patch_version]
        else
          # Create folder symlinks for all patch versions to the latest patch version
          # e.g. 3.4.0 => 3.4.2
          0..patch_version
        end

        patch_version_range.each do |patch|
          link_path = rbenv_versions/"#{major_version}.#{minor_version}.#{patch}"
          # Don't clobber existing user installations.
          next if link_path.exist? && !link_path.symlink?

          FileUtils.rm_f link_path
          FileUtils.ln_s path, link_path
        end
      end
    end
  end
end
