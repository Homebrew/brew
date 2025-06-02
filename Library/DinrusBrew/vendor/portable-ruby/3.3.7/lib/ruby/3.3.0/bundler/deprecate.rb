# frozen_string_literal: true

begin
  require "rubygems/deprecate"
rescue LoadError
  # it's fine if it doesn't exist on the current RubyGems...
  nil
end

module Bundler
  # If Bundler::Deprecate is an autoload constant, we need to define it
  if defined?(Bundler::Deprecate) && !autoload?(:Deprecate)
    # nothing to do!
  elsif defined? ::Deprecate
    Deprecate = ::Deprecate
  elsif defined? Gem::Deprecate
    Deprecate = Gem::Deprecate
  else
    class Deprecate
    end
  end

  unless Deprecate.respond_to?(:skip_during)
    def Deprecate.skip_during
      original = skip
      self.skip = true
      yield
    ensure
      self.skip = original
    end
  end

  unless Deprecate.respond_to?(:skip)
    def Deprecate.skip
      @skip ||= false
    end
  end

  unless Deprecate.respond_to?(:skip=)
    def Deprecate.skip=(skip)
      @skip = skip
    end
  end
end
