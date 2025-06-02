# frozen_string_literal: true
require_relative 'yaml_events'

module Psych
  module JSON
    ###
    # Psych::JSON::TreeBuilder is an event based AST builder.  Events are sent
    # to an instance of Psych::JSON::TreeBuilder and a JSON AST is constructed.
    class TreeBuilder < Psych::TreeBuilder
      include Psych::JSON::YAMLEvents
    end
  end
end
