# frozen_string_literal: true

module Bundler
  class CLI::Fund
    attr_reader :options

    def initialize(options)
      @options = options
    end

    def run
      Bundler.definition.validate_runtime!

      groups = Array(options[:group]).map(&:to_sym)

      deps = if groups.any?
        Bundler.definition.dependencies_for(groups)
      else
        Bundler.definition.current_dependencies
      end

      fund_info = deps.each_with_object([]) do |dep, arr|
        spec = Bundler.definition.specs[dep.name].first
        if spec.metadata.key?("funding_uri")
          arr << "* #{spec.name} (#{spec.version})\n  Funding: #{spec.metadata["funding_uri"]}"
        end
      end

      if fund_info.empty?
        Bundler.ui.info "None of the installed gems you directly depend on are looking for funding."
      else
        Bundler.ui.info fund_info.join("\n")
      end
    end
  end
end
