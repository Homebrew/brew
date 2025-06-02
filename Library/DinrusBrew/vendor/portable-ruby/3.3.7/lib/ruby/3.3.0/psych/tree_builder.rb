# frozen_string_literal: true
require_relative 'handler'

module Psych
  ###
  # This class works in conjunction with Psych::Parser to build an in-memory
  # parse tree that represents a YAML document.
  #
  # == Example
  #
  #   parser = Psych::Parser.new Psych::TreeBuilder.new
  #   parser.parse('--- foo')
  #   tree = parser.handler.root
  #
  # See Psych::Handler for documentation on the event methods used in this
  # class.
  class TreeBuilder < Psych::Handler
    # Returns the root node for the built tree
    attr_reader :root

    # Create a new TreeBuilder instance
    def initialize
      @stack = []
      @last  = nil
      @root  = nil

      @start_line   = nil
      @start_column = nil
      @end_line     = nil
      @end_column   = nil
    end

    def event_location(start_line, start_column, end_line, end_column)
      @start_line   = start_line
      @start_column = start_column
      @end_line     = end_line
      @end_column   = end_column
    end

    %w{
      Sequence
      Mapping
    }.each do |node|
      class_eval <<~RUBY, __FILE__, __LINE__ + 1
        def start_#{node.downcase}(anchor, tag, implicit, style)
          n = Nodes::#{node}.new(anchor, tag, implicit, style)
          set_start_location(n)
          @last.children << n
          push n
        end

        def end_#{node.downcase}
          n = pop
          set_end_location(n)
          n
        end
        RUBY
    end

    ###
    # Handles start_document events with +version+, +tag_directives+,
    # and +implicit+ styling.
    #
    # See Psych::Handler#start_document
    def start_document version, tag_directives, implicit
      n = Nodes::Document.new version, tag_directives, implicit
      set_start_location(n)
      @last.children << n
      push n
    end

    ###
    # Handles end_document events with +version+, +tag_directives+,
    # and +implicit+ styling.
    #
    # See Psych::Handler#start_document
    def end_document implicit_end = !streaming?
      @last.implicit_end = implicit_end
      n = pop
      set_end_location(n)
      n
    end

    def start_stream encoding
      @root = Nodes::Stream.new(encoding)
      set_start_location(@root)
      push @root
    end

    def end_stream
      n = pop
      set_end_location(n)
      n
    end

    def scalar value, anchor, tag, plain, quoted, style
      s = Nodes::Scalar.new(value,anchor,tag,plain,quoted,style)
      set_location(s)
      @last.children << s
      s
    end

    def alias anchor
      a = Nodes::Alias.new(anchor)
      set_location(a)
      @last.children << a
      a
    end

    private
    def push value
      @stack.push value
      @last = value
    end

    def pop
      x = @stack.pop
      @last = @stack.last
      x
    end

    def set_location(node)
      set_start_location(node)
      set_end_location(node)
    end

    def set_start_location(node)
      node.start_line   = @start_line
      node.start_column = @start_column
    end

    def set_end_location(node)
      node.end_line   = @end_line
      node.end_column = @end_column
    end
  end
end
