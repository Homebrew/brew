# frozen_string_literal: true
require_relative '../handler'

module Psych
  module Handlers
    ###
    # This handler will capture an event and record the event.  Recorder events
    # are available vial Psych::Handlers::Recorder#events.
    #
    # For example:
    #
    #   recorder = Psych::Handlers::Recorder.new
    #   parser = Psych::Parser.new recorder
    #   parser.parse '--- foo'
    #
    #   recorder.events # => [list of events]
    #
    #   # Replay the events
    #
    #   emitter = Psych::Emitter.new $stdout
    #   recorder.events.each do |m, args|
    #     emitter.send m, *args
    #   end

    class Recorder < Psych::Handler
      attr_reader :events

      def initialize
        @events = []
        super
      end

      EVENTS.each do |event|
        define_method event do |*args|
          @events << [event, args]
        end
      end
    end
  end
end
