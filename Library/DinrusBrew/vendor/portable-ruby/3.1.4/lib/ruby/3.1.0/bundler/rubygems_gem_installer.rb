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
        FileUtils.mkdir_p gem_dir, :mode => 0o755
      end

      extract_files

      build_extensions if spec.extensions.any?
      write_build_info_file
      run_post_build_hooks

      generate_bin
      generate_plugins

      write_spec

      SharedHelpers.filesystem_access("#{gem_home}/cache", :write) do
        write_cache_file
      end

      say spec.post_install_message unless spec.post_install_message.nil?

      run_post_install_hooks

      spec
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

    def pre_install_checks
      super && validate_bundler_checksum(options[:bundler_expected_checksum])
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

    private

    def prepare_extension_build(extension_dir)
      SharedHelpers.filesystem_access(extension_dir, :create) do
        FileUtils.mkdir_p extension_dir
      end
      require "shellwords" unless Bundler.rubygems.provides?(">= 3.2.25")
    end

    def strict_rm_rf(dir)
      Bundler.rm_rf dir
    rescue Errno::ENOTEMPTY => e
      raise DirectoryRemovalError.new(e.cause, "Could not delete previous installation of `#{dir}`")
    end

    def validate_bundler_checksum(checksum)
      return true if Bundler.settings[:disable_checksum_validation]
      return true unless checksum
      return true unless source = @package.instance_variable_get(:@gem)
      return true unless source.respond_to?(:with_read_io)
      digest = source.with_read_io do |io|
        digest = SharedHelpers.digest(:SHA256).new
        digest << io.read(16_384) until io.eof?
        io.rewind
        send(checksum_type(checksum), digest)
      end
      unless digest == checksum
        raise SecurityError, <<-MESSAGE
          Bundler cannot continue installing #{spec.name} (#{spec.version}).
          The checksum for the downloaded `#{spec.full_name}.gem` does not match \
          the checksum given by the server. This means the contents of the downloaded \
          gem is different from what was uploaded to the server, and could be a potential security issue.

          To resolve this issue:
          1. delete the downloaded gem located at: `#{spec.gem_dir}/#{spec.full_name}.gem`
          2. run `bundle install`

          If you wish to continue installing the downloaded gem, and are certain it does not pose a \
          security issue despite the mismatching checksum, do the following:
          1. run `bundle config set --local disable_checksum_validation true` to turn off checksum verification
          2. run `bundle install`

          (More info: The expected SHA256 checksum was #{checksum.inspect}, but the \
          checksum for the downloaded gem was #{digest.inspect}.)
          MESSAGE
      end
      true
    end

    def checksum_type(checksum)
      case checksum.length
      when 64 then :hexdigest!
      when 44 then :base64digest!
      else raise InstallError, "The given checksum for #{spec.full_name} (#{checksum.inspect}) is not a valid SHA256 hexdigest nor base64digest"
      end
    end

    def hexdigest!(digest)
      digest.hexdigest!
    end

    def base64digest!(digest)
      if digest.respond_to?(:base64digest!)
        digest.base64digest!
      else
        [digest.digest!].pack("m0")
      end
    end
  end
end
