require_relative 'package'
require_relative 'rubygems'
require_relative 'version_constraint'
require_relative 'incompatibility'
require_relative 'basic_package_source'

module Bundler::PubGrub
  class StaticPackageSource < BasicPackageSource
    class DSL
      def initialize(packages, root_deps)
        @packages = packages
        @root_deps = root_deps
      end

      def root(deps:)
        @root_deps.update(deps)
      end

      def add(name, version, deps: {})
        version = Gem::Version.new(version)
        @packages[name] ||= {}
        raise ArgumentError, "#{name} #{version} declared twice" if @packages[name].key?(version)
        @packages[name][version] = clean_deps(name, version, deps)
      end

      private

      # Exclude redundant self-referencing dependencies
      def clean_deps(name, version, deps)
        deps.reject {|dep_name, req| name == dep_name && Bundler::PubGrub::RubyGems.parse_range(req).include?(version) }
      end
    end

    def initialize
      @root_deps = {}
      @packages = {}

      yield DSL.new(@packages, @root_deps)

      super()
    end

    def all_versions_for(package)
      @packages[package].keys
    end

    def root_dependencies
      @root_deps
    end

    def dependencies_for(package, version)
      @packages[package][version]
    end

    def parse_dependency(package, dependency)
      return false unless @packages.key?(package)

      Bundler::PubGrub::RubyGems.parse_constraint(package, dependency)
    end
  end
end
