# frozen_string_literal: true

require "rubygems/installer"

module Bundler
  class RubyGemsGemInstaller < Gem::Installer
    def check_executable_overwrite(filename)
      # Bundler needs to install gems regardless of binstub overwriting
    end

    def install
      pre_install_checks

      run_pre_install_hooks

      spec.loaded_from = spec_file

      # Completely remove any previous gem files
      strict_rm_rf gem_dir
      strict_rm_rf spec.extension_dir

      SharedHelpers.filesystem_access(gem_dir, :create) do
        FileUtils.mkdir_p gem_dir, mode: 0o755
      end

      extract_files

      build_extensions if spec.extensions.any?
      write_build_info_file
      run_post_build_hooks

      SharedHelpers.filesystem_access(bin_dir, :write) do
        generate_bin
      end

      generate_plugins

      write_spec

      SharedHelpers.filesystem_access("#{gem_home}/cache", :write) do
        write_cache_file
      end

      say spec.post_install_message unless spec.post_install_message.nil?

      run_post_install_hooks

      spec
    end

    if Bundler.rubygems.provides?("< 3.5")
      def pre_install_checks
        super
      rescue Gem::FilePermissionError
        # Ignore permission checks in RubyGems. Instead, go on, and try to write
        # for real. We properly handle permission errors when they happen.
        nil
      end
    end

    def ensure_writable_dir(dir)
      super
    rescue Gem::FilePermissionError
      # Ignore permission checks in RubyGems. Instead, go on, and try to write
      # for real. We properly handle permission errors when they happen.
      nil
    end

    def generate_plugins
      return unless Gem::Installer.instance_methods(false).include?(:generate_plugins)

      latest = Gem::Specification.stubs_for(spec.name).first
      return if latest && latest.version > spec.version

      ensure_writable_dir @plugins_dir

      if spec.plugins.empty?
        remove_plugins_for(spec, @plugins_dir)
      else
        regenerate_plugins_for(spec, @plugins_dir)
      end
    end

    if Bundler.rubygems.provides?("< 3.5.19")
      def generate_bin_script(filename, bindir)
        bin_script_path = File.join bindir, formatted_program_filename(filename)

        Gem.open_file_with_lock(bin_script_path) do
          require "fileutils"
          FileUtils.rm_f bin_script_path # prior install may have been --no-wrappers

          File.open(bin_script_path, "wb", 0o755) do |file|
            file.write app_script_text(filename)
            file.chmod(options[:prog_mode] || 0o755)
          end
        end

        verbose bin_script_path

        generate_windows_script filename, bindir
      end
    end

    def build_extensions
      extension_cache_path = options[:bundler_extension_cache_path]
      extension_dir = spec.extension_dir
      unless extension_cache_path && extension_dir
        prepare_extension_build(extension_dir)
        return super
      end

      build_complete = SharedHelpers.filesystem_access(extension_cache_path.join("gem.build_complete"), :read, &:file?)
      if build_complete && !options[:force]
        SharedHelpers.filesystem_access(File.dirname(extension_dir)) do |p|
          FileUtils.mkpath p
        end
        SharedHelpers.filesystem_access(extension_cache_path) do
          FileUtils.cp_r extension_cache_path, extension_dir
        end
      else
        prepare_extension_build(extension_dir)
        super
        SharedHelpers.filesystem_access(extension_cache_path.parent, &:mkpath)
        SharedHelpers.filesystem_access(extension_cache_path) do
          FileUtils.cp_r extension_dir, extension_cache_path
        end
      end
    end

    def spec
      if Bundler.rubygems.provides?("< 3.3.12") # RubyGems implementation rescues and re-raises errors before 3.3.12 and we don't want that
        @package.spec
      else
        super
      end
    end

    def gem_checksum
      Checksum.from_gem_package(@package)
    end

    private

    def prepare_extension_build(extension_dir)
      SharedHelpers.filesystem_access(extension_dir, :create) do
        FileUtils.mkdir_p extension_dir
      end
      require "shellwords" unless Bundler.rubygems.provides?(">= 3.2.25")
    end

    def strict_rm_rf(dir)
      return unless File.exist?(dir)
      return if Dir.empty?(dir)

      parent = File.dirname(dir)
      parent_st = File.stat(parent)

      if parent_st.world_writable? && !parent_st.sticky?
        raise InsecureInstallPathError.new(spec.full_name, dir)
      end

      begin
        FileUtils.remove_entry_secure(dir)
      rescue StandardError => e
        raise unless File.exist?(dir)

        raise DirectoryRemovalError.new(e, "Could not delete previous installation of `#{dir}`")
      end
    end
  end
end
