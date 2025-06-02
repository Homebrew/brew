# frozen_string_literal: true

return if ENV['RUBY_DEBUG_ENABLE'] == '0'

# skip to load debugger for bundle exec

if $0.end_with?('bin/bundle') && ARGV.first == 'exec'
  trace_var(:$0) do |file|
    trace_var(:$0, nil)
    if /-r (#{Regexp.escape(__dir__)}\S+)/ =~ ENV['RUBYOPT']
      lib = $1
      $LOADED_FEATURES.delete_if{|path| path.start_with?(__dir__)}
      ENV['RUBY_DEBUG_INITIAL_SUSPEND_PATH'] = file
      require lib
      ENV['RUBY_DEBUG_INITIAL_SUSPEND_PATH'] = nil
    end
  end

  return
end

# restore RUBYOPT
if (added_opt = ENV['RUBY_DEBUG_ADDED_RUBYOPT']) &&
   (rubyopt = ENV['RUBYOPT']) &&
   rubyopt.end_with?(added_opt)

  ENV['RUBYOPT'] = rubyopt.delete_suffix(added_opt)
  ENV['RUBY_DEBUG_ADDED_RUBYOPT'] = nil
end

require_relative 'frame_info'
require_relative 'config'
require_relative 'thread_client'
require_relative 'source_repository'
require_relative 'breakpoint'
require_relative 'tracer'

# To prevent loading old lib/debug.rb in Ruby 2.6 to 3.0
$LOADED_FEATURES << 'debug.rb'
$LOADED_FEATURES << File.expand_path(File.join(__dir__, '..', 'debug.rb'))
require 'debug' # invalidate the $LOADED_FEATURE cache

require 'json' if ENV['RUBY_DEBUG_TEST_UI'] == 'terminal'
require 'pp'

class RubyVM::InstructionSequence
  def traceable_lines_norec lines
    code = self.to_a[13]
    line = 0
    code.each{|e|
      case e
      when Integer
        line = e
      when Symbol
        if /\ARUBY_EVENT_/ =~ e.to_s
          lines[line] = [e, *lines[line]]
        end
      end
    }
  end

  def traceable_lines_rec lines
    self.each_child{|ci| ci.traceable_lines_rec(lines)}
    traceable_lines_norec lines
  end

  def type
    self.to_a[9]
  end unless method_defined?(:type)

  def parameters_symbols
    ary = self.to_a
    argc = ary[4][:arg_size]
    locals = ary.to_a[10]
    locals[0...argc]
  end unless method_defined?(:parameters_symbols)

  def last_line
    self.to_a[4][:code_location][2]
  end unless method_defined?(:last_line)

  def first_line
    self.to_a[4][:code_location][0]
  end unless method_defined?(:first_line)
end

module DEBUGGER__
  PresetCommand = Struct.new(:commands, :source, :auto_continue)
  class PostmortemError < RuntimeError; end

  class Session
    attr_reader :intercepted_sigint_cmd, :process_group

    include Color

    def initialize
      @ui = nil
      @sr = SourceRepository.new
      @bps = {} # bp.key => bp
                #   [file, line] => LineBreakpoint
                #   "Error" => CatchBreakpoint
                #   "Foo#bar" => MethodBreakpoint
                #   [:watch, ivar] => WatchIVarBreakpoint
                #   [:check, expr] => CheckBreakpoint
      #
      @tracers = {}
      @th_clients = {} # {Thread => ThreadClient}
      @q_evt = Queue.new
      @displays = []
      @tc = nil
      @tc_id = 0
      @preset_command = nil
      @postmortem_hook = nil
      @postmortem = false
      @intercept_trap_sigint = false
      @intercepted_sigint_cmd = 'DEFAULT'
      @process_group = ProcessGroup.new
      @subsession_stack = []

      @frame_map = {} # for DAP: {id => [threadId, frame_depth]} and CDP: {id => frame_depth}
      @var_map   = {1 => [:globals], } # {id => ...} for DAP
      @src_map   = {} # {id => src}

      @scr_id_map = {} # for CDP
      @obj_map = {} # { object_id => ... } for CDP

      @tp_thread_begin = nil
      @tp_load_script = TracePoint.new(:script_compiled){|tp|
        ThreadClient.current.on_load tp.instruction_sequence, tp.eval_script
      }
      @tp_load_script.enable

      @thread_stopper = thread_stopper
      self.postmortem = CONFIG[:postmortem]
    end

    def active?
      !@q_evt.closed?
    end

    def break_at? file, line
      @bps.has_key? [file, line]
    end

    def activate ui = nil, on_fork: false
      @ui = ui if ui

      @tp_thread_begin&.disable
      @tp_thread_begin = nil

      @ui.activate self, on_fork: on_fork

      q = Queue.new
      @session_server = Thread.new do
        Thread.current.name = 'DEBUGGER__::SESSION@server'
        Thread.current.abort_on_exception = true

        # Thread management
        setup_threads
        thc = get_thread_client Thread.current
        thc.mark_as_management

        if @ui.respond_to?(:reader_thread) && thc = get_thread_client(@ui.reader_thread)
          thc.mark_as_management
        end

        @tp_thread_begin = TracePoint.new(:thread_begin) do |tp|
          get_thread_client
        end
        @tp_thread_begin.enable

        # session start
        q << true
        session_server_main
      end

      q.pop
    end

    def deactivate
      get_thread_client.deactivate
      @thread_stopper.disable
      @tp_load_script.disable
      @tp_thread_begin.disable
      @bps.each_value{|bp| bp.disable}
      @th_clients.each_value{|thc| thc.close}
      @tracers.values.each{|t| t.disable}
      @q_evt.close
      @ui&.deactivate
      @ui = nil
    end

    def reset_ui ui
      @ui.deactivate
      @ui = ui
    end

    def pop_event
      @q_evt.pop
    end

    def session_server_main
      while evt = pop_event
        process_event evt
      end
    ensure
      deactivate
    end

    def request_tc(req)
      @tc << req
    end

    def process_event evt
      # variable `@internal_info` is only used for test
      tc, output, ev, @internal_info, *ev_args = evt

      output.each{|str| @ui.puts str} if ev != :suspend

      # special event, tc is nil
      # and we don't want to set @tc to the newly created thread's ThreadClient
      if ev == :thread_begin
        th = ev_args.shift
        q = ev_args.shift
        on_thread_begin th
        q << true

        return
      end

      @tc = tc

      case ev
      when :init
        enter_subsession
        wait_command_loop
      when :load
        iseq, src = ev_args
        on_load iseq, src
        request_tc :continue

      when :trace
        trace_id, msg = ev_args
        if t = @tracers.values.find{|t| t.object_id == trace_id}
          t.puts msg
        end
        request_tc :continue

      when :suspend
        enter_subsession if ev_args.first != :replay
        output.each{|str| @ui.puts str}

        case ev_args.first
        when :breakpoint
          bp, i = bp_index ev_args[1]
          clean_bps unless bp
          @ui.event :suspend_bp, i, bp, @tc.id
        when :trap
          @ui.event :suspend_trap, sig = ev_args[1], @tc.id

          if sig == :SIGINT && (@intercepted_sigint_cmd.kind_of?(Proc) || @intercepted_sigint_cmd.kind_of?(String))
            @ui.puts "#{@intercepted_sigint_cmd.inspect} is registered as SIGINT handler."
            @ui.puts "`sigint` command execute it."
          end
        else
          @ui.event :suspended, @tc.id
        end

        if @displays.empty?
          wait_command_loop
        else
          request_tc [:eval, :display, @displays]
        end
      when :result
        raise "[BUG] not in subsession" if @subsession_stack.empty?

        case ev_args.first
        when :try_display
          failed_results = ev_args[1]
          if failed_results.size > 0
            i, _msg = failed_results.last
            if i+1 == @displays.size
              @ui.puts "canceled: #{@displays.pop}"
            end
          end

        when :method_breakpoint, :watch_breakpoint
          bp = ev_args[1]
          if bp
            add_bp(bp)
            show_bps bp
          else
            # can't make a bp
          end
        when :trace_pass
          obj_id = ev_args[1]
          obj_inspect = ev_args[2]
          opt = ev_args[3]
          add_tracer ObjectTracer.new(@ui, obj_id, obj_inspect, **opt)
        else
          # ignore
        end

        wait_command_loop

      when :dap_result
        dap_event ev_args # server.rb
        wait_command_loop
      when :cdp_result
        cdp_event ev_args
        wait_command_loop
      end
    end

    def add_preset_commands name, cmds, kick: true, continue: true
      cs = cmds.map{|c|
        c.each_line.map{|line|
          line = line.strip.gsub(/\A\s*\#.*/, '').strip
          line unless line.empty?
        }.compact
      }.flatten.compact

      if @preset_command && !@preset_command.commands.empty?
        @preset_command.commands += cs
      else
        @preset_command = PresetCommand.new(cs, name, continue)
      end

      ThreadClient.current.on_init name if kick
    end

    def source iseq
      if !CONFIG[:no_color]
        @sr.get_colored(iseq)
      else
        @sr.get(iseq)
      end
    end

    def inspect
      "DEBUGGER__::SESSION"
    end

    def wait_command_loop
      loop do
        case wait_command
        when :retry
          # nothing
        else
          break
        end
      rescue Interrupt
        @ui.puts "\n^C"
        retry
      end
    end

    def prompt
      if @postmortem
        '(rdbg:postmortem) '
      elsif @process_group.multi?
        "(rdbg@#{process_info}) "
      else
        '(rdbg) '
      end
    end

    def wait_command
      if @preset_command
        if @preset_command.commands.empty?
          if @preset_command.auto_continue
            @preset_command = nil

            leave_subsession :continue
            return
          else
            @preset_command = nil
            return :retry
          end
        else
          line = @preset_command.commands.shift
          @ui.puts "(rdbg:#{@preset_command.source}) #{line}"
        end
      else
        @ui.puts "INTERNAL_INFO: #{JSON.generate(@internal_info)}" if ENV['RUBY_DEBUG_TEST_UI'] == 'terminal'
        line = @ui.readline prompt
      end

      case line
      when String
        process_command line
      when Hash
        process_protocol_request line # defined in server.rb
      else
        raise "unexpected input: #{line.inspect}"
      end
    end

    def process_command line
      if line.empty?
        if @repl_prev_line
          line = @repl_prev_line
        else
          return :retry
        end
      else
        @repl_prev_line = line
      end

      /([^\s]+)(?:\s+(.+))?/ =~ line
      cmd, arg = $1, $2

      # p cmd: [cmd, *arg]

      case cmd
      ### Control flow

      # * `s[tep]`
      #   * Step in. Resume the program until next breakable point.
      # * `s[tep] <n>`
      #   * Step in, resume the program at `<n>`th breakable point.
      when 's', 'step'
        cancel_auto_continue
        check_postmortem
        step_command :in, arg

      # * `n[ext]`
      #   * Step over. Resume the program until next line.
      # * `n[ext] <n>`
      #   * Step over, same as `step <n>`.
      when 'n', 'next'
        cancel_auto_continue
        check_postmortem
        step_command :next, arg

      # * `fin[ish]`
      #   * Finish this frame. Resume the program until the current frame is finished.
      # * `fin[ish] <n>`
      #   * Finish `<n>`th frames.
      when 'fin', 'finish'
        cancel_auto_continue
        check_postmortem

        if arg&.to_i == 0
          raise 'finish command with 0 does not make sense.'
        end

        step_command :finish, arg

      # * `c[ontinue]`
      #   * Resume the program.
      when 'c', 'continue'
        cancel_auto_continue
        leave_subsession :continue

      # * `q[uit]` or `Ctrl-D`
      #   * Finish debugger (with the debuggee process on non-remote debugging).
      when 'q', 'quit'
        if ask 'Really quit?'
          @ui.quit arg.to_i
          leave_subsession :continue
        else
          return :retry
        end

      # * `q[uit]!`
      #   * Same as q[uit] but without the confirmation prompt.
      when 'q!', 'quit!'
        @ui.quit arg.to_i
        leave_subsession nil

      # * `kill`
      #   * Stop the debuggee process with `Kernel#exit!`.
      when 'kill'
        if ask 'Really kill?'
          exit! (arg || 1).to_i
        else
          return :retry
        end

      # * `kill!`
      #   * Same as kill but without the confirmation prompt.
      when 'kill!'
        exit! (arg || 1).to_i

      # * `sigint`
      #   * Execute SIGINT handler registered by the debuggee.
      #   * Note that this command should be used just after stop by `SIGINT`.
      when 'sigint'
        begin
          case cmd = @intercepted_sigint_cmd
          when nil, 'IGNORE', :IGNORE, 'DEFAULT', :DEFAULT
            # ignore
          when String
            eval(cmd)
          when Proc
            cmd.call
          end

          leave_subsession :continue

        rescue Exception => e
          @ui.puts "Exception: #{e}"
          @ui.puts e.backtrace.map{|line| "  #{e}"}
          return :retry
        end

      ### Breakpoint

      # * `b[reak]`
      #   * Show all breakpoints.
      # * `b[reak] <line>`
      #   * Set breakpoint on `<line>` at the current frame's file.
      # * `b[reak] <file>:<line>` or `<file> <line>`
      #   * Set breakpoint on `<file>:<line>`.
      # * `b[reak] <class>#<name>`
      #    * Set breakpoint on the method `<class>#<name>`.
      # * `b[reak] <expr>.<name>`
      #    * Set breakpoint on the method `<expr>.<name>`.
      # * `b[reak] ... if: <expr>`
      #   * break if `<expr>` is true at specified location.
      # * `b[reak] ... pre: <command>`
      #   * break and run `<command>` before stopping.
      # * `b[reak] ... do: <command>`
      #   * break and run `<command>`, and continue.
      # * `b[reak] ... path: <path>`
      #   * break if the path matches to `<path>`. `<path>` can be a regexp with `/regexp/`.
      # * `b[reak] if: <expr>`
      #   * break if: `<expr>` is true at any lines.
      #   * Note that this feature is super slow.
      when 'b', 'break'
        check_postmortem

        if arg == nil
          show_bps
          return :retry
        else
          case bp = repl_add_breakpoint(arg)
          when :noretry
          when nil
            return :retry
          else
            show_bps bp
            return :retry
          end
        end

      # * `catch <Error>`
      #   * Set breakpoint on raising `<Error>`.
      # * `catch ... if: <expr>`
      #   * stops only if `<expr>` is true as well.
      # * `catch ... pre: <command>`
      #   * runs `<command>` before stopping.
      # * `catch ... do: <command>`
      #   * stops and run `<command>`, and continue.
      # * `catch ... path: <path>`
      #   * stops if the exception is raised from a `<path>`. `<path>` can be a regexp with `/regexp/`.
      when 'catch'
        check_postmortem

        if arg
          bp = repl_add_catch_breakpoint arg
          show_bps bp if bp
        else
          show_bps
        end
        return :retry

      # * `watch @ivar`
      #   * Stop the execution when the result of current scope's `@ivar` is changed.
      #   * Note that this feature is super slow.
      # * `watch ... if: <expr>`
      #   * stops only if `<expr>` is true as well.
      # * `watch ... pre: <command>`
      #   * runs `<command>` before stopping.
      # * `watch ... do: <command>`
      #   * stops and run `<command>`, and continue.
      # * `watch ... path: <path>`
      #   * stops if the path matches `<path>`. `<path>` can be a regexp with `/regexp/`.
      when 'wat', 'watch'
        check_postmortem

        if arg && arg.match?(/\A@\w+/)
          repl_add_watch_breakpoint(arg)
        else
          show_bps
          return :retry
        end

      # * `del[ete]`
      #   * delete all breakpoints.
      # * `del[ete] <bpnum>`
      #   * delete specified breakpoint.
      when 'del', 'delete'
        check_postmortem

        bp =
        case arg
        when nil
          show_bps
          if ask "Remove all breakpoints?", 'N'
            delete_bp
          end
        when /\d+/
          delete_bp arg.to_i
        else
          nil
        end
        @ui.puts "deleted: \##{bp[0]} #{bp[1]}" if bp
        return :retry

      ### Information

      # * `bt` or `backtrace`
      #   * Show backtrace (frame) information.
      # * `bt <num>` or `backtrace <num>`
      #   * Only shows first `<num>` frames.
      # * `bt /regexp/` or `backtrace /regexp/`
      #   * Only shows frames with method name or location info that matches `/regexp/`.
      # * `bt <num> /regexp/` or `backtrace <num> /regexp/`
      #   * Only shows first `<num>` frames with method name or location info that matches `/regexp/`.
      when 'bt', 'backtrace'
        case arg
        when /\A(\d+)\z/
          request_tc [:show, :backtrace, arg.to_i, nil]
        when /\A\/(.*)\/\z/
          pattern = $1
          request_tc [:show, :backtrace, nil, Regexp.compile(pattern)]
        when /\A(\d+)\s+\/(.*)\/\z/
          max, pattern = $1, $2
          request_tc [:show, :backtrace, max.to_i, Regexp.compile(pattern)]
        else
          request_tc [:show, :backtrace, nil, nil]
        end

      # * `l[ist]`
      #   * Show current frame's source code.
      #   * Next `list` command shows the successor lines.
      # * `l[ist] -`
      #   * Show predecessor lines as opposed to the `list` command.
      # * `l[ist] <start>` or `l[ist] <start>-<end>`
      #   * Show current frame's source code from the line <start> to <end> if given.
      when 'l', 'list'
        case arg ? arg.strip : nil
        when /\A(\d+)\z/
          request_tc [:show, :list, {start_line: arg.to_i - 1}]
        when /\A-\z/
          request_tc [:show, :list, {dir: -1}]
        when /\A(\d+)-(\d+)\z/
          request_tc [:show, :list, {start_line: $1.to_i - 1, end_line: $2.to_i}]
        when nil
          request_tc [:show, :list]
        else
          @ui.puts "Can not handle list argument: #{arg}"
          return :retry
        end

      # * `edit`
      #   * Open the current file on the editor (use `EDITOR` environment variable).
      #   * Note that edited file will not be reloaded.
      # * `edit <file>`
      #   * Open <file> on the editor.
      when 'edit'
        if @ui.remote?
          @ui.puts "not supported on the remote console."
          return :retry
        end

        begin
          arg = resolve_path(arg) if arg
        rescue Errno::ENOENT
          @ui.puts "not found: #{arg}"
          return :retry
        end

        request_tc [:show, :edit, arg]

      # * `i[nfo]`
      #    * Show information about current frame (local/instance variables and defined constants).
      # * `i[nfo] l[ocal[s]]`
      #   * Show information about the current frame (local variables)
      #   * It includes `self` as `%self` and a return value as `%return`.
      # * `i[nfo] i[var[s]]` or `i[nfo] instance`
      #   * Show information about instance variables about `self`.
      # * `i[nfo] c[onst[s]]` or `i[nfo] constant[s]`
      #   * Show information about accessible constants except toplevel constants.
      # * `i[nfo] g[lobal[s]]`
      #   * Show information about global variables
      # * `i[nfo] ... /regexp/`
      #   * Filter the output with `/regexp/`.
      # * `i[nfo] th[read[s]]`
      #   * Show all threads (same as `th[read]`).
      when 'i', 'info'
        if /\/(.+)\/\z/ =~ arg
          pat = Regexp.compile($1)
          sub = $~.pre_match.strip
        else
          sub = arg
        end

        case sub
        when nil
          request_tc [:show, :default, pat] # something useful
        when 'l', /^locals?/
          request_tc [:show, :locals, pat]
        when 'i', /^ivars?/i, /^instance[_ ]variables?/i
          request_tc [:show, :ivars, pat]
        when 'c', /^consts?/i, /^constants?/i
          request_tc [:show, :consts, pat]
        when 'g', /^globals?/i, /^global[_ ]variables?/i
          request_tc [:show, :globals, pat]
        when 'th', /threads?/
          thread_list
          return :retry
        else
          @ui.puts "unrecognized argument for info command: #{arg}"
          show_help 'info'
          return :retry
        end

      # * `o[utline]` or `ls`
      #   * Show you available methods, constants, local variables, and instance variables in the current scope.
      # * `o[utline] <expr>` or `ls <expr>`
      #   * Show you available methods and instance variables of the given object.
      #   * If the object is a class/module, it also lists its constants.
      when 'outline', 'o', 'ls'
        request_tc [:show, :outline, arg]

      # * `display`
      #   * Show display setting.
      # * `display <expr>`
      #   * Show the result of `<expr>` at every suspended timing.
      when 'display'
        if arg && !arg.empty?
          @displays << arg
          request_tc [:eval, :try_display, @displays]
        else
          request_tc [:eval, :display, @displays]
        end

      # * `undisplay`
      #   * Remove all display settings.
      # * `undisplay <displaynum>`
      #   * Remove a specified display setting.
      when 'undisplay'
        case arg
        when /(\d+)/
          if @displays[n = $1.to_i]
            @displays.delete_at n
          end
          request_tc [:eval, :display, @displays]
        when nil
          if ask "clear all?", 'N'
            @displays.clear
          end
          return :retry
        end

      ### Frame control

      # * `f[rame]`
      #   * Show the current frame.
      # * `f[rame] <framenum>`
      #   * Specify a current frame. Evaluation are run on specified frame.
      when 'frame', 'f'
        request_tc [:frame, :set, arg]

      # * `up`
      #   * Specify the upper frame.
      when 'up'
        request_tc [:frame, :up]

      # * `down`
      #   * Specify the lower frame.
      when 'down'
        request_tc [:frame, :down]

      ### Evaluate

      # * `p <expr>`
      #   * Evaluate like `p <expr>` on the current frame.
      when 'p'
        request_tc [:eval, :p, arg.to_s]

      # * `pp <expr>`
      #   * Evaluate like `pp <expr>` on the current frame.
      when 'pp'
        request_tc [:eval, :pp, arg.to_s]

      # * `eval <expr>`
      #   * Evaluate `<expr>` on the current frame.
      when 'eval', 'call'
        if arg == nil || arg.empty?
          show_help 'eval'
          @ui.puts "\nTo evaluate the variable `#{cmd}`, use `pp #{cmd}` instead."
          return :retry
        else
          request_tc [:eval, :call, arg]
        end

      # * `irb`
      #   * Invoke `irb` on the current frame.
      when 'irb'
        if @ui.remote?
          @ui.puts "not supported on the remote console."
          return :retry
        end
        request_tc [:eval, :irb]

        # don't repeat irb command
        @repl_prev_line = nil

      ### Trace
      # * `trace`
      #   * Show available tracers list.
      # * `trace line`
      #   * Add a line tracer. It indicates line events.
      # * `trace call`
      #   * Add a call tracer. It indicate call/return events.
      # * `trace exception`
      #   * Add an exception tracer. It indicates raising exceptions.
      # * `trace object <expr>`
      #   * Add an object tracer. It indicates that an object by `<expr>` is passed as a parameter or a receiver on method call.
      # * `trace ... /regexp/`
      #   * Indicates only matched events to `/regexp/`.
      # * `trace ... into: <file>`
      #   * Save trace information into: `<file>`.
      # * `trace off <num>`
      #   * Disable tracer specified by `<num>` (use `trace` command to check the numbers).
      # * `trace off [line|call|pass]`
      #   * Disable all tracers. If `<type>` is provided, disable specified type tracers.
      when 'trace'
        if (re = /\s+into:\s*(.+)/) =~ arg
          into = $1
          arg.sub!(re, '')
        end

        if (re = /\s\/(.+)\/\z/) =~ arg
          pattern = $1
          arg.sub!(re, '')
        end

        case arg
        when nil
          @ui.puts 'Tracers:'
          @tracers.values.each_with_index{|t, i|
            @ui.puts "* \##{i} #{t}"
          }
          @ui.puts
          return :retry

        when /\Aline\z/
          add_tracer LineTracer.new(@ui, pattern: pattern, into: into)
          return :retry

        when /\Acall\z/
          add_tracer CallTracer.new(@ui, pattern: pattern, into: into)
          return :retry

        when /\Aexception\z/
          add_tracer ExceptionTracer.new(@ui, pattern: pattern, into: into)
          return :retry

        when /\Aobject\s+(.+)/
          request_tc [:trace, :object, $1.strip, {pattern: pattern, into: into}]

        when /\Aoff\s+(\d+)\z/
          if t = @tracers.values[$1.to_i]
            t.disable
            @ui.puts "Disable #{t.to_s}"
          else
            @ui.puts "Unmatched: #{$1}"
          end
          return :retry

        when /\Aoff(\s+(line|call|exception|object))?\z/
          @tracers.values.each{|t|
            if $2.nil? || t.type == $2
              t.disable
              @ui.puts "Disable #{t.to_s}"
            end
          }
          return :retry

        else
          @ui.puts "Unknown trace option: #{arg.inspect}"
          return :retry
        end

      # Record
      # * `record`
      #   * Show recording status.
      # * `record [on|off]`
      #   * Start/Stop recording.
      # * `step back`
      #   * Start replay. Step back with the last execution log.
      #   * `s[tep]` does stepping forward with the last log.
      # * `step reset`
      #   * Stop replay .
      when 'record'
        case arg
        when nil, 'on', 'off'
          request_tc [:record, arg&.to_sym]
        else
          @ui.puts "unknown command: #{arg}"
          return :retry
        end

      ### Thread control

      # * `th[read]`
      #   * Show all threads.
      # * `th[read] <thnum>`
      #   * Switch thread specified by `<thnum>`.
      when 'th', 'thread'
        case arg
        when nil, 'list', 'l'
          thread_list
        when /(\d+)/
          switch_thread $1.to_i
        else
          @ui.puts "unknown thread command: #{arg}"
        end
        return :retry

      ### Configuration
      # * `config`
      #   * Show all configuration with description.
      # * `config <name>`
      #   * Show current configuration of <name>.
      # * `config set <name> <val>` or `config <name> = <val>`
      #   * Set <name> to <val>.
      # * `config append <name> <val>` or `config <name> << <val>`
      #   * Append `<val>` to `<name>` if it is an array.
      # * `config unset <name>`
      #   * Set <name> to default.
      when 'config'
        config_command arg
        return :retry

      # * `source <file>`
      #   * Evaluate lines in `<file>` as debug commands.
      when 'source'
        if arg
          begin
            cmds = File.readlines(path = File.expand_path(arg))
            add_preset_commands path, cmds, kick: true, continue: false
          rescue Errno::ENOENT
            @ui.puts "File not found: #{arg}"
          end
        else
          show_help 'source'
        end
        return :retry

      # * `open`
      #   * open debuggee port on UNIX domain socket and wait for attaching.
      #   * Note that `open` command is EXPERIMENTAL.
      # * `open [<host>:]<port>`
      #   * open debuggee port on TCP/IP with given `[<host>:]<port>` and wait for attaching.
      # * `open vscode`
      #   * open debuggee port for VSCode and launch VSCode if available.
      # * `open chrome`
      #   * open debuggee port for Chrome and wait for attaching.
      when 'open'
        case arg&.downcase
        when '', nil
          repl_open
        when 'vscode'
          repl_open_vscode
        when /\A(.+):(\d+)\z/
          repl_open_tcp $1, $2.to_i
        when /\A(\d+)z/
          repl_open_tcp nil, $1.to_i
        when 'tcp'
          repl_open_tcp CONFIG[:host], (CONFIG[:port] || 0)
        when 'chrome', 'cdp'
          CONFIG[:open_frontend] = 'chrome'
          repl_open_tcp CONFIG[:host], (CONFIG[:port] || 0)
        else
          raise "Unknown arg: #{arg}"
        end

        return :retry

      ### Help

      # * `h[elp]`
      #   * Show help for all commands.
      # * `h[elp] <command>`
      #   * Show help for the given command.
      when 'h', 'help', '?'
        show_help arg
        return :retry

      ### END
      else
        request_tc [:eval, :pp, line]
=begin
        @repl_prev_line = nil
        @ui.puts "unknown command: #{line}"
        begin
          require 'did_you_mean'
          spell_checker = DidYouMean::SpellChecker.new(dictionary: DEBUGGER__.commands)
          correction = spell_checker.correct(line.split(/\s/).first || '')
          @ui.puts "Did you mean? #{correction.join(' or ')}" unless correction.empty?
        rescue LoadError
          # Don't use D
        end
        return :retry
=end
      end

    rescue Interrupt
      return :retry
    rescue SystemExit
      raise
    rescue PostmortemError => e
      @ui.puts e.message
      return :retry
    rescue Exception => e
      @ui.puts "[REPL ERROR] #{e.inspect}"
      @ui.puts e.backtrace.map{|e| '  ' + e}
      return :retry
    end

    def repl_open_setup
      @tp_thread_begin.disable
      @ui.activate self
      if @ui.respond_to?(:reader_thread) && thc = get_thread_client(@ui.reader_thread)
        thc.mark_as_management
      end
      @tp_thread_begin.enable
    end

    def repl_open_tcp host, port, **kw
      DEBUGGER__.open_tcp host: host, port: port, nonstop: true, **kw
      repl_open_setup
    end

    def repl_open
      DEBUGGER__.open nonstop: true
      repl_open_setup
    end

    def repl_open_vscode
      CONFIG[:open_frontend] = 'vscode'
      repl_open
    end

    def step_command type, arg
      case arg
      when nil, /\A\d+\z/
        if type == :in && @tc.recorder&.replaying?
          request_tc [:step, type, arg&.to_i]
        else
          leave_subsession [:step, type, arg&.to_i]
        end
      when /\Aback\z/, /\Areset\z/
        if type != :in
          @ui.puts "only `step #{arg}` is supported."
          :retry
        else
          request_tc [:step, arg.to_sym]
        end
      else
        @ui.puts "Unknown option: #{arg}"
        :retry
      end
    end

    def config_show key
      key = key.to_sym
      config_detail = CONFIG_SET[key]

      if config_detail
        v = CONFIG[key]
        kv = "#{key} = #{v.inspect}"
        desc = config_detail[1]

        if config_default = config_detail[3]
          desc += " (default: #{config_default})"
        end

        line = "%-34s \# %s" % [kv, desc]
        if line.size > SESSION.width
          @ui.puts "\# #{desc}\n#{kv}"
        else
          @ui.puts line
        end
      else
        @ui.puts "Unknown configuration: #{key}. 'config' shows all configurations."
      end
    end

    def config_set key, val, append: false
      if CONFIG_SET[key = key.to_sym]
        begin
          if append
            CONFIG.append_config(key, val)
          else
            CONFIG[key] = val
          end
        rescue => e
          @ui.puts e.message
        end
      end

      config_show key
    end

    def config_command arg
      case arg
      when nil
        CONFIG_SET.each do |k, _|
          config_show k
        end

      when /\Aunset\s+(.+)\z/
        if CONFIG_SET[key = $1.to_sym]
          CONFIG[key] = nil
        end
        config_show key

      when /\A(\w+)\s*=\s*(.+)\z/
        config_set $1, $2

      when /\A\s*set\s+(\w+)\s+(.+)\z/
        config_set $1, $2

      when /\A(\w+)\s*<<\s*(.+)\z/
        config_set $1, $2, append: true

      when /\A\s*append\s+(\w+)\s+(.+)\z/
        config_set $1, $2, append: true

      when /\A(\w+)\z/
        config_show $1

      else
        @ui.puts "Can not parse parameters: #{arg}"
      end
    end


    def cancel_auto_continue
      if @preset_command&.auto_continue
        @preset_command.auto_continue = false
      end
    end

    def show_help arg = nil
      instructions = (DEBUGGER__.commands.keys + DEBUGGER__.commands.values).uniq
      print_instructions = proc do |desc|
        desc.split("\n").each do |line|
          next if line.start_with?(" ") # workaround for step back
          formatted_line = line.gsub(/[\[\]\*]/, "").strip
          instructions.each do |inst|
            if formatted_line.start_with?("`#{inst}")
              desc.sub!(line, colorize(line, [:CYAN, :BOLD]))
            end
          end
        end
        @ui.puts desc
      end

      print_category = proc do |cat|
        @ui.puts "\n"
        @ui.puts colorize("### #{cat}", [:GREEN, :BOLD])
        @ui.puts "\n"
      end

      DEBUGGER__.helps.each { |cat, cs|
        # categories
        if arg.nil?
          print_category.call(cat)
        else
          cs.each { |ws, _|
            if ws.include?(arg)
              print_category.call(cat)
              break
            end
          }
        end

        # instructions
        cs.each { |ws, desc|
          if arg.nil? || ws.include?(arg)
            print_instructions.call(desc.dup)
            return if arg
          end
        }
      }

      @ui.puts "not found: #{arg}" if arg
    end

    def ask msg, default = 'Y'
      opts = '[y/n]'.tr(default.downcase, default)
      input = @ui.ask("#{msg} #{opts} ")
      input = default if input.empty?
      case input
      when 'y', 'Y'
        true
      else
        false
      end
    end

    # breakpoint management

    def iterate_bps
      deleted_bps = []
      i = 0
      @bps.each{|key, bp|
        if !bp.deleted?
          yield key, bp, i
          i += 1
        else
          deleted_bps << bp
        end
      }
    ensure
      deleted_bps.each{|bp| @bps.delete bp}
    end

    def show_bps specific_bp = nil
      iterate_bps do |key, bp, i|
        @ui.puts "#%d %s" % [i, bp.to_s] if !specific_bp || bp == specific_bp
      end
    end

    def bp_index specific_bp_key
      iterate_bps do |key, bp, i|
        if key == specific_bp_key
          return [bp, i]
        end
      end
      nil
    end

    def rehash_bps
      bps = @bps.values
      @bps.clear
      bps.each{|bp|
        add_bp bp
      }
    end

    def clean_bps
      @bps.delete_if{|_k, bp|
        bp.deleted?
      }
    end

    def add_bp bp
      # don't repeat commands that add breakpoints
      @repl_prev_line = nil

      if @bps.has_key? bp.key
        if bp.duplicable?
          bp
        else
          @ui.puts "duplicated breakpoint: #{bp}"
          bp.disable
          nil
        end
      else
        @bps[bp.key] = bp
      end
    end

    def delete_bp arg = nil
      case arg
      when nil
        @bps.each{|key, bp| bp.delete}
        @bps.clear
      else
        del_bp = nil
        iterate_bps{|key, bp, i| del_bp = bp if i == arg}
        if del_bp
          del_bp.delete
          @bps.delete del_bp.key
          return [arg, del_bp]
        end
      end
    end

    BREAK_KEYWORDS = %w(if: do: pre: path:).freeze

    def parse_break arg
      mode = :sig
      expr = Hash.new{|h, k| h[k] = []}
      arg.split(' ').each{|w|
        if BREAK_KEYWORDS.any?{|pat| w == pat}
          mode = w[0..-2].to_sym
        else
          expr[mode] << w
        end
      }
      expr.default_proc = nil
      expr = expr.transform_values{|v| v.join(' ')}

      if (path = expr[:path]) && path =~ /\A\/(.*)\/\z/
        expr[:path] = Regexp.compile($1)
      end

      expr
    end

    def repl_add_breakpoint arg
      expr = parse_break arg.strip
      cond = expr[:if]
      cmd = ['break', expr[:pre], expr[:do]] if expr[:pre] || expr[:do]
      path = expr[:path]

      case expr[:sig]
      when /\A(\d+)\z/
        add_line_breakpoint @tc.location.path, $1.to_i, cond: cond, command: cmd
      when /\A(.+)[:\s+](\d+)\z/
        add_line_breakpoint $1, $2.to_i, cond: cond, command: cmd
      when /\A(.+)([\.\#])(.+)\z/
        request_tc [:breakpoint, :method, $1, $2, $3, cond, cmd, path]
        return :noretry
      when nil
        add_check_breakpoint cond, path, cmd
      else
        @ui.puts "Unknown breakpoint format: #{arg}"
        @ui.puts
        show_help 'b'
      end
    end

    def repl_add_catch_breakpoint arg
      expr = parse_break arg.strip
      cond = expr[:if]
      cmd = ['catch', expr[:pre], expr[:do]] if expr[:pre] || expr[:do]
      path = expr[:path]

      bp = CatchBreakpoint.new(expr[:sig], cond: cond, command: cmd, path: path)
      add_bp bp
    end

    def repl_add_watch_breakpoint arg
      expr = parse_break arg.strip
      cond = expr[:if]
      cmd = ['watch', expr[:pre], expr[:do]] if expr[:pre] || expr[:do]
      path = Regexp.compile(expr[:path]) if expr[:path]

      request_tc [:breakpoint, :watch, expr[:sig], cond, cmd, path]
    end

    def add_catch_breakpoint pat, cond: nil
      bp = CatchBreakpoint.new(pat, cond: cond)
      add_bp bp
    end

    def add_check_breakpoint cond, path, command
      bp = CheckBreakpoint.new(cond: cond, path: path, command: command)
      add_bp bp
    end

    def add_line_breakpoint file, line, **kw
      file = resolve_path(file)
      bp = LineBreakpoint.new(file, line, **kw)

      add_bp bp
    rescue Errno::ENOENT => e
      @ui.puts e.message
    end

    def clear_breakpoints(&condition)
      @bps.delete_if do |k, bp|
        if condition.call(k, bp)
          bp.delete
          true
        end
      end
    end

    def clear_line_breakpoints path
      path = resolve_path(path)
      clear_breakpoints do |k, bp|
        bp.is_a?(LineBreakpoint) && DEBUGGER__.compare_path(k.first, path)
      end
    rescue Errno::ENOENT
      # just ignore
    end

    def clear_catch_breakpoints *exception_names
      clear_breakpoints do |k, bp|
        bp.is_a?(CatchBreakpoint) && exception_names.include?(k[1])
      end
    end

    def clear_all_breakpoints
      clear_breakpoints{true}
    end

    def add_iseq_breakpoint iseq, **kw
      bp = ISeqBreakpoint.new(iseq, [:line], **kw)
      add_bp bp
    end

    # tracers

    def add_tracer tracer
      # don't repeat commands that add tracers
      @repl_prev_line = nil
      if @tracers.has_key? tracer.key
        tracer.disable
        @ui.puts "Duplicated tracer: #{tracer}"
      else
        @tracers[tracer.key] = tracer
        @ui.puts "Enable #{tracer}"
      end
    end

    # threads

    def update_thread_list
      list = Thread.list
      thcs = []
      unmanaged = []

      list.each{|th|
        if thc = @th_clients[th]
          if !thc.management?
            thcs << thc
          end
        else
          unmanaged << th
        end
      }

      return thcs.sort_by{|thc| thc.id}, unmanaged
    end

    def thread_list
      thcs, unmanaged_ths = update_thread_list
      thcs.each_with_index{|thc, i|
        @ui.puts "#{@tc == thc ? "--> " : "    "}\##{i} #{thc}"
      }

      if !unmanaged_ths.empty?
        @ui.puts "The following threads are not managed yet by the debugger:"
        unmanaged_ths.each{|th|
          @ui.puts "     " + th.to_s
        }
      end
    end

    def managed_thread_clients
      thcs, _unmanaged_ths = update_thread_list
      thcs
    end

    def switch_thread n
      thcs, _unmanaged_ths = update_thread_list

      if tc = thcs[n]
        if tc.waiting?
          @tc = tc
        else
          @ui.puts "#{tc.thread} is not controllable yet."
        end
      end
      thread_list
    end

    def setup_threads
      prev_clients = @th_clients
      @th_clients = {}

      Thread.list.each{|th|
        if tc = prev_clients[th]
          @th_clients[th] = tc
        else
          create_thread_client(th)
        end
      }
    end

    def on_thread_begin th
      if @th_clients.has_key? th
        # TODO: NG?
      else
        create_thread_client th
      end
    end

    private def create_thread_client th
      # TODO: Ractor support
      raise "Only session_server can create thread_client" unless Thread.current == @session_server
      @th_clients[th] = ThreadClient.new((@tc_id += 1), @q_evt, Queue.new, th)
    end

    private def ask_thread_client th
      # TODO: Ractor support
      q2 = Queue.new
      # tc, output, ev, @internal_info, *ev_args = evt
      @q_evt << [nil, [], :thread_begin, nil, th, q2]
      q2.pop

      @th_clients[th] or raise "unexpected error"
    end

    # can be called by other threads
    def get_thread_client th = Thread.current
      if @th_clients.has_key? th
        @th_clients[th]
      else
        if Thread.current == @session_server
          create_thread_client th
        else
          ask_thread_client th
        end
      end
    end

    private def running_thread_clients_count
      @th_clients.count{|th, tc|
        next if tc.management?
        next unless tc.running?
        true
      }
    end

    private def waiting_thread_clients
      @th_clients.map{|th, tc|
        next if tc.management?
        next unless tc.waiting?
        tc
      }.compact
    end

    private def thread_stopper
      TracePoint.new(:line) do
        # run on each thread
        tc = ThreadClient.current
        next if tc.management?
        next unless tc.running?
        next if tc == @tc

        tc.on_pause
      end
    end

    private def stop_all_threads
      return if running_thread_clients_count == 0

      stopper = @thread_stopper
      stopper.enable unless stopper.enabled?
    end

    private def restart_all_threads
      stopper = @thread_stopper
      stopper.disable if stopper.enabled?

      waiting_thread_clients.each{|tc|
        next if @tc == tc
        tc << :continue
      }
    end

    private def enter_subsession
      if !@subsession_stack.empty?
        DEBUGGER__.info "Enter subsession (nested #{@subsession_stack.size})"
      else
        DEBUGGER__.info "Enter subsession"
        stop_all_threads
        @process_group.lock
      end

      @subsession_stack << true
    end

    private def leave_subsession type
      raise '[BUG] leave_subsession: not entered' if @subsession_stack.empty?
      @subsession_stack.pop

      if @subsession_stack.empty?
        DEBUGGER__.info "Leave subsession"
        @process_group.unlock
        restart_all_threads
      else
        DEBUGGER__.info "Leave subsession (nested #{@subsession_stack.size})"
      end

      request_tc type if type
      @tc = nil
    rescue Exception => e
      STDERR.puts PP.pp([e, e.backtrace], ''.dup)
      raise
    end

    def in_subsession?
      !@subsession_stack.empty?
    end

    ## event

    def on_load iseq, src
      DEBUGGER__.info "Load #{iseq.absolute_path || iseq.path}"

      file_path, reloaded = @sr.add(iseq, src)
      @ui.event :load, file_path, reloaded

      pending_line_breakpoints = @bps.find_all do |key, bp|
        LineBreakpoint === bp && !bp.iseq
      end

      pending_line_breakpoints.each do |_key, bp|
        if DEBUGGER__.compare_path(bp.path, (iseq.absolute_path || iseq.path))
          bp.try_activate iseq
        end
      end

      if reloaded
        @bps.find_all do |key, bp|
          LineBreakpoint === bp && DEBUGGER__.compare_path(bp.path, file_path)
        end.each do |_key, bp|
          @bps.delete bp.key # to allow duplicate
          if nbp = LineBreakpoint.copy(bp, iseq)
            add_bp nbp
          end
        end
      end
    end

    def resolve_path file
      File.realpath(File.expand_path(file))
    rescue Errno::ENOENT
      case file
      when '-e', '-'
        return file
      else
        $LOAD_PATH.each do |lp|
          libpath = File.join(lp, file)
          return File.realpath(libpath)
        rescue Errno::ENOENT
          # next
        end
      end

      raise
    end

    def method_added tp
      b = tp.binding

      if var_name = b.local_variables.first
        mid = b.local_variable_get(var_name)
        resolved = true

        @bps.each{|k, bp|
          case bp
          when MethodBreakpoint
            if bp.method.nil?
              if bp.sig_method_name == mid.to_s
                bp.try_enable(added: true)
              end
            end

            resolved = false if !bp.enabled?
          end
        }

        if resolved
          Session.deactivate_method_added_trackers
        end

        case mid
        when :method_added, :singleton_method_added
          Session.create_method_added_tracker(tp.self, mid)
          Session.activate_method_added_trackers unless resolved
        end
      end
    end

    class ::Module
      undef method_added
      def method_added mid; end
    end

    class ::BasicObject
      undef singleton_method_added
      def singleton_method_added mid; end
    end

    def self.create_method_added_tracker mod, method_added_id, method_accessor = :method
      m = mod.__send__(method_accessor, method_added_id)
      METHOD_ADDED_TRACKERS[m] = TracePoint.new(:call) do |tp|
        SESSION.method_added tp
      end
    end

    def self.activate_method_added_trackers
      METHOD_ADDED_TRACKERS.each do |m, tp|
        tp.enable(target: m) unless tp.enabled?
      rescue ArgumentError
        DEBUGGER__.warn "Methods defined under #{m.owner} can not track by the debugger."
      end
    end

    def self.deactivate_method_added_trackers
      METHOD_ADDED_TRACKERS.each do |m, tp|
        tp.disable if tp.enabled?
      end
    end

    METHOD_ADDED_TRACKERS = Hash.new
    create_method_added_tracker Module, :method_added, :instance_method
    create_method_added_tracker BasicObject, :singleton_method_added, :instance_method

    def width
      @ui.width
    end

    def check_postmortem
      if @postmortem
        raise PostmortemError, "Can not use this command on postmortem mode."
      end
    end

    def enter_postmortem_session exc
      return unless exc.instance_variable_defined? :@__debugger_postmortem_frames

      frames = exc.instance_variable_get(:@__debugger_postmortem_frames)
      @postmortem = true
      ThreadClient.current.suspend :postmortem, postmortem_frames: frames, postmortem_exc: exc
    ensure
      @postmortem = false
    end

    def capture_exception_frames *exclude_path
      postmortem_hook = TracePoint.new(:raise){|tp|
        exc = tp.raised_exception
        frames = DEBUGGER__.capture_frames(__dir__)

        exclude_path.each{|ex|
          if Regexp === ex
            frames.delete_if{|e| ex =~ e.path}
          else
            frames.delete_if{|e| e.path.start_with? ex.to_s}
          end
        }
        exc.instance_variable_set(:@__debugger_postmortem_frames, frames)
      }
      postmortem_hook.enable

      begin
        yield
        nil
      rescue Exception => e
        if e.instance_variable_defined? :@__debugger_postmortem_frames
          e
        else
          raise
        end
      ensure
        postmortem_hook.disable
      end
    end

    def postmortem=(is_enable)
      if is_enable
        unless @postmortem_hook
          @postmortem_hook = TracePoint.new(:raise){|tp|
            exc = tp.raised_exception
            frames = DEBUGGER__.capture_frames(__dir__)
            exc.instance_variable_set(:@__debugger_postmortem_frames, frames)
          }
          at_exit{
            @postmortem_hook.disable
            if CONFIG[:postmortem] && (exc = $!) != nil
              exc = exc.cause while exc.cause

              begin
                @ui.puts "Enter postmortem mode with #{exc.inspect}"
                @ui.puts exc.backtrace.map{|e| '  ' + e}
                @ui.puts "\n"

                enter_postmortem_session exc
              rescue SystemExit
                exit!
              rescue Exception => e
                @ui = STDERR unless @ui
                @ui.puts "Error while postmortem console: #{e.inspect}"
              end
            end
          }
        end

        if !@postmortem_hook.enabled?
          @postmortem_hook.enable
        end
      else
        if @postmortem_hook && @postmortem_hook.enabled?
          @postmortem_hook.disable
        end
      end
    end

    def save_int_trap cmd
      prev, @intercepted_sigint_cmd = @intercepted_sigint_cmd, cmd
      prev
    end

    def intercept_trap_sigint?
      @intercept_trap_sigint
    end

    def intercept_trap_sigint flag, &b
      prev = @intercept_trap_sigint
      @intercept_trap_sigint = flag
      yield
    ensure
      @intercept_trap_sigint = prev
    end

    def intercept_trap_sigint_start prev
      @intercept_trap_sigint = true
      @intercepted_sigint_cmd = prev
    end

    def intercept_trap_sigint_end
      @intercept_trap_sigint = false
      prev, @intercepted_sigint_cmd = @intercepted_sigint_cmd, nil
      prev
    end

    def process_info
      if @process_group.multi?
        "#{$0}\##{Process.pid}"
      end
    end

    def before_fork need_lock = true
      if need_lock
        @process_group.multi_process!
      end
    end

    def after_fork_parent
      @ui.after_fork_parent
    end
  end

  class ProcessGroup
    def initialize
      @lock_file = nil
    end

    def locked?
      true
    end

    def trylock
      true
    end

    def lock
      true
    end

    def unlock
      true
    end

    def sync
      yield
    end

    def after_fork
    end

    def multi?
      @lock_file
    end

    def multi_process!
      require 'tempfile'
      @lock_tempfile = Tempfile.open("ruby-debug-lock-")
      @lock_tempfile.close
      extend MultiProcessGroup
    end
  end

  module MultiProcessGroup
    def multi_process!
    end

    def after_fork child: true
      if child || !@lock_file
        @m = Mutex.new unless @m
        @m.synchronize do
          @lock_level = 0
          @lock_file = open(@lock_tempfile.path, 'w')
        end
      end
    end

    def info msg
      DEBUGGER__.info "#{msg} (#{@lock_level})" #  #{caller.first(1).map{|bt| bt.sub(__dir__, '')}}"
    end

    def locked?
      # DEBUGGER__.info "locked? #{@lock_level}"
      @lock_level > 0
    end

    private def lock_level_up
      raise unless @m.owned?
      @lock_level += 1
    end

    private def lock_level_down
      raise unless @m.owned?
      raise "@lock_level underflow: #{@lock_level}" if @lock_level < 1
      @lock_level -= 1
    end

    private def trylock
      @m.synchronize do
        if locked?
          lock_level_up
          info "Try lock, already locked"
          true
        else
          case r = @lock_file.flock(File::LOCK_EX | File::LOCK_NB)
          when 0
            lock_level_up
            info "Try lock with file: success"
            true
          when false
            info "Try lock with file: failed"
            false
          else
            raise "unknown flock result: #{r.inspect}"
          end
        end
      end
    end

    def lock
      unless trylock
        @m.synchronize do
          if locked?
            lock_level_up
          else
            info "Lock: block"
            @lock_file.flock(File::LOCK_EX)
            lock_level_up
          end
        end

        info "Lock: success"
      end
    end

    def unlock
      @m.synchronize do
        raise "lock file is not opened (#{@lock_file.inspect})" if @lock_file.closed?
        lock_level_down
        @lock_file.flock(File::LOCK_UN) unless locked?
        info "Unlocked"
      end
    end

    def sync &b
      info "sync"

      lock
      begin
        b.call if b
      ensure
        unlock
      end
    end
  end

  class UI_Base
    def event type, *args
      case type
      when :suspend_bp
        i, bp = *args
        puts "\nStop by \##{i} #{bp}" if bp
      when :suspend_trap
        puts "\nStop by #{args.first}"
      end
    end

    def flush
    end
  end

  # manual configuration methods

  def self.add_line_breakpoint file, line, **kw
    ::DEBUGGER__::SESSION.add_line_breakpoint file, line, **kw
  end

  def self.add_catch_breakpoint pat
    ::DEBUGGER__::SESSION.add_catch_breakpoint pat
  end

  # String for requiring location
  # nil for -r
  def self.require_location
    locs = caller_locations
    dir_prefix = /#{Regexp.escape(__dir__)}/

    locs.each do |loc|
      case loc.absolute_path
      when dir_prefix
      when %r{rubygems/core_ext/kernel_require\.rb}
      else
        return loc if loc.absolute_path
      end
    end
    nil
  end

  # start methods

  def self.start nonstop: false, **kw
    CONFIG.set_config(**kw)

    unless defined? SESSION
      require_relative 'local'
      initialize_session{ UI_LocalConsole.new }
    end

    setup_initial_suspend unless nonstop
  end

  def self.open host: nil, port: CONFIG[:port], sock_path: nil, sock_dir: nil, nonstop: false, **kw
    CONFIG.set_config(**kw)
    require_relative 'server'

    if port || CONFIG[:open_frontend] == 'chrome' || (!::Addrinfo.respond_to?(:unix))
      open_tcp host: host, port: (port || 0), nonstop: nonstop
    else
      open_unix sock_path: sock_path, sock_dir: sock_dir, nonstop: nonstop
    end
  end

  def self.open_tcp host: nil, port:, nonstop: false, **kw
    CONFIG.set_config(**kw)
    require_relative 'server'

    if defined? SESSION
      SESSION.reset_ui UI_TcpServer.new(host: host, port: port)
    else
      initialize_session{ UI_TcpServer.new(host: host, port: port) }
    end

    setup_initial_suspend unless nonstop
  end

  def self.open_unix sock_path: nil, sock_dir: nil, nonstop: false, **kw
    CONFIG.set_config(**kw)
    require_relative 'server'

    if defined? SESSION
      SESSION.reset_ui UI_UnixDomainServer.new(sock_dir: sock_dir, sock_path: sock_path)
    else
      initialize_session{ UI_UnixDomainServer.new(sock_dir: sock_dir, sock_path: sock_path) }
    end

    setup_initial_suspend unless nonstop
  end

  # boot utilities

  def self.setup_initial_suspend
    if !CONFIG[:nonstop]
      case
      when CONFIG[:stop_at_load]
        add_line_breakpoint __FILE__, __LINE__ + 1, oneshot: true, hook_call: false
        nil # stop here
      when path = ENV['RUBY_DEBUG_INITIAL_SUSPEND_PATH']
        add_line_breakpoint path, 0, oneshot: true, hook_call: false
      when loc = ::DEBUGGER__.require_location
        # require 'debug/start' or 'debug'
        add_line_breakpoint loc.absolute_path, loc.lineno + 1, oneshot: true, hook_call: false
      else
        # -r
        add_line_breakpoint $0, 0, oneshot: true, hook_call: false
      end
    end
  end

  class << self
    define_method :initialize_session do |&init_ui|
      DEBUGGER__.info "Session start (pid: #{Process.pid})"
      ::DEBUGGER__.const_set(:SESSION, Session.new)
      SESSION.activate init_ui.call
      load_rc
    end
  end

  def self.load_rc
    [[File.expand_path('~/.rdbgrc'), true],
     [File.expand_path('~/.rdbgrc.rb'), true],
     # ['./.rdbgrc', true], # disable because of security concern
     [CONFIG[:init_script], false],
     ].each{|(path, rc)|
      next unless path
      next if rc && CONFIG[:no_rc] # ignore rc

      if File.file? path
        if path.end_with?('.rb')
          load path
        else
          ::DEBUGGER__::SESSION.add_preset_commands path, File.readlines(path)
        end
      elsif !rc
        warn "Not found: #{path}"
      end
    }

    # given debug commands
    if CONFIG[:commands]
      cmds = CONFIG[:commands].split(';;')
      ::DEBUGGER__::SESSION.add_preset_commands "commands", cmds, kick: false, continue: false
    end
  end

  # Inspector

  SHORT_INSPECT_LENGTH = 40

  class LimitedPP
    def self.pp(obj, max=80)
      out = self.new(max)
      catch out do
        PP.singleline_pp(obj, out)
      end
      out.buf
    end

    attr_reader :buf

    def initialize max
      @max = max
      @cnt = 0
      @buf = String.new
    end

    def <<(other)
      @buf << other

      if @buf.size >= @max
        @buf = @buf[0..@max] + '...'
        throw self
      end
    end
  end

  def self.safe_inspect obj, max_length: SHORT_INSPECT_LENGTH, short: false
    if short
      LimitedPP.pp(obj, max_length)
    else
      obj.inspect
    end
  rescue NoMethodError => e
    klass, oid = M_CLASS.bind_call(obj), M_OBJECT_ID.bind_call(obj)
    if obj == (r = e.receiver)
      "<\##{klass.name}#{oid} does not have \#inspect>"
    else
      rklass, roid = M_CLASS.bind_call(r), M_OBJECT_ID.bind_call(r)
      "<\##{klass.name}:#{roid} contains <\##{rklass}:#{roid} and it does not have #inspect>"
    end
  rescue Exception => e
    "<#inspect raises #{e.inspect}>"
  end

  def self.warn msg
    log :WARN, msg
  end

  def self.info msg
    log :INFO, msg
  end

  def self.check_loglevel level
    lv = LOG_LEVELS[level]
    config_lv = LOG_LEVELS[CONFIG[:log_level]]
    lv <= config_lv
  end

  def self.debug(&b)
    if check_loglevel :DEBUG
      log :DEBUG, b.call
    end
  end

  def self.log level, msg
    if check_loglevel level
      @logfile = STDERR unless defined? @logfile

      if defined? SESSION
        pi = SESSION.process_info
        process_info = pi ? "[#{pi}]" : nil
      end

      if level == :WARN
        # :WARN on debugger is general information
        @logfile.puts "DEBUGGER#{process_info}: #{msg}"
        @logfile.flush
      else
        @logfile.puts "DEBUGGER#{process_info} (#{level}): #{msg}"
        @logfile.flush
      end
    end
  end

  def self.step_in &b
    if defined?(SESSION) && SESSION.active?
      SESSION.add_iseq_breakpoint RubyVM::InstructionSequence.of(b), oneshot: true
    end

    yield
  end

  if File.identical?(__FILE__.upcase, __FILE__.downcase)
    # For case insensitive file system (like Windows)
    # Note that this check is not enough because case sensitive/insensitive is
    # depend on the file system. So this check is only roughly estimation.

    def self.compare_path(a, b)
      a&.downcase == b&.downcase
    end
  else
    def self.compare_path(a, b)
      a == b
    end
  end

  module ForkInterceptor
    if Process.respond_to? :_fork
      def _fork
        return super unless defined?(SESSION) && SESSION.active?

        parent_hook, child_hook = __fork_setup_for_debugger

        super.tap do |pid|
          if pid != 0
            # after fork: parent
            parent_hook.call pid
          else
            # after fork: child
            child_hook.call
          end
        end
      end
    else
      def fork(&given_block)
        return super unless defined?(SESSION) && SESSION.active?
        parent_hook, child_hook = __fork_setup_for_debugger

        if given_block
          new_block = proc {
            # after fork: child
            child_hook.call
            given_block.call
          }
          super(&new_block).tap{|pid| parent_hook.call(pid)}
        else
          super.tap do |pid|
            if pid
              # after fork: parent
              parent_hook.call pid
            else
              # after fork: child
              child_hook.call
            end
          end
        end
      end
    end

    private def __fork_setup_for_debugger
      fork_mode = CONFIG[:fork_mode]

      if fork_mode == :both && CONFIG[:parent_on_fork]
        fork_mode = :parent
      end

      parent_pid = Process.pid

      # before fork
      case fork_mode
      when :parent
        parent_hook = -> child_pid {
          # Do nothing
        }
        child_hook = -> {
          DEBUGGER__.warn "Detaching after fork from child process #{Process.pid}"
          SESSION.deactivate
        }
      when :child
        SESSION.before_fork false

        parent_hook = -> child_pid {
          DEBUGGER__.warn "Detaching after fork from parent process #{Process.pid}"
          SESSION.after_fork_parent
          SESSION.deactivate
        }
        child_hook = -> {
          DEBUGGER__.warn "Attaching after process #{parent_pid} fork to child process #{Process.pid}"
          SESSION.activate on_fork: true
        }
      when :both
        SESSION.before_fork

        parent_hook = -> child_pid {
          SESSION.process_group.after_fork
          SESSION.after_fork_parent
        }
        child_hook = -> {
          DEBUGGER__.warn "Attaching after process #{parent_pid} fork to child process #{Process.pid}"
          SESSION.process_group.after_fork child: true
          SESSION.activate on_fork: true
        }
      end

      return parent_hook, child_hook
    end
  end

  module TrapInterceptor
    def trap sig, *command, &command_proc
      case sig&.to_sym
      when :INT, :SIGINT
        if defined?(SESSION) && SESSION.active? && SESSION.intercept_trap_sigint?
          return SESSION.save_int_trap(command.empty? ? command_proc : command.first)
        end
      end

      super
    end
  end

  if Process.respond_to? :_fork
    module ::Process
      class << self
        prepend ForkInterceptor
      end
    end

    # trap
    module ::Kernel
      prepend TrapInterceptor
    end
    module ::Signal
      class << self
        prepend TrapInterceptor
      end
    end
  else
    if RUBY_VERSION >= '3.0.0'
      module ::Kernel
        prepend ForkInterceptor
        prepend TrapInterceptor
      end
    else
      class ::Object
        include ForkInterceptor
        include TrapInterceptor
      end
    end

    module ::Kernel
      class << self
        prepend ForkInterceptor
        prepend TrapInterceptor
      end
    end

    module ::Process
      class << self
        prepend ForkInterceptor
      end
    end
  end

  module ::Signal
    class << self
      prepend TrapInterceptor
    end
  end
end

module Kernel
  def debugger pre: nil, do: nil, up_level: 0
    return if !defined?(::DEBUGGER__::SESSION) || !::DEBUGGER__::SESSION.active?

    if pre || (do_expr = binding.local_variable_get(:do))
      cmds = ['binding.break', pre, do_expr]
    end

    loc = caller_locations(up_level, 1).first; ::DEBUGGER__.add_line_breakpoint loc.path, loc.lineno + 1, oneshot: true, command: cmds
    self
  end

  alias bb debugger if ENV['RUBY_DEBUG_BB']
end

class Binding
  alias break debugger
  alias b debugger
end

# for Ruby 2.6 compatibility
unless method(:p).unbind.respond_to? :bind_call
  class UnboundMethod
    def bind_call(obj, *args)
      self.bind(obj).call(*args)
    end
  end
end
