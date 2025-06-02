# frozen_string_literal: true
#
#   irb/lib/tracer.rb -
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#
# Loading the gem "tracer" will cause it to extend IRB commands with:
# https://github.com/ruby/tracer/blob/v0.2.2/lib/tracer/irb.rb
begin
  require "tracer"
rescue LoadError
  $stderr.puts "Tracer extension of IRB is enabled but tracer gem wasn't found."
  return # This is about to disable loading below
end

module IRB
  class CallTracer < ::CallTracer
    IRB_DIR = File.expand_path('../..', __dir__)

    def skip?(tp)
      super || tp.path.match?(IRB_DIR) || tp.path.match?('<internal:prelude>')
    end
  end
  class WorkSpace
    alias __evaluate__ evaluate
    # Evaluate the context of this workspace and use the Tracer library to
    # output the exact lines of code are being executed in chronological order.
    #
    # See https://github.com/ruby/tracer for more information.
    def evaluate(statements, file = __FILE__, line = __LINE__)
      if IRB.conf[:USE_TRACER] == true
        CallTracer.new(colorize: Color.colorable?).start do
          __evaluate__(statements, file, line)
        end
      else
        __evaluate__(statements, file, line)
      end
    end
  end
end
