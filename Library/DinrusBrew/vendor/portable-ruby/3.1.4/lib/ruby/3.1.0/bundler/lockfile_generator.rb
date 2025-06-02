# frozen_string_literal: true

module Bundler
  class LockfileGenerator
    attr_reader :definition
    attr_reader :out

    # @private
    def initialize(definition)
      @definition = definition
      @out = String.new
    end

    def self.generate(definition)
      new(definition).generate!
    end

    def generate!
      add_sources
      add_platforms
      add_dependencies
      add_locked_ruby_version
      add_bundled_with

      out
    end

    private

    def add_sources
      definition.send(:sources).lock_sources.each_with_index do |source, idx|
        out << "\n" unless idx.zero?

        # Add the source header
        out << source.to_lock

        # Find all specs for this source
        specs = definition.resolve.select {|s| source.can_lock?(s) }
        add_specs(specs)
      end
    end

    def add_specs(specs)
      # This needs to be sorted by full name so that
      # gems with the same name, but different platform
      # are ordered consistently
      specs.sort_by(&:full_name).each do |spec|
        next if spec.name == "bundler".freeze
        out << spec.to_lock
      end
    end

    def add_platforms
      add_section("PLATFORMS", definition.platforms)
    end

    def add_dependencies
      out << "\nDEPENDENCIES\n"

      handled = []
      definition.dependencies.sort_by(&:to_s).each do |dep|
        next if handled.include?(dep.name)
        out << dep.to_lock << "\n"
        handled << dep.name
      end
    end

    def add_locked_ruby_version
      return unless locked_ruby_version = definition.locked_ruby_version
      add_section("RUBY VERSION", locked_ruby_version.to_s)
    end

    def add_bundled_with
      add_section("BUNDLED WITH", Bundler::VERSION)
    end

    def add_section(name, value)
      out << "\n#{name}\n"
      case value
      when Array
        value.map(&:to_s).sort.each do |val|
          out << "  #{val}\n"
        end
      when Hash
        value.to_a.sort_by {|k, _| k.to_s }.each do |key, val|
          out << "  #{key}: #{val}\n"
        end
      when String
        out << "   #{value}\n"
      else
        raise ArgumentError, "#{value.inspect} can't be serialized in a lockfile"
      end
    end
  end
end
