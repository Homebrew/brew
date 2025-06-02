# frozen_string_literal: true

require_relative "../command"

unless defined? Gem::Commands::MirrorCommand
  class Gem::Commands::MirrorCommand < Gem::Command
    def initialize
      super("mirror", "Mirror all gem files (requires rubygems-mirror)")
      begin
        Gem::Specification.find_by_name("rubygems-mirror").activate
      rescue Gem::LoadError
        # no-op
      end
    end

    def description # :nodoc:
      <<-EOF
The mirror command has been moved to the rubygems-mirror gem.
      EOF
    end

    def execute
      alert_error "Install the rubygems-mirror gem for the mirror command"
    end
  end
end
