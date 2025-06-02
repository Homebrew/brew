# frozen_string_literal: true
require_relative 'ruby_events'
require_relative 'yaml_events'

module Psych
  module JSON
    class Stream < Psych::Visitors::JSONTree
      include Psych::JSON::RubyEvents
      include Psych::Streaming
      extend Psych::Streaming::ClassMethods

      class Emitter < Psych::Stream::Emitter # :nodoc:
        include Psych::JSON::YAMLEvents
      end
    end
  end
end
