require_relative "pub_grub/package"
require_relative "pub_grub/static_package_source"
require_relative "pub_grub/term"
require_relative "pub_grub/version_range"
require_relative "pub_grub/version_constraint"
require_relative "pub_grub/version_union"
require_relative "pub_grub/version_solver"
require_relative "pub_grub/incompatibility"
require_relative 'pub_grub/solve_failure'
require_relative 'pub_grub/failure_writer'
require_relative 'pub_grub/version'

module Bundler::PubGrub
  class << self
    attr_writer :logger

    def logger
      @logger || default_logger
    end

    private

    def default_logger
      require "logger"

      logger = ::Logger.new(STDERR)
      logger.level = $DEBUG ? ::Logger::DEBUG : ::Logger::WARN
      @logger = logger
    end
  end
end
