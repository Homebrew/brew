module BinData
  # reference to the current tracer
  @tracer ||= nil

  class Tracer #:nodoc:
    def initialize(io)
      @trace_io = io
    end

    def trace(msg)
      @trace_io.puts(msg)
    end

    def trace_obj(obj_name, val)
      if val.length > 30
        val = val.slice(0..30) + "..."
      end

      trace "#{obj_name} => #{val}"
    end
  end

  # Turn on trace information when reading a BinData object.
  # If +block+ is given then the tracing only occurs for that block.
  # This is useful for debugging a BinData declaration.
  def trace_reading(io = STDERR)
    @tracer = Tracer.new(io)
    [BasePrimitive, Choice].each(&:turn_on_tracing)

    if block_given?
      begin
        yield
      ensure
        [BasePrimitive, Choice].each(&:turn_off_tracing)
        @tracer = nil
      end
    end
  end

  def trace_message #:nodoc:
    yield @tracer if @tracer
  end

  module_function :trace_reading, :trace_message

  class BasePrimitive < BinData::Base
    class << self
      def turn_on_tracing
        alias_method :do_read_without_hook, :do_read
        alias_method :do_read, :do_read_with_hook
      end

      def turn_off_tracing
        alias_method :do_read, :do_read_without_hook
      end
    end

    def do_read_with_hook(io)
      do_read_without_hook(io)
      trace_value
    end

    def trace_value
      BinData.trace_message do |tracer|
        value_string = _value.inspect
        tracer.trace_obj(debug_name, value_string)
      end
    end
  end

  class Choice < BinData::Base
    class << self
      def turn_on_tracing
        alias_method :do_read_without_hook, :do_read
        alias_method :do_read, :do_read_with_hook
      end

      def turn_off_tracing
        alias_method :do_read, :do_read_without_hook
      end
    end

    def do_read_with_hook(io)
      trace_selection
      do_read_without_hook(io)
    end

    def trace_selection
      BinData.trace_message do |tracer|
        selection_string = eval_parameter(:selection).inspect
        tracer.trace_obj("#{debug_name}-selection-", selection_string)
      end
    end
  end
end
