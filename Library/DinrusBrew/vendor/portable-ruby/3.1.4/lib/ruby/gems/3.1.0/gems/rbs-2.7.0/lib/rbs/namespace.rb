# frozen_string_literal: true

module RBS
  class Namespace
    attr_reader :path

    def initialize(path:, absolute:)
      @path = path
      @absolute = absolute ? true : false
    end

    def self.empty
      @empty ||= new(path: [], absolute: false)
    end

    def self.root
      @root ||= new(path: [], absolute: true)
    end

    def +(other)
      if other.absolute?
        other
      else
        self.class.new(path: path + other.path, absolute: absolute?)
      end
    end

    def append(component)
      self.class.new(path: path + [component], absolute: absolute?)
    end

    def parent
      @parent ||= begin
        raise "Parent with empty namespace" if empty?
        self.class.new(path: path.take(path.size - 1), absolute: absolute?)
      end
    end

    def absolute?
      @absolute
    end

    def relative?
      !absolute?
    end

    def absolute!
      self.class.new(path: path, absolute: true)
    end

    def relative!
      self.class.new(path: path, absolute: false)
    end

    def empty?
      path.empty?
    end

    def ==(other)
      other.is_a?(Namespace) && other.path == path && other.absolute? == absolute?
    end

    alias eql? ==

    def hash
      path.hash ^ absolute?.hash
    end

    def split
      last = path.last or return
      parent = self.parent
      [parent, last]
    end

    def to_s
      if empty?
        absolute? ? "::" : ""
      else
        s = path.join("::")
        absolute? ? "::#{s}::" : "#{s}::"
      end
    end

    def to_type_name
      parent, name = split

      raise unless name
      raise unless parent

      TypeName.new(name: name, namespace: parent)
    end

    def self.parse(string)
      if string.start_with?("::")
        new(path: string.split("::").drop(1).map(&:to_sym), absolute: true)
      else
        new(path: string.split("::").map(&:to_sym), absolute: false)
      end
    end

    def ascend
      if block_given?
        current = self

        until current.empty?
          yield current
          current = _ = current.parent
        end

        yield current

        self
      else
        enum_for(:ascend)
      end
    end
  end
end

module Kernel
  def Namespace(name)
    RBS::Namespace.parse(name)
  end
end
