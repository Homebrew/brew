# frozen_string_literal: true

require_relative "package"

module Bundler
  class Resolver
    class Base
      attr_reader :packages, :requirements, :source_requirements

      def initialize(source_requirements, dependencies, base, platforms, options)
        @source_requirements = source_requirements

        @base = base

        @packages = Hash.new do |hash, name|
          hash[name] = Package.new(name, platforms, **options)
        end

        @requirements = dependencies.map do |dep|
          dep_platforms = dep.gem_platforms(platforms)

          # Dependencies scoped to external platforms are ignored
          next if dep_platforms.empty?

          name = dep.name

          @packages[name] = Package.new(name, dep_platforms, **options.merge(dependency: dep))

          dep
        end.compact
      end

      def specs_compatible_with(result)
        @base.specs_compatible_with(result)
      end

      def [](name)
        @base[name]
      end

      def delete(specs)
        @base.delete(specs)
      end

      def get_package(name)
        @packages[name]
      end

      def base_requirements
        @base_requirements ||= build_base_requirements
      end

      def unlock_names(names)
        indirect_pins = indirect_pins(names)

        if indirect_pins.any?
          loosen_names(indirect_pins)
        else
          pins = pins(names)

          if pins.any?
            loosen_names(pins)
          else
            unrestrict_names(names)
          end
        end
      end

      def include_prereleases(names)
        names.each do |name|
          get_package(name).consider_prereleases!
        end
      end

      def include_remote_specs(names)
        names.each do |name|
          get_package(name).consider_remote_versions!
        end
      end

      private

      def indirect_pins(names)
        names.select {|name| @base_requirements[name].exact? && @requirements.none? {|dep| dep.name == name } }
      end

      def pins(names)
        names.select {|name| @base_requirements[name].exact? }
      end

      def loosen_names(names)
        names.each do |name|
          version = @base_requirements[name].requirements.first[1]

          @base_requirements[name] = Gem::Requirement.new(">= #{version}")

          @base.delete_by_name(name)
        end
      end

      def unrestrict_names(names)
        names.each do |name|
          @base_requirements.delete(name)
        end
      end

      def build_base_requirements
        base_requirements = {}
        @base.each do |ls|
          req = Gem::Requirement.new(ls.version)
          base_requirements[ls.name] = req
        end
        base_requirements
      end
    end
  end
end
