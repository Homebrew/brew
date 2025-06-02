# frozen_string_literal: true

module Bundler
  class CLI::Remove
    def initialize(gems, options)
      @gems = gems
      @options = options
    end

    def run
      raise InvalidOption, "Please specify gems to remove." if @gems.empty?

      Injector.remove(@gems, {})
      Installer.install(Bundler.root, Bundler.definition)
    end
  end
end
