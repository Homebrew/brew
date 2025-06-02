# frozen_string_literal: true

##
# Helper methods for both Gem::Installer and Gem::Uninstaller

module Gem::InstallerUninstallerUtils
  def regenerate_plugins_for(spec, plugins_dir)
    plugins = spec.plugins
    return if plugins.empty?

    require "pathname"

    spec.plugins.each do |plugin|
      plugin_script_path = File.join plugins_dir, "#{spec.name}_plugin#{File.extname(plugin)}"

      File.open plugin_script_path, "wb" do |file|
        file.puts "require_relative '#{Pathname.new(plugin).relative_path_from(Pathname.new(plugins_dir))}'"
      end

      verbose plugin_script_path
    end
  end

  def remove_plugins_for(spec, plugins_dir)
    FileUtils.rm_f Gem::Util.glob_files_in_dir("#{spec.name}#{Gem.plugin_suffix_pattern}", plugins_dir)
  end
end
