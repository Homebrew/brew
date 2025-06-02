# frozen_string_literal: true

module Bundler
  class CLI::Clean
    attr_reader :options

    def initialize(options)
      @options = options
    end

    def run
      require_path_or_force unless options[:"dry-run"]
      Bundler.load.clean(options[:"dry-run"])
    end

    protected

    def require_path_or_force
      return unless Bundler.use_system_gems? && !options[:force]
      raise InvalidOption, "Cleaning all the gems on your system is dangerous! " \
        "If you're sure you want to remove every system gem not in this " \
        "bundle, run `bundle clean --force`."
    end
  end
end
