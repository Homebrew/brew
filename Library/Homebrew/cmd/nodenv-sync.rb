# typed: true
# frozen_string_literal: true

require "cli/parser"
require "formula"

module Homebrew
  module_function

  sig { returns(CLI::Parser) }
  def nodenv_sync_args
    Homebrew::CLI::Parser.new do
      description <<~EOS
        Create symlinks for Homebrew's installed NodeJS versions in `~/.nodenv/versions`.

        Note that older version symlinks will also be created so e.g. NodeJS 19.1.0 will
        also be symlinked to 19.0.0.
      EOS

      named_args :none
    end
  end

  sig { void }
  def nodenv_sync
    dot_nodenv = Pathname(Dir.home)/".nodenv"

    # Don't run multiple times at once.
    nodenv_sync_running = dot_nodenv/".nodenv_sync_running"
    return if nodenv_sync_running.exist?

    begin
      nodenv_versions = dot_nodenv/"versions"
      nodenv_versions.mkpath
      FileUtils.touch nodenv_sync_running

      nodenv_sync_args.parse

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

  sig { params(path: Pathname, nodenv_versions: Pathname).void }
  def link_nodenv_versions(path, nodenv_versions)
    nodenv_versions.mkpath

    version = Keg.new(path).version
    major_version = version.major.to_i
    minor_version = version.minor.to_i || 0
    patch_version = version.patch.to_i || 0

    (0..minor_version).each do |minor|
      (0..patch_version).each do |patch|
        link_path = nodenv_versions/"#{major_version}.#{minor}.#{patch}"

        FileUtils.rm_f link_path
        FileUtils.ln_sf path, link_path
      end
    end
  end
end
