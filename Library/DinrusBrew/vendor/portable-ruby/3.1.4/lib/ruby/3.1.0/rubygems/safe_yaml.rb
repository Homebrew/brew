module Gem

  ###
  # This module is used for safely loading YAML specs from a gem.  The
  # `safe_load` method defined on this module is specifically designed for
  # loading Gem specifications.  For loading other YAML safely, please see
  # Psych.safe_load

  module SafeYAML
    PERMITTED_CLASSES = %w[
      Symbol
      Time
      Date
      Gem::Dependency
      Gem::Platform
      Gem::Requirement
      Gem::Specification
      Gem::Version
      Gem::Version::Requirement
    ].freeze

    PERMITTED_SYMBOLS = %w[
      development
      runtime
    ].freeze

    if ::Psych.respond_to? :safe_load
      def self.safe_load(input)
        if Gem::Version.new(Psych::VERSION) >= Gem::Version.new("3.1.0.pre1")
          ::Psych.safe_load(input, permitted_classes: PERMITTED_CLASSES, permitted_symbols: PERMITTED_SYMBOLS, aliases: true)
        else
          ::Psych.safe_load(input, PERMITTED_CLASSES, PERMITTED_SYMBOLS, true)
        end
      end

      def self.load(input)
        if Gem::Version.new(Psych::VERSION) >= Gem::Version.new("3.1.0.pre1")
          ::Psych.safe_load(input, permitted_classes: [::Symbol])
        else
          ::Psych.safe_load(input, [::Symbol])
        end
      end
    else
      unless Gem::Deprecate.skip
        warn "Psych safe loading is not available. Please upgrade psych to a version that supports safe loading (>= 2.0)."
      end

      def self.safe_load(input, *args)
        ::Psych.load input
      end

      def self.load(input)
        ::Psych.load input
      end
    end
  end
end
