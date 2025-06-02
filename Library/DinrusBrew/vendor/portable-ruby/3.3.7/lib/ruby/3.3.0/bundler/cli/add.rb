# frozen_string_literal: true

module Bundler
  class CLI::Add
    attr_reader :gems, :options, :version

    def initialize(options, gems)
      @gems = gems
      @options = options
      @options[:group] = options[:group].split(",").map(&:strip) unless options[:group].nil?
      @version = options[:version].split(",").map(&:strip) unless options[:version].nil?
    end

    def run
      validate_options!
      inject_dependencies
      perform_bundle_install unless options["skip-install"]
    end

    private

    def perform_bundle_install
      Installer.install(Bundler.root, Bundler.definition)
      Bundler.load.cache if Bundler.app_cache.exist?
    end

    def inject_dependencies
      dependencies = gems.map {|g| Bundler::Dependency.new(g, version, options) }

      Injector.inject(dependencies,
        conservative_versioning: options[:version].nil?, # Perform conservative versioning only when version is not specified
        optimistic: options[:optimistic],
        strict: options[:strict])
    end

    def validate_options!
      raise InvalidOption, "You cannot specify `--strict` and `--optimistic` at the same time." if options[:strict] && options[:optimistic]

      # raise error when no gems are specified
      raise InvalidOption, "Please specify gems to add." if gems.empty?

      version.to_a.each do |v|
        raise InvalidOption, "Invalid gem requirement pattern '#{v}'" unless Gem::Requirement::PATTERN.match?(v.to_s)
      end
    end
  end
end
