# frozen_string_literal: false
#
#   irb/workspace-binding.rb -
#   	$Release Version: 0.9.6$
#   	$Revision$
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#
# --
#
#
#

require "delegate"

IRB::TOPLEVEL_BINDING = binding
module IRB # :nodoc:
  class WorkSpace
    # Creates a new workspace.
    #
    # set self to main if specified, otherwise
    # inherit main from TOPLEVEL_BINDING.
    def initialize(*main)
      if main[0].kind_of?(Binding)
        @binding = main.shift
      elsif IRB.conf[:SINGLE_IRB]
        @binding = TOPLEVEL_BINDING
      else
        case IRB.conf[:CONTEXT_MODE]
        when 0	# binding in proc on TOPLEVEL_BINDING
          @binding = eval("proc{binding}.call",
                          TOPLEVEL_BINDING,
                          __FILE__,
                          __LINE__)
        when 1	# binding in loaded file
          require "tempfile"
          f = Tempfile.open("irb-binding")
          f.print <<EOF
      $binding = binding
EOF
          f.close
          load f.path
          @binding = $binding

        when 2	# binding in loaded file(thread use)
          unless defined? BINDING_QUEUE
            IRB.const_set(:BINDING_QUEUE, Thread::SizedQueue.new(1))
            Thread.abort_on_exception = true
            Thread.start do
              eval "require \"irb/ws-for-case-2\"", TOPLEVEL_BINDING, __FILE__, __LINE__
            end
            Thread.pass
          end
          @binding = BINDING_QUEUE.pop

        when 3	# binding in function on TOPLEVEL_BINDING
          @binding = eval("self.class.remove_method(:irb_binding) if defined?(irb_binding); private; def irb_binding; binding; end; irb_binding",
                          TOPLEVEL_BINDING,
                          __FILE__,
                          __LINE__ - 3)
        when 4  # binding is a copy of TOPLEVEL_BINDING (default)
          # Note that this will typically be IRB::TOPLEVEL_BINDING
          # This is to avoid RubyGems' local variables (see issue #17623)
          @binding = TOPLEVEL_BINDING.dup
        end
      end

      if main.empty?
        @main = eval("self", @binding)
      else
        @main = main[0]
      end
      IRB.conf[:__MAIN__] = @main

      unless main.empty?
        case @main
        when Module
          @binding = eval("IRB.conf[:__MAIN__].module_eval('binding', __FILE__, __LINE__)", @binding, __FILE__, __LINE__)
        else
          begin
            @binding = eval("IRB.conf[:__MAIN__].instance_eval('binding', __FILE__, __LINE__)", @binding, __FILE__, __LINE__)
          rescue TypeError
            fail CantChangeBinding, @main.inspect
          end
        end
      end

      case @main
      when Object
        use_delegator = @main.frozen?
      else
        use_delegator = true
      end

      if use_delegator
        @main = SimpleDelegator.new(@main)
        IRB.conf[:__MAIN__] = @main
        @main.singleton_class.class_eval do
          private
          define_method(:exit) do |*a, &b|
            # Do nothing, will be overridden
          end
          define_method(:binding, Kernel.instance_method(:binding))
          define_method(:local_variables, Kernel.instance_method(:local_variables))
        end
        @binding = eval("IRB.conf[:__MAIN__].instance_eval('binding', __FILE__, __LINE__)", @binding, *@binding.source_location)
      end

      @binding.local_variable_set(:_, nil)
    end

    # The Binding of this workspace
    attr_reader :binding
    # The top-level workspace of this context, also available as
    # <code>IRB.conf[:__MAIN__]</code>
    attr_reader :main

    # Evaluate the given +statements+ within the  context of this workspace.
    def evaluate(context, statements, file = __FILE__, line = __LINE__)
      eval(statements, @binding, file, line)
    end

    def local_variable_set(name, value)
      @binding.local_variable_set(name, value)
    end

    def local_variable_get(name)
      @binding.local_variable_get(name)
    end

    # error message manipulator
    def filter_backtrace(bt)
      return nil if bt =~ /\/irb\/.*\.rb/
      return nil if bt =~ /\/irb\.rb/
      return nil if bt =~ /tool\/lib\/.*\.rb|runner\.rb/ # for tests in Ruby repository
      case IRB.conf[:CONTEXT_MODE]
      when 1
        return nil if bt =~ %r!/tmp/irb-binding!
      when 3
        bt = bt.sub(/:\s*in `irb_binding'/, '')
      end
      bt
    end

    def code_around_binding
      if @binding.respond_to?(:source_location)
        file, pos = @binding.source_location
      else
        file, pos = @binding.eval('[__FILE__, __LINE__]')
      end

      if defined?(::SCRIPT_LINES__[file]) && lines = ::SCRIPT_LINES__[file]
        code = ::SCRIPT_LINES__[file].join('')
      else
        begin
          code = File.read(file)
        rescue SystemCallError
          return
        end
      end

      # NOT using #use_colorize? of IRB.conf[:MAIN_CONTEXT] because this method may be called before IRB::Irb#run
      use_colorize = IRB.conf.fetch(:USE_COLORIZE, true)
      if use_colorize
        lines = Color.colorize_code(code).lines
      else
        lines = code.lines
      end
      pos -= 1

      start_pos = [pos - 5, 0].max
      end_pos   = [pos + 5, lines.size - 1].min

      if use_colorize
        fmt = " %2s #{Color.colorize("%#{end_pos.to_s.length}d", [:BLUE, :BOLD])}: %s"
      else
        fmt = " %2s %#{end_pos.to_s.length}d: %s"
      end
      body = (start_pos..end_pos).map do |current_pos|
        sprintf(fmt, pos == current_pos ? '=>' : '', current_pos + 1, lines[current_pos])
      end.join("")
      "\nFrom: #{file} @ line #{pos + 1} :\n\n#{body}#{Color.clear if use_colorize}\n"
    end

    def IRB.delete_caller
    end
  end
end
