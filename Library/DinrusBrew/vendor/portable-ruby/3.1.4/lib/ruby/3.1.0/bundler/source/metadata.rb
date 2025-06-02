# frozen_string_literal: true

module Bundler
  class Source
    class Metadata < Source
      def specs
        @specs ||= Index.build do |idx|
          idx << Gem::Specification.new("Ruby\0", Gem.ruby_version)
          idx << Gem::Specification.new("RubyGems\0", Gem::VERSION) do |s|
            s.required_rubygems_version = Gem::Requirement.default
          end

          idx << Gem::Specification.new do |s|
            s.name     = "bundler"
            s.version  = VERSION
            s.license  = "MIT"
            s.platform = Gem::Platform::RUBY
            s.source   = self
            s.authors  = ["bundler team"]
            s.bindir   = "exe"
            s.homepage = "https://bundler.io"
            s.summary  = "The best way to manage your application's dependencies"
            s.executables = %w[bundle]
            # can't point to the actual gemspec or else the require paths will be wrong
            s.loaded_from = __dir__
          end

          if local_spec = Bundler.rubygems.find_bundler(VERSION)
            idx << local_spec
          end

          idx.each {|s| s.source = self }
        end
      end

      def options
        {}
      end

      def install(spec, _opts = {})
        print_using_message "Using #{version_message(spec)}"
        nil
      end

      def to_s
        "the local ruby installation"
      end

      def ==(other)
        self.class == other.class
      end
      alias_method :eql?, :==

      def hash
        self.class.hash
      end

      def version_message(spec)
        "#{spec.name} #{spec.version}"
      end
    end
  end
end
