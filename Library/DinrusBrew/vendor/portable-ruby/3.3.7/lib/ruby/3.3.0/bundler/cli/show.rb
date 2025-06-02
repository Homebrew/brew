# frozen_string_literal: true

module Bundler
  class CLI::Show
    attr_reader :options, :gem_name, :latest_specs
    def initialize(options, gem_name)
      @options = options
      @gem_name = gem_name
      @verbose = options[:verbose] || options[:outdated]
      @latest_specs = fetch_latest_specs if @verbose
    end

    def run
      Bundler.ui.silence do
        Bundler.definition.validate_runtime!
        Bundler.load.lock
      end

      if gem_name
        if gem_name == "bundler"
          path = File.expand_path("../../..", __dir__)
        else
          spec = Bundler::CLI::Common.select_spec(gem_name, :regex_match)
          return unless spec
          path = spec.full_gem_path
          unless File.directory?(path)
            return Bundler.ui.warn "The gem #{gem_name} has been deleted. It was installed at: #{path}"
          end
        end
        return Bundler.ui.info(path)
      end

      if options[:paths]
        Bundler.load.specs.sort_by(&:name).map do |s|
          Bundler.ui.info s.full_gem_path
        end
      else
        Bundler.ui.info "Gems included by the bundle:"
        Bundler.load.specs.sort_by(&:name).each do |s|
          desc = "  * #{s.name} (#{s.version}#{s.git_version})"
          if @verbose
            latest = latest_specs.find {|l| l.name == s.name }
            Bundler.ui.info <<~END
              #{desc.lstrip}
              \tSummary:  #{s.summary || "No description available."}
              \tHomepage: #{s.homepage || "No website available."}
              \tStatus:   #{outdated?(s, latest) ? "Outdated - #{s.version} < #{latest.version}" : "Up to date"}
            END
          else
            Bundler.ui.info desc
          end
        end
      end
    end

    private

    def fetch_latest_specs
      definition = Bundler.definition(true)
      if options[:outdated]
        Bundler.ui.info "Fetching remote specs for outdated check...\n\n"
        Bundler.ui.silence { definition.resolve_remotely! }
      else
        definition.resolve_with_cache!
      end
      Bundler.reset!
      definition.specs
    end

    def outdated?(current, latest)
      return false unless latest
      Gem::Version.new(current.version) < Gem::Version.new(latest.version)
    end
  end
end
