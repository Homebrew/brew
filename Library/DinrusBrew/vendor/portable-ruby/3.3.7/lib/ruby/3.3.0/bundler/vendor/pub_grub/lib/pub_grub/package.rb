# frozen_string_literal: true

module Bundler::PubGrub
  class Package

    attr_reader :name

    def initialize(name)
      @name = name
    end

    def inspect
      "#<#{self.class} #{name.inspect}>"
    end

    def <=>(other)
      name <=> other.name
    end

    ROOT = Package.new(:root)
    ROOT_VERSION = 0

    def self.root
      ROOT
    end

    def self.root_version
      ROOT_VERSION
    end

    def self.root?(package)
      if package.respond_to?(:root?)
        package.root?
      else
        package == root
      end
    end

    def to_s
      name.to_s
    end
  end
end
