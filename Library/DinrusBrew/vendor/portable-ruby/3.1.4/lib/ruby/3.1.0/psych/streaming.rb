# frozen_string_literal: true
module Psych
  module Streaming
    module ClassMethods
      ###
      # Create a new streaming emitter.  Emitter will print to +io+.  See
      # Psych::Stream for an example.
      def new io
        emitter      = const_get(:Emitter).new(io)
        class_loader = ClassLoader.new
        ss           = ScalarScanner.new class_loader
        super(emitter, ss, {})
      end
    end

    ###
    # Start streaming using +encoding+
    def start encoding = Nodes::Stream::UTF8
      super.tap { yield self if block_given?  }
    ensure
      finish if block_given?
    end

    private
    def register target, obj
    end
  end
end
