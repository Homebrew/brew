# typed: true
# frozen_string_literal: true

require "cli/parser"
require "formula"

module Homebrew
  module_function

  sig { returns(CLI::Parser) }
  def pyenv_sync_args
    Homebrew::CLI::Parser.new do
      description <<~EOS
        Create symlinks for Homebrew's installed Python versions in `~/.pyenv/versions`.

        Note that older patch version symlinks will be created and linked to the minor
        version so e.g. Python 3.11.0 will also be symlinked to 3.11.3.
      EOS

      named_args :none
    end
  end

  sig { void }
  def pyenv_sync
    dot_pyenv = Pathname(Dir.home)/".pyenv"

    # Don't run multiple times at once.
    pyenv_sync_running = dot_pyenv/".pyenv_sync_running"
    return if pyenv_sync_running.exist?

    begin
      pyenv_versions = dot_pyenv/"versions"
      pyenv_versions.mkpath
      FileUtils.touch pyenv_sync_running

      pyenv_sync_args.parse

      HOMEBREW_CELLAR.glob("python{,@*}")
                     .flat_map(&:children)
                     .each { |path| link_pyenv_versions(path, pyenv_versions) }

      pyenv_versions.children
                    .select(&:symlink?)
                    .reject(&:exist?)
                    .each { |path| FileUtils.rm_f path }
    ensure
      pyenv_sync_running.unlink if pyenv_sync_running.exist?
    end
  end

  sig { params(path: Pathname, pyenv_versions: Pathname).void }
  def link_pyenv_versions(path, pyenv_versions)
    pyenv_versions.mkpath

    version = Keg.new(path).version
    major_version = version.major.to_i
    minor_version = version.minor.to_i
    patch_version = version.patch.to_i

    (0..patch_version).each do |patch|
      link_path = pyenv_versions/"#{major_version}.#{minor_version}.#{patch}"

      FileUtils.rm_f link_path
      FileUtils.ln_sf path, link_path
    end
  end
end
