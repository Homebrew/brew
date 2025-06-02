# frozen_string_literal: true

module Bundler
  class CLI::Open
    attr_reader :options, :name
    def initialize(options, name)
      @options = options
      @name = name
    end

    def run
      editor = [ENV["BUNDLER_EDITOR"], ENV["VISUAL"], ENV["EDITOR"]].find {|e| !e.nil? && !e.empty? }
      return Bundler.ui.info("To open a bundled gem, set $EDITOR or $BUNDLER_EDITOR") unless editor
      return unless spec = Bundler::CLI::Common.select_spec(name, :regex_match)
      if spec.default_gem?
        Bundler.ui.info "Unable to open #{name} because it's a default gem, so the directory it would normally be installed to does not exist."
      else
        path = spec.full_gem_path
        Dir.chdir(path) do
          require "shellwords"
          command = Shellwords.split(editor) + [path]
          Bundler.with_original_env do
            system(*command)
          end || Bundler.ui.info("Could not run '#{command.join(" ")}'")
        end
      end
    end
  end
end
