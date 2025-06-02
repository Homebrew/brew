# frozen_string_literal: true
require_relative "../command"

unless defined? Gem::Commands::ServerCommand
  class Gem::Commands::ServerCommand < Gem::Command
    def initialize
      super("server", "Starts up a web server that hosts the RDoc (requires rubygems-server)")
      begin
        Gem::Specification.find_by_name("rubygems-server").activate
      rescue Gem::LoadError
        # no-op
      end
    end

    def description # :nodoc:
      <<-EOF
The server command has been moved to the rubygems-server gem.
      EOF
    end

    def execute
      alert_error "Install the rubygems-server gem for the server command"
    end
  end
end
