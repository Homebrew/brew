# frozen_string_literal: true

module RBS
  class TypeAliasDependency
    attr_reader :env

    # Direct dependencies corresponds to a directed graph
    # with vertices as types and directions based on assignment of types
    attr_reader :direct_dependencies
    # A hash which stores the transitive closure
    # of the directed graph
    attr_reader :dependencies

    def initialize(env:)
      @env = env
    end

    # Check if an alias type definition is circular & prohibited
    def circular_definition?(alias_name)
      # Construct transitive closure, if not constructed already
      transitive_closure() unless @dependencies

      # Check for recursive type alias
      @dependencies[alias_name][alias_name]
    end

    def build_dependencies
      return if @direct_dependencies

      # Initialize hash(a directed graph)
      @direct_dependencies = {}
      # Initialize dependencies as an empty hash
      @dependencies = {}
      # Iterate over alias declarations inserted into environment
      env.alias_decls.each do |name, entry|
        # Construct a directed graph by recursively extracting type aliases
        @direct_dependencies[name] = direct_dependency(entry.decl.type)
        # Initialize dependencies with an empty hash
        @dependencies[name] = {}
      end
    end

    def transitive_closure
      # Construct a graph of direct dependencies
      build_dependencies()
      # Construct transitive closure by using DFS(recursive technique)
      @direct_dependencies.each_key do |name|
        dependency(name, name)
      end
    end

    private

    # Constructs directed graph recursively
    def direct_dependency(type, result = Set[])
      case type
      when RBS::Types::Union, RBS::Types::Intersection, RBS::Types::Optional
        # Iterate over nested types & extract type aliases recursively
        type.each_type do |nested_type|
          direct_dependency(nested_type, result)
        end
      when RBS::Types::Alias
        # Append type name if the type is an alias
        result << type.name
      end

      result
    end

    # Recursive function to construct transitive closure
    def dependency(start, vertex, nested = nil)
      if (start == vertex)
        if (@direct_dependencies[start].include?(vertex) || nested)
          # Mark a vertex as connected to itself
          # if it is connected as an edge || a path(traverse multiple edges)
          @dependencies[start][vertex] = true
        end
      else
        # Mark a pair of vertices as connected while recursively performing DFS
        @dependencies[start][vertex] = true
      end

      # Iterate over the direct dependencies of the vertex
      @direct_dependencies[vertex]&.each do |type_name|
        # Invoke the function unless it is already checked
        dependency(start, type_name, start == type_name) unless @dependencies[start][type_name]
      end
    end
  end
end
