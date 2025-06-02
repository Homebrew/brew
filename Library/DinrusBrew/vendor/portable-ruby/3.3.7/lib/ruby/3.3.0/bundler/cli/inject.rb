# frozen_string_literal: true

module Bundler
  class CLI::Inject
    attr_reader :options, :name, :version, :group, :source, :gems
    def initialize(options, name, version)
      @options = options
      @name = name
      @version = version || last_version_number
      @group = options[:group].split(",") unless options[:group].nil?
      @source = options[:source]
      @gems = []
    end

    def run
      # The required arguments allow Thor to give useful feedback when the arguments
      # are incorrect. This adds those first two arguments onto the list as a whole.
      gems.unshift(source).unshift(group).unshift(version).unshift(name)

      # Build an array of Dependency objects out of the arguments
      deps = []
      # when `inject` support addition of more than one gem, then this loop will
      # help. Currently this loop is running once.
      gems.each_slice(4) do |gem_name, gem_version, gem_group, gem_source|
        ops = Gem::Requirement::OPS.map {|key, _val| key }
        has_op = ops.any? {|op| gem_version.start_with? op }
        gem_version = "~> #{gem_version}" unless has_op
        deps << Bundler::Dependency.new(gem_name, gem_version, "group" => gem_group, "source" => gem_source)
      end

      added = Injector.inject(deps, options)

      if added.any?
        Bundler.ui.confirm "Added to Gemfile:"
        Bundler.ui.confirm(added.map do |d|
          name = "'#{d.name}'"
          requirement = ", '#{d.requirement}'"
          group = ", :group => #{d.groups.inspect}" if d.groups != Array(:default)
          source = ", :source => '#{d.source}'" unless d.source.nil?
          %(gem #{name}#{requirement}#{group}#{source})
        end.join("\n"))
      else
        Bundler.ui.confirm "All gems were already present in the Gemfile"
      end
    end

    private

    def last_version_number
      definition = Bundler.definition(true)
      definition.resolve_remotely!
      specs = definition.index[name].sort_by(&:version)
      unless options[:pre]
        specs.delete_if {|b| b.respond_to?(:version) && b.version.prerelease? }
      end
      spec = specs.last
      spec.version.to_s
    end
  end
end
