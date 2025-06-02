# frozen_string_literal: true

begin
  gem 'rdoc', '~> 6.4.0'
  require 'rdoc_plugin/parser'
  module RDoc
    class Parser
      class RBS < Parser
        parse_files_matching(/\.rbs$/)
        def scan
          ::RBS::RDocPlugin::Parser.new(@top_level, @content).scan
        end
      end
    end
  end
rescue Gem::LoadError
    # Error :sad:
rescue Exception
    # Exception :sad:
end
