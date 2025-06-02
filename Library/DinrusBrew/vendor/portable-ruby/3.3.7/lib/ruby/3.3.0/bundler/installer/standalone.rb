# frozen_string_literal: true

module Bundler
  class Standalone
    def initialize(groups, definition)
      @specs = definition.specs_for(groups)
    end

    def generate
      SharedHelpers.filesystem_access(bundler_path) do |p|
        FileUtils.mkdir_p(p)
      end
      File.open File.join(bundler_path, "setup.rb"), "w" do |file|
        file.puts "require 'rbconfig'"
        file.puts prevent_gem_activation
        file.puts define_path_helpers
        file.puts reverse_rubygems_kernel_mixin
        paths.each do |path|
          if Pathname.new(path).absolute?
            file.puts %($:.unshift "#{path}")
          else
            file.puts %($:.unshift File.expand_path("\#{__dir__}/#{path}"))
          end
        end
      end
    end

    private

    def paths
      @specs.map do |spec|
        next if spec.name == "bundler"
        Array(spec.require_paths).map do |path|
          gem_path(path, spec).
            sub(version_dir, '#{RUBY_ENGINE}/#{Gem.ruby_api_version}').
            sub(extensions_dir, 'extensions/\k<platform>/#{Gem.extension_api_version}')
          # This is a static string intentionally. It's interpolated at a later time.
        end
      end.flatten.compact
    end

    def version_dir
      "#{RUBY_ENGINE}/#{Gem.ruby_api_version}"
    end

    def extensions_dir
      %r{extensions/(?<platform>[^/]+)/#{Regexp.escape(Gem.extension_api_version)}}
    end

    def bundler_path
      Bundler.root.join(Bundler.settings[:path].to_s, "bundler")
    end

    def gem_path(path, spec)
      full_path = Pathname.new(path).absolute? ? path : File.join(spec.full_gem_path, path)
      if spec.source.instance_of?(Source::Path) && spec.source.path.absolute?
        full_path
      else
        SharedHelpers.relative_path_to(full_path, from: Bundler.root.join(bundler_path))
      end
    end

    def prevent_gem_activation
      <<~'END'
        module Kernel
          remove_method(:gem) if private_method_defined?(:gem)

          def gem(*)
          end

          private :gem
        end
      END
    end

    def define_path_helpers
      <<~'END'
        unless defined?(Gem)
          module Gem
            def self.ruby_api_version
              RbConfig::CONFIG["ruby_version"]
            end

            def self.extension_api_version
              if 'no' == RbConfig::CONFIG['ENABLE_SHARED']
                "#{ruby_api_version}-static"
              else
                ruby_api_version
              end
            end
          end
        end
      END
    end

    def reverse_rubygems_kernel_mixin
      <<~END
      if Gem.respond_to?(:discover_gems_on_require=)
        Gem.discover_gems_on_require = false
      else
        [::Kernel.singleton_class, ::Kernel].each do |k|
          if k.private_method_defined?(:gem_original_require)
            private_require = k.private_method_defined?(:require)
            k.send(:remove_method, :require)
            k.send(:define_method, :require, k.instance_method(:gem_original_require))
            k.send(:private, :require) if private_require
          end
        end
      end
      END
    end
  end
end
