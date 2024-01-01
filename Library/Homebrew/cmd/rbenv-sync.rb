# typed: true
# frozen_string_literal: true

require "cli/parser"
require "formula"

module Homebrew
  module_function

  sig { returns(CLI::Parser) }
  def rbenv_sync_args
    Homebrew::CLI::Parser.new do
      description <<~EOS
        Create symlinks for Homebrew's installed Ruby versions in `~/.rbenv/versions`.

        Note that older version symlinks will also be created so e.g. Ruby 3.2.1 will
        also be symlinked to 3.2.0.
      EOS

      named_args :none
    end
  end

  sig { void }
  def rbenv_sync
    dot_rbenv = Pathname(Dir.home)/".rbenv"

    # Don't run multiple times at once.
    rbenv_sync_running = dot_rbenv/".rbenv_sync_running"
    return if rbenv_sync_running.exist?

    begin
      rbenv_versions = dot_rbenv/"versions"
      rbenv_versions.mkpath
      FileUtils.touch rbenv_sync_running

      rbenv_sync_args.parse

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

  sig { params(path: Pathname, rbenv_versions: Pathname).void }
  def link_rbenv_versions(path, rbenv_versions)
    rbenv_versions.mkpath

    version = Keg.new(path).version
    major_version = version.major.to_i
    minor_version = version.minor.to_i
    patch_version = version.patch.to_i || 0

    (0..patch_version).each do |patch|
      link_path = rbenv_versions/"#{major_version}.#{minor_version}.#{patch}"

      FileUtils.rm_f link_path
      FileUtils.ln_sf path, link_path
    end
  end
end
