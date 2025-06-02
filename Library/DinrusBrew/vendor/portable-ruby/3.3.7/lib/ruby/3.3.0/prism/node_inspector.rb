# frozen_string_literal: true

module Prism
  # This object is responsible for generating the output for the inspect method
  # implementations of child nodes.
  class NodeInspector # :nodoc:
    attr_reader :prefix, :output

    def initialize(prefix = "")
      @prefix = prefix
      @output = +""
    end

    # Appends a line to the output with the current prefix.
    def <<(line)
      output << "#{prefix}#{line}"
    end

    # This generates a string that is used as the header of the inspect output
    # for any given node.
    def header(node)
      output = +"@ #{node.class.name.split("::").last} ("
      output << "location: (#{node.location.start_line},#{node.location.start_column})-(#{node.location.end_line},#{node.location.end_column})"
      output << ", newline: true" if node.newline?
      output << ")\n"
      output
    end

    # Generates a string that represents a list of nodes. It handles properly
    # using the box drawing characters to make the output look nice.
    def list(prefix, nodes)
      output = +"(length: #{nodes.length})\n"
      last_index = nodes.length - 1

      nodes.each_with_index do |node, index|
        pointer, preadd = (index == last_index) ? ["└── ", "    "] : ["├── ", "│   "]
        node_prefix = "#{prefix}#{preadd}"
        output << node.inspect(NodeInspector.new(node_prefix)).sub(node_prefix, "#{prefix}#{pointer}")
      end

      output
    end

    # Generates a string that represents a location field on a node.
    def location(value)
      if value
        "(#{value.start_line},#{value.start_column})-(#{value.end_line},#{value.end_column}) = #{value.slice.inspect}"
      else
        "∅"
      end
    end

    # Generates a string that represents a child node.
    def child_node(node, append)
      node.inspect(child_inspector(append)).delete_prefix(prefix)
    end

    # Returns a new inspector that can be used to inspect a child node.
    def child_inspector(append)
      NodeInspector.new("#{prefix}#{append}")
    end

    # Returns the output as a string.
    def to_str
      output
    end
  end
end
