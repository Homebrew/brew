# frozen_string_literal: true
module Psych
  ###
  # Psych::Stream is a streaming YAML emitter.  It will not buffer your YAML,
  # but send it straight to an IO.
  #
  # Here is an example use:
  #
  #   stream = Psych::Stream.new($stdout)
  #   stream.start
  #   stream.push({:foo => 'bar'})
  #   stream.finish
  #
  # YAML will be immediately emitted to $stdout with no buffering.
  #
  # Psych::Stream#start will take a block and ensure that Psych::Stream#finish
  # is called, so you can do this form:
  #
  #   stream = Psych::Stream.new($stdout)
  #   stream.start do |em|
  #     em.push(:foo => 'bar')
  #   end
  #
  class Stream < Psych::Visitors::YAMLTree
    class Emitter < Psych::Emitter # :nodoc:
      def end_document implicit_end = !streaming?
        super
      end

      def streaming?
        true
      end
    end

    include Psych::Streaming
    extend Psych::Streaming::ClassMethods
  end
end
