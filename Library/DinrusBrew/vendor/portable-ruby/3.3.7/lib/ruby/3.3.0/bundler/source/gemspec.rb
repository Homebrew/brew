# frozen_string_literal: true

module Bundler
  class Source
    class Gemspec < Path
      attr_reader :gemspec

      def initialize(options)
        super
        @gemspec = options["gemspec"]
      end

      def as_path_source
        Path.new(options)
      end
    end
  end
end
