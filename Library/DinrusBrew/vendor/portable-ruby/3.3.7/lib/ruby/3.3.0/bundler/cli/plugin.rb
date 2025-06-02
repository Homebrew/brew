# frozen_string_literal: true

require_relative "../vendored_thor"
module Bundler
  class CLI::Plugin < Thor
    desc "install PLUGINS", "Install the plugin from the source"
    long_desc <<-D
      Install plugins either from the rubygems source provided (with --source option), from a git source provided with --git, or a local path provided with --path. If no sources are provided, it uses Gem.sources
   D
    method_option "source", type: :string, default: nil, banner: "URL of the RubyGems source to fetch the plugin from"
    method_option "version", type: :string, default: nil, banner: "The version of the plugin to fetch"
    method_option "git", type: :string, default: nil, banner: "URL of the git repo to fetch from"
    method_option "local_git", type: :string, default: nil, banner: "Path of the local git repo to fetch from (deprecated)"
    method_option "branch", type: :string, default: nil, banner: "The git branch to checkout"
    method_option "ref", type: :string, default: nil, banner: "The git revision to check out"
    method_option "path", type: :string, default: nil, banner: "Path of a local gem to directly use"
    def install(*plugins)
      Bundler::Plugin.install(plugins, options)
    end

    desc "uninstall PLUGINS", "Uninstall the plugins"
    long_desc <<-D
      Uninstall given list of plugins. To uninstall all the plugins, use -all option.
    D
    method_option "all", type: :boolean, default: nil, banner: "Uninstall all the installed plugins. If no plugin is installed, then it does nothing."
    def uninstall(*plugins)
      Bundler::Plugin.uninstall(plugins, options)
    end

    desc "list", "List the installed plugins and available commands"
    def list
      Bundler::Plugin.list
    end
  end
end
