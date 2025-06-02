# frozen_string_literal: false
require_relative "utils"

module RSS
  module XML
    class Element
      include Enumerable

      attr_reader :name, :prefix, :uri, :attributes, :children
      def initialize(name, prefix=nil, uri=nil, attributes={}, children=[])
        @name = name
        @prefix = prefix
        @uri = uri
        @attributes = attributes
        if children.is_a?(String) or !children.respond_to?(:each)
          @children = [children]
        else
          @children = children
        end
      end

      def [](name)
        @attributes[name]
      end

      def []=(name, value)
        @attributes[name] = value
      end

      def <<(child)
        @children << child
      end

      def each(&block)
        @children.each(&block)
      end

      def ==(other)
        other.kind_of?(self.class) and
          @name == other.name and
          @uri == other.uri and
          @attributes == other.attributes and
          @children == other.children
      end

      def to_s
        rv = "<#{full_name}"
        attributes.each do |key, value|
          rv << " #{Utils.html_escape(key)}=\"#{Utils.html_escape(value)}\""
        end
        if children.empty?
          rv << "/>"
        else
          rv << ">"
          children.each do |child|
            rv << child.to_s
          end
          rv << "</#{full_name}>"
        end
        rv
      end

      def full_name
        if @prefix
          "#{@prefix}:#{@name}"
        else
          @name
        end
      end
    end
  end
end
