# frozen_string_literal: true

module Bundler
  class CLI::Init
    attr_reader :options
    def initialize(options)
      @options = options
    end

    def run
      if File.exist?(gemfile)
        Bundler.ui.error "#{gemfile} already exists at #{File.expand_path(gemfile)}"
        exit 1
      end

      unless File.writable?(Dir.pwd)
        Bundler.ui.error "Can not create #{gemfile} as the current directory is not writable."
        exit 1
      end

      if options[:gemspec]
        gemspec = File.expand_path(options[:gemspec])
        unless File.exist?(gemspec)
          Bundler.ui.error "Gem specification #{gemspec} doesn't exist"
          exit 1
        end

        spec = Bundler.load_gemspec_uncached(gemspec)

        File.open(gemfile, "wb") do |file|
          file << "# Generated from #{gemspec}\n"
          file << spec.to_gemfile
        end
      else
        File.open(File.expand_path("../templates/#{gemfile}", __dir__), "r") do |template|
          File.open(gemfile, "wb") do |destination|
            IO.copy_stream(template, destination)
          end
        end
      end

      puts "Writing new #{gemfile} to #{SharedHelpers.pwd}/#{gemfile}"
    end

    private

    def gemfile
      @gemfile ||= Bundler.preferred_gemfile_name
    end
  end
end
