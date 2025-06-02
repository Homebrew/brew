# frozen_string_literal: true

require "set"
module Bundler
  class Graph
    GRAPH_NAME = :Gemfile

    def initialize(env, output_file, show_version = false, show_requirements = false, output_format = "png", without = [])
      @env               = env
      @output_file       = output_file
      @show_version      = show_version
      @show_requirements = show_requirements
      @output_format     = output_format
      @without_groups    = without.map(&:to_sym)

      @groups            = []
      @relations         = Hash.new {|h, k| h[k] = Set.new }
      @node_options      = {}
      @edge_options      = {}

      _populate_relations
    end

    attr_reader :groups, :relations, :node_options, :edge_options, :output_file, :output_format

    def viz
      GraphVizClient.new(self).run
    end

    private

    def _populate_relations
      parent_dependencies = _groups.values.to_set.flatten
      loop do
        break if parent_dependencies.empty?

        tmp = Set.new
        parent_dependencies.each do |dependency|
          child_dependencies = spec_for_dependency(dependency).runtime_dependencies.to_set
          @relations[dependency.name] += child_dependencies.map(&:name).to_set
          tmp += child_dependencies

          @node_options[dependency.name] = _make_label(dependency, :node)
          child_dependencies.each do |c_dependency|
            @edge_options["#{dependency.name}_#{c_dependency.name}"] = _make_label(c_dependency, :edge)
          end
        end
        parent_dependencies = tmp
      end
    end

    def _groups
      relations = Hash.new {|h, k| h[k] = Set.new }
      @env.current_dependencies.each do |dependency|
        dependency.groups.each do |group|
          next if @without_groups.include?(group)

          relations[group.to_s].add(dependency)
          @relations[group.to_s].add(dependency.name)

          @node_options[group.to_s] ||= _make_label(group, :node)
          @edge_options["#{group}_#{dependency.name}"] = _make_label(dependency, :edge)
        end
      end
      @groups = relations.keys
      relations
    end

    def _make_label(symbol_or_string_or_dependency, element_type)
      case element_type.to_sym
      when :node
        if symbol_or_string_or_dependency.is_a?(Gem::Dependency)
          label = symbol_or_string_or_dependency.name.dup
          label << "\n#{spec_for_dependency(symbol_or_string_or_dependency).version}" if @show_version
        else
          label = symbol_or_string_or_dependency.to_s
        end
      when :edge
        label = nil
        if symbol_or_string_or_dependency.respond_to?(:requirements_list) && @show_requirements
          tmp = symbol_or_string_or_dependency.requirements_list.join(", ")
          label = tmp if tmp != ">= 0"
        end
      else
        raise ArgumentError, "2nd argument is invalid"
      end
      label.nil? ? {} : { label: label }
    end

    def spec_for_dependency(dependency)
      @env.requested_specs.find {|s| s.name == dependency.name }
    end

    class GraphVizClient
      def initialize(graph_instance)
        @graph_name    = graph_instance.class::GRAPH_NAME
        @groups        = graph_instance.groups
        @relations     = graph_instance.relations
        @node_options  = graph_instance.node_options
        @edge_options  = graph_instance.edge_options
        @output_file   = graph_instance.output_file
        @output_format = graph_instance.output_format
      end

      def g
        @g ||= ::GraphViz.digraph(@graph_name, concentrate: true, normalize: true, nodesep: 0.55) do |g|
          g.edge[:weight]   = 2
          g.edge[:fontname] = g.node[:fontname] = "Arial, Helvetica, SansSerif"
          g.edge[:fontsize] = 12
        end
      end

      def run
        @groups.each do |group|
          g.add_nodes(
            group, {
              style: "filled",
              fillcolor: "#B9B9D5",
              shape: "box3d",
              fontsize: 16,
            }.merge(@node_options[group])
          )
        end

        @relations.each do |parent, children|
          children.each do |child|
            if @groups.include?(parent)
              g.add_nodes(child, { style: "filled", fillcolor: "#B9B9D5" }.merge(@node_options[child]))
              g.add_edges(parent, child, { constraint: false }.merge(@edge_options["#{parent}_#{child}"]))
            else
              g.add_nodes(child, @node_options[child])
              g.add_edges(parent, child, @edge_options["#{parent}_#{child}"])
            end
          end
        end

        if @output_format.to_s == "debug"
          $stdout.puts g.output none: String
          Bundler.ui.info "debugging bundle viz..."
        else
          begin
            g.output @output_format.to_sym => "#{@output_file}.#{@output_format}"
            Bundler.ui.info "#{@output_file}.#{@output_format}"
          rescue ArgumentError => e
            warn "Unsupported output format. See Ruby-Graphviz/lib/graphviz/constants.rb"
            raise e
          end
        end
      end
    end
  end
end
