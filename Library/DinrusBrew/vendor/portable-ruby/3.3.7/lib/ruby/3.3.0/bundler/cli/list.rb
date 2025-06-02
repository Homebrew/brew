# frozen_string_literal: true

module Bundler
  class CLI::List
    def initialize(options)
      @options = options
      @without_group = options["without-group"].map(&:to_sym)
      @only_group = options["only-group"].map(&:to_sym)
    end

    def run
      raise InvalidOption, "The `--only-group` and `--without-group` options cannot be used together" if @only_group.any? && @without_group.any?

      raise InvalidOption, "The `--name-only` and `--paths` options cannot be used together" if @options["name-only"] && @options[:paths]

      specs = if @only_group.any? || @without_group.any?
        filtered_specs_by_groups
      else
        begin
          Bundler.load.specs
        rescue GemNotFound => e
          Bundler.ui.error e.message
          Bundler.ui.warn "Install missing gems with `bundle install`."
          exit 1
        end
      end.reject {|s| s.name == "bundler" }.sort_by(&:name)

      return Bundler.ui.info "No gems in the Gemfile" if specs.empty?

      return specs.each {|s| Bundler.ui.info s.name } if @options["name-only"]
      return specs.each {|s| Bundler.ui.info s.full_gem_path } if @options["paths"]

      Bundler.ui.info "Gems included by the bundle:"

      specs.each {|s| Bundler.ui.info "  * #{s.name} (#{s.version}#{s.git_version})" }

      Bundler.ui.info "Use `bundle info` to print more detailed information about a gem"
    end

    private

    def verify_group_exists(groups)
      (@without_group + @only_group).each do |group|
        raise InvalidOption, "`#{group}` group could not be found." unless groups.include?(group)
      end
    end

    def filtered_specs_by_groups
      definition = Bundler.definition
      groups = definition.groups

      verify_group_exists(groups)

      show_groups =
        if @without_group.any?
          groups.reject {|g| @without_group.include?(g) }
        elsif @only_group.any?
          groups.select {|g| @only_group.include?(g) }
        else
          groups
        end.map(&:to_sym)

      definition.specs_for(show_groups)
    end
  end
end
