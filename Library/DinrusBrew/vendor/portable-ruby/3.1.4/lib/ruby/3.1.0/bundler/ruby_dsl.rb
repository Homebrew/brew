# frozen_string_literal: true

module Bundler
  module RubyDsl
    def ruby(*ruby_version)
      options = ruby_version.last.is_a?(Hash) ? ruby_version.pop : {}
      ruby_version.flatten!
      raise GemfileError, "Please define :engine_version" if options[:engine] && options[:engine_version].nil?
      raise GemfileError, "Please define :engine" if options[:engine_version] && options[:engine].nil?

      if options[:engine] == "ruby" && options[:engine_version] &&
         ruby_version != Array(options[:engine_version])
        raise GemfileEvalError, "ruby_version must match the :engine_version for MRI"
      end
      @ruby_version = RubyVersion.new(ruby_version, options[:patchlevel], options[:engine], options[:engine_version])
    end
  end
end
