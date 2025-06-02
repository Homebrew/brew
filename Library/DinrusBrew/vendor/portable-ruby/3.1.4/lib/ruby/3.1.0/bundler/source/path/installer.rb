# frozen_string_literal: true

require_relative "../../rubygems_gem_installer"

module Bundler
  class Source
    class Path
      class Installer < Bundler::RubyGemsGemInstaller
        attr_reader :spec

        def initialize(spec, options = {})
          @options            = options
          @spec               = spec
          @gem_dir            = Bundler.rubygems.path(spec.full_gem_path)
          @wrappers           = true
          @env_shebang        = true
          @format_executable  = options[:format_executable] || false
          @build_args         = options[:build_args] || Bundler.rubygems.build_args
          @gem_bin_dir        = "#{Bundler.rubygems.gem_dir}/bin"
          @disable_extensions = options[:disable_extensions]

          if Bundler.requires_sudo?
            @tmp_dir = Bundler.tmp(spec.full_name).to_s
            @bin_dir = "#{@tmp_dir}/bin"
          else
            @bin_dir = @gem_bin_dir
          end
        end

        def post_install
          run_hooks(:pre_install)

          unless @disable_extensions
            build_extensions
            run_hooks(:post_build)
          end

          generate_bin unless spec.executables.empty?

          run_hooks(:post_install)
        ensure
          Bundler.rm_rf(@tmp_dir) if Bundler.requires_sudo?
        end

        private

        def generate_bin
          super

          if Bundler.requires_sudo?
            SharedHelpers.filesystem_access(@gem_bin_dir) do |p|
              Bundler.mkdir_p(p)
            end
            spec.executables.each do |exe|
              Bundler.sudo "cp -R #{@bin_dir}/#{exe} #{@gem_bin_dir}"
            end
          end
        end

        def run_hooks(type)
          hooks_meth = "#{type}_hooks"
          return unless Gem.respond_to?(hooks_meth)
          Gem.send(hooks_meth).each do |hook|
            result = hook.call(self)
            next unless result == false
            location = " at #{$1}" if hook.inspect =~ /@(.*:\d+)/
            message = "#{type} hook#{location} failed for #{spec.full_name}"
            raise InstallHookError, message
          end
        end
      end
    end
  end
end
