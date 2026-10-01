module BinData

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

  # reference to the current tracer
  @tracer ||= nil

  class Tracer # :nodoc:
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

  def trace_message # :nodoc:
    yield @tracer
  end

  module_function :trace_reading, :trace_message

  module TraceHook
    def turn_on_tracing
      if !method_defined? :do_read_without_hook
        alias_method :do_read_without_hook, :do_read
        alias_method :do_read, :do_read_with_hook
      end
    end

    def turn_off_tracing
      if method_defined? :do_read_without_hook
        alias_method :do_read, :do_read_without_hook
        remove_method :do_read_without_hook
      end
    end
  end

  class BasePrimitive < BinData::Base
    extend TraceHook

    def do_read_with_hook(io)
      do_read_without_hook(io)

      BinData.trace_message do |tracer|
        value_string = _value.inspect
        tracer.trace_obj(debug_name, value_string)
      end
    end
  end

  class Choice < BinData::Base
    extend TraceHook

    def do_read_with_hook(io)
      BinData.trace_message do |tracer|
        selection_string = eval_parameter(:selection).inspect
        tracer.trace_obj("#{debug_name}-selection-", selection_string)
      end

      do_read_without_hook(io)
    end
  end
end
