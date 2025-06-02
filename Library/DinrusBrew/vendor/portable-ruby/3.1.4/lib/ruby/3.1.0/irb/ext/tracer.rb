# frozen_string_literal: false
#
#   irb/lib/tracer.rb -
#   	$Release Version: 0.9.6$
#   	$Revision$
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#
# --
#
#
#
begin
  require "tracer"
rescue LoadError
  $stderr.puts "Tracer extension of IRB is enabled but tracer gem doesn't found."
  module IRB
    TracerLoadError = true
    class Context
      def use_tracer=(opt)
        # do nothing
      end
    end
  end
  return # This is about to disable loading below
end

module IRB

  # initialize tracing function
  def IRB.initialize_tracer
    Tracer.verbose = false
    Tracer.add_filter {
      |event, file, line, id, binding, *rests|
      /^#{Regexp.quote(@CONF[:IRB_LIB_PATH])}/ !~ file and
        File::basename(file) != "irb.rb"
    }
  end

  class Context
    # Whether Tracer is used when evaluating statements in this context.
    #
    # See +lib/tracer.rb+ for more information.
    attr_reader :use_tracer
    alias use_tracer? use_tracer

    # Sets whether or not to use the Tracer library when evaluating statements
    # in this context.
    #
    # See +lib/tracer.rb+ for more information.
    def use_tracer=(opt)
      if opt
        Tracer.set_get_line_procs(@irb_path) {
          |line_no, *rests|
          @io.line(line_no)
        }
      elsif !opt && @use_tracer
        Tracer.off
      end
      @use_tracer=opt
    end
  end

  class WorkSpace
    alias __evaluate__ evaluate
    # Evaluate the context of this workspace and use the Tracer library to
    # output the exact lines of code are being executed in chronological order.
    #
    # See +lib/tracer.rb+ for more information.
    def evaluate(context, statements, file = nil, line = nil)
      if context.use_tracer? && file != nil && line != nil
        Tracer.on
        begin
          __evaluate__(context, statements, file, line)
        ensure
          Tracer.off
        end
      else
        __evaluate__(context, statements, file || __FILE__, line || __LINE__)
      end
    end
  end

  IRB.initialize_tracer
end
