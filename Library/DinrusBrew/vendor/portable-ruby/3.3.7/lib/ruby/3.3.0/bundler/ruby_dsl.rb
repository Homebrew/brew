# frozen_string_literal: true

module Bundler
  module RubyDsl
    def ruby(*ruby_version)
      options = ruby_version.pop if ruby_version.last.is_a?(Hash)
      ruby_version.flatten!

      if options
        patchlevel = options[:patchlevel]
        engine = options[:engine]
        engine_version = options[:engine_version]

        raise GemfileError, "Please define :engine_version" if engine && engine_version.nil?
        raise GemfileError, "Please define :engine" if engine_version && engine.nil?

        if options[:file]
          raise GemfileError, "Do not pass version argument when using :file option" unless ruby_version.empty?
          ruby_version << normalize_ruby_file(options[:file])
        end

        if engine == "ruby" && engine_version && ruby_version != Array(engine_version)
          raise GemfileEvalError, "ruby_version must match the :engine_version for MRI"
        end
      end

      @ruby_version = RubyVersion.new(ruby_version, patchlevel, engine, engine_version)
    end

    # Support the various file formats found in .ruby-version files.
    #
    #     3.2.2
    #     ruby-3.2.2
    #
    # Also supports .tool-versions files for asdf. Lines not starting with "ruby" are ignored.
    #
    #     ruby 2.5.1 # comment is ignored
    #     ruby   2.5.1# close comment and extra spaces doesn't confuse
    #
    # Intentionally does not support `3.2.1@gemset` since rvm recommends using .ruby-gemset instead
    #
    # Loads the file relative to the dirname of the Gemfile itself.
    def normalize_ruby_file(filename)
      file_content = Bundler.read_file(gemfile.dirname.join(filename))
      # match "ruby-3.2.2" or "ruby   3.2.2" capturing version string up to the first space or comment
      if /^ruby(-|\s+)([^\s#]+)/.match(file_content)
        $2
      else
        file_content.strip
      end
    end
  end
end
