# frozen_string_literal: false
#
#   irb.rb - irb main module
#       $Release Version: 0.9.6 $
#       $Revision$
#       by Keiju ISHITSUKA(keiju@ruby-lang.org)
#
# --
#
#
#
require "ripper"
require "reline"

require_relative "irb/init"
require_relative "irb/context"
require_relative "irb/extend-command"

require_relative "irb/ruby-lex"
require_relative "irb/input-method"
require_relative "irb/locale"
require_relative "irb/color"

require_relative "irb/version"
require_relative "irb/easter-egg"

# IRB stands for "interactive Ruby" and is a tool to interactively execute Ruby
# expressions read from the standard input.
#
# The +irb+ command from your shell will start the interpreter.
#
# == Usage
#
# Use of irb is easy if you know Ruby.
#
# When executing irb, prompts are displayed as follows. Then, enter the Ruby
# expression. An input is executed when it is syntactically complete.
#
#     $ irb
#     irb(main):001:0> 1+2
#     #=> 3
#     irb(main):002:0> class Foo
#     irb(main):003:1>  def foo
#     irb(main):004:2>    print 1
#     irb(main):005:2>  end
#     irb(main):006:1> end
#     #=> nil
#
# The singleline editor module or multiline editor module can be used with irb.
# Use of multiline editor is default if it's installed.
#
# == Command line options
#
#   Usage:  irb.rb [options] [programfile] [arguments]
#     -f                Suppress read of ~/.irbrc
#     -d                Set $DEBUG to true (same as `ruby -d')
#     -r load-module    Same as `ruby -r'
#     -I path           Specify $LOAD_PATH directory
#     -U                Same as `ruby -U`
#     -E enc            Same as `ruby -E`
#     -w                Same as `ruby -w`
#     -W[level=2]       Same as `ruby -W`
#     --context-mode n  Set n[0-4] to method to create Binding Object,
#                       when new workspace was created
#     --extra-doc-dir   Add an extra doc dir for the doc dialog
#     --echo            Show result (default)
#     --noecho          Don't show result
#     --echo-on-assignment
#                       Show result on assignment
#     --noecho-on-assignment
#                       Don't show result on assignment
#     --truncate-echo-on-assignment
#                       Show truncated result on assignment (default)
#     --inspect         Use `inspect' for output
#     --noinspect       Don't use inspect for output
#     --multiline       Use multiline editor module
#     --nomultiline     Don't use multiline editor module
#     --singleline      Use singleline editor module
#     --nosingleline    Don't use singleline editor module
#     --colorize        Use colorization
#     --nocolorize      Don't use colorization
#     --autocomplete    Use autocompletion
#     --noautocomplete  Don't use autocompletion
#     --prompt prompt-mode/--prompt-mode prompt-mode
#                       Switch prompt mode. Pre-defined prompt modes are
#                       `default', `simple', `xmp' and `inf-ruby'
#     --inf-ruby-mode   Use prompt appropriate for inf-ruby-mode on emacs.
#                       Suppresses --multiline and --singleline.
#     --sample-book-mode/--simple-prompt
#                       Simple prompt mode
#     --noprompt        No prompt mode
#     --single-irb      Share self with sub-irb.
#     --tracer          Display trace for each execution of commands.
#     --back-trace-limit n
#                       Display backtrace top n and tail n. The default
#                       value is 16.
#     --verbose         Show details
#     --noverbose       Don't show details
#     -v, --version	    Print the version of irb
#     -h, --help        Print help
#     --                Separate options of irb from the list of command-line args
#
# == Configuration
#
# IRB reads from <code>~/.irbrc</code> when it's invoked.
#
# If <code>~/.irbrc</code> doesn't exist, +irb+ will try to read in the following order:
#
# * +.irbrc+
# * +irb.rc+
# * +_irbrc+
# * <code>$irbrc</code>
#
# The following are alternatives to the command line options. To use them type
# as follows in an +irb+ session:
#
#     IRB.conf[:IRB_NAME]="irb"
#     IRB.conf[:INSPECT_MODE]=nil
#     IRB.conf[:IRB_RC] = nil
#     IRB.conf[:BACK_TRACE_LIMIT]=16
#     IRB.conf[:USE_LOADER] = false
#     IRB.conf[:USE_MULTILINE] = nil
#     IRB.conf[:USE_SINGLELINE] = nil
#     IRB.conf[:USE_COLORIZE] = true
#     IRB.conf[:USE_TRACER] = false
#     IRB.conf[:USE_AUTOCOMPLETE] = true
#     IRB.conf[:IGNORE_SIGINT] = true
#     IRB.conf[:IGNORE_EOF] = false
#     IRB.conf[:PROMPT_MODE] = :DEFAULT
#     IRB.conf[:PROMPT] = {...}
#
# === Auto indentation
#
# To disable auto-indent mode in irb, add the following to your +.irbrc+:
#
#     IRB.conf[:AUTO_INDENT] = false
#
# === Autocompletion
#
# To enable autocompletion for irb, add the following to your +.irbrc+:
#
#     require 'irb/completion'
#
# === History
#
# By default, irb will store the last 1000 commands you used in
# <code>IRB.conf[:HISTORY_FILE]</code> (<code>~/.irb_history</code> by default).
#
# If you want to disable history, add the following to your +.irbrc+:
#
#     IRB.conf[:SAVE_HISTORY] = nil
#
# See IRB::Context#save_history= for more information.
#
# The history of _results_ of commands evaluated is not stored by default,
# but can be turned on to be stored with this +.irbrc+ setting:
#
#     IRB.conf[:EVAL_HISTORY] = <number>
#
# See IRB::Context#eval_history= and History class. The history of command
# results is not permanently saved in any file.
#
# == Customizing the IRB Prompt
#
# In order to customize the prompt, you can change the following Hash:
#
#     IRB.conf[:PROMPT]
#
# This example can be used in your +.irbrc+
#
#     IRB.conf[:PROMPT][:MY_PROMPT] = { # name of prompt mode
#       :AUTO_INDENT => false,          # disables auto-indent mode
#       :PROMPT_I =>  ">> ",		# simple prompt
#       :PROMPT_S => nil,		# prompt for continuated strings
#       :PROMPT_C => nil,		# prompt for continuated statement
#       :RETURN => "    ==>%s\n"	# format to return value
#     }
#
#     IRB.conf[:PROMPT_MODE] = :MY_PROMPT
#
# Or, invoke irb with the above prompt mode by:
#
#     irb --prompt my-prompt
#
# Constants +PROMPT_I+, +PROMPT_S+ and +PROMPT_C+ specify the format. In the
# prompt specification, some special strings are available:
#
#     %N    # command name which is running
#     %m    # to_s of main object (self)
#     %M    # inspect of main object (self)
#     %l    # type of string(", ', /, ]), `]' is inner %w[...]
#     %NNi  # indent level. NN is digits and means as same as printf("%NNd").
#           # It can be omitted
#     %NNn  # line number.
#     %%    # %
#
# For instance, the default prompt mode is defined as follows:
#
#     IRB.conf[:PROMPT_MODE][:DEFAULT] = {
#       :PROMPT_I => "%N(%m):%03n:%i> ",
#       :PROMPT_N => "%N(%m):%03n:%i> ",
#       :PROMPT_S => "%N(%m):%03n:%i%l ",
#       :PROMPT_C => "%N(%m):%03n:%i* ",
#       :RETURN => "%s\n" # used to printf
#     }
#
# irb comes with a number of available modes:
#
#   # :NULL:
#   #   :PROMPT_I:
#   #   :PROMPT_N:
#   #   :PROMPT_S:
#   #   :PROMPT_C:
#   #   :RETURN: |
#   #     %s
#   # :DEFAULT:
#   #   :PROMPT_I: ! '%N(%m):%03n:%i> '
#   #   :PROMPT_N: ! '%N(%m):%03n:%i> '
#   #   :PROMPT_S: ! '%N(%m):%03n:%i%l '
#   #   :PROMPT_C: ! '%N(%m):%03n:%i* '
#   #   :RETURN: |
#   #     => %s
#   # :CLASSIC:
#   #   :PROMPT_I: ! '%N(%m):%03n:%i> '
#   #   :PROMPT_N: ! '%N(%m):%03n:%i> '
#   #   :PROMPT_S: ! '%N(%m):%03n:%i%l '
#   #   :PROMPT_C: ! '%N(%m):%03n:%i* '
#   #   :RETURN: |
#   #     %s
#   # :SIMPLE:
#   #   :PROMPT_I: ! '>> '
#   #   :PROMPT_N: ! '>> '
#   #   :PROMPT_S:
#   #   :PROMPT_C: ! '?> '
#   #   :RETURN: |
#   #     => %s
#   # :INF_RUBY:
#   #   :PROMPT_I: ! '%N(%m):%03n:%i> '
#   #   :PROMPT_N:
#   #   :PROMPT_S:
#   #   :PROMPT_C:
#   #   :RETURN: |
#   #     %s
#   #   :AUTO_INDENT: true
#   # :XMP:
#   #   :PROMPT_I:
#   #   :PROMPT_N:
#   #   :PROMPT_S:
#   #   :PROMPT_C:
#   #   :RETURN: |2
#   #         ==>%s
#
# == Restrictions
#
# Because irb evaluates input immediately after it is syntactically complete,
# the results may be slightly different than directly using Ruby.
#
# == IRB Sessions
#
# IRB has a special feature, that allows you to manage many sessions at once.
#
# You can create new sessions with Irb.irb, and get a list of current sessions
# with the +jobs+ command in the prompt.
#
# === Commands
#
# JobManager provides commands to handle the current sessions:
#
#   jobs    # List of current sessions
#   fg      # Switches to the session of the given number
#   kill    # Kills the session with the given number
#
# The +exit+ command, or ::irb_exit, will quit the current session and call any
# exit hooks with IRB.irb_at_exit.
#
# A few commands for loading files within the session are also available:
#
# +source+::
#   Loads a given file in the current session and displays the source lines,
#   see IrbLoader#source_file
# +irb_load+::
#   Loads the given file similarly to Kernel#load, see IrbLoader#irb_load
# +irb_require+::
#   Loads the given file similarly to Kernel#require
#
# === Configuration
#
# The command line options, or IRB.conf, specify the default behavior of
# Irb.irb.
#
# On the other hand, each conf in IRB@Command+line+options is used to
# individually configure IRB.irb.
#
# If a proc is set for <code>IRB.conf[:IRB_RC]</code>, its will be invoked after execution
# of that proc with the context of the current session as its argument. Each
# session can be configured using this mechanism.
#
# === Session variables
#
# There are a few variables in every Irb session that can come in handy:
#
# <code>_</code>::
#   The value command executed, as a local variable
# <code>__</code>::
#   The history of evaluated commands. Available only if
#   <code>IRB.conf[:EVAL_HISTORY]</code> is not +nil+ (which is the default).
#   See also IRB::Context#eval_history= and IRB::History.
# <code>__[line_no]</code>::
#   Returns the evaluation value at the given line number, +line_no+.
#   If +line_no+ is a negative, the return value +line_no+ many lines before
#   the most recent return value.
#
# === Example using IRB Sessions
#
#   # invoke a new session
#   irb(main):001:0> irb
#   # list open sessions
#   irb.1(main):001:0> jobs
#     #0->irb on main (#<Thread:0x400fb7e4> : stop)
#     #1->irb#1 on main (#<Thread:0x40125d64> : running)
#
#   # change the active session
#   irb.1(main):002:0> fg 0
#   # define class Foo in top-level session
#   irb(main):002:0> class Foo;end
#   # invoke a new session with the context of Foo
#   irb(main):003:0> irb Foo
#   # define Foo#foo
#   irb.2(Foo):001:0> def foo
#   irb.2(Foo):002:1>   print 1
#   irb.2(Foo):003:1> end
#
#   # change the active session
#   irb.2(Foo):004:0> fg 0
#   # list open sessions
#   irb(main):004:0> jobs
#     #0->irb on main (#<Thread:0x400fb7e4> : running)
#     #1->irb#1 on main (#<Thread:0x40125d64> : stop)
#     #2->irb#2 on Foo (#<Thread:0x4011d54c> : stop)
#   # check if Foo#foo is available
#   irb(main):005:0> Foo.instance_methods #=> [:foo, ...]
#
#   # change the active session
#   irb(main):006:0> fg 2
#   # define Foo#bar in the context of Foo
#   irb.2(Foo):005:0> def bar
#   irb.2(Foo):006:1>  print "bar"
#   irb.2(Foo):007:1> end
#   irb.2(Foo):010:0>  Foo.instance_methods #=> [:bar, :foo, ...]
#
#   # change the active session
#   irb.2(Foo):011:0> fg 0
#   irb(main):007:0> f = Foo.new  #=> #<Foo:0x4010af3c>
#   # invoke a new session with the context of f (instance of Foo)
#   irb(main):008:0> irb f
#   # list open sessions
#   irb.3(<Foo:0x4010af3c>):001:0> jobs
#     #0->irb on main (#<Thread:0x400fb7e4> : stop)
#     #1->irb#1 on main (#<Thread:0x40125d64> : stop)
#     #2->irb#2 on Foo (#<Thread:0x4011d54c> : stop)
#     #3->irb#3 on #<Foo:0x4010af3c> (#<Thread:0x4010a1e0> : running)
#   # evaluate f.foo
#   irb.3(<Foo:0x4010af3c>):002:0> foo #=> 1 => nil
#   # evaluate f.bar
#   irb.3(<Foo:0x4010af3c>):003:0> bar #=> bar => nil
#   # kill jobs 1, 2, and 3
#   irb.3(<Foo:0x4010af3c>):004:0> kill 1, 2, 3
#   # list open sessions, should only include main session
#   irb(main):009:0> jobs
#     #0->irb on main (#<Thread:0x400fb7e4> : running)
#   # quit irb
#   irb(main):010:0> exit
module IRB

  # An exception raised by IRB.irb_abort
  class Abort < Exception;end

  @CONF = {}


  # Displays current configuration.
  #
  # Modifying the configuration is achieved by sending a message to IRB.conf.
  #
  # See IRB@Configuration for more information.
  def IRB.conf
    @CONF
  end

  # Returns the current version of IRB, including release version and last
  # updated date.
  def IRB.version
    if v = @CONF[:VERSION] then return v end

    @CONF[:VERSION] = format("irb %s (%s)", @RELEASE_VERSION, @LAST_UPDATE_DATE)
  end

  # The current IRB::Context of the session, see IRB.conf
  #
  #   irb
  #   irb(main):001:0> IRB.CurrentContext.irb_name = "foo"
  #   foo(main):002:0> IRB.conf[:MAIN_CONTEXT].irb_name #=> "foo"
  def IRB.CurrentContext
    IRB.conf[:MAIN_CONTEXT]
  end

  # Initializes IRB and creates a new Irb.irb object at the +TOPLEVEL_BINDING+
  def IRB.start(ap_path = nil)
    STDOUT.sync = true
    $0 = File::basename(ap_path, ".rb") if ap_path

    IRB.setup(ap_path)

    if @CONF[:SCRIPT]
      irb = Irb.new(nil, @CONF[:SCRIPT])
    else
      irb = Irb.new
    end
    irb.run(@CONF)
  end

  # Calls each event hook of <code>IRB.conf[:AT_EXIT]</code> when the current session quits.
  def IRB.irb_at_exit
    @CONF[:AT_EXIT].each{|hook| hook.call}
  end

  # Quits irb
  def IRB.irb_exit(irb, ret)
    throw :IRB_EXIT, ret
  end

  # Aborts then interrupts irb.
  #
  # Will raise an Abort exception, or the given +exception+.
  def IRB.irb_abort(irb, exception = Abort)
    if defined? Thread
      irb.context.thread.raise exception, "abort then interrupt!"
    else
      raise exception, "abort then interrupt!"
    end
  end

  class Irb
    ASSIGNMENT_NODE_TYPES = [
      # Local, instance, global, class, constant, instance, and index assignment:
      #   "foo = bar",
      #   "@foo = bar",
      #   "$foo = bar",
      #   "@@foo = bar",
      #   "::Foo = bar",
      #   "a::Foo = bar",
      #   "Foo = bar"
      #   "foo.bar = 1"
      #   "foo[1] = bar"
      :assign,

      # Operation assignment:
      #   "foo += bar"
      #   "foo -= bar"
      #   "foo ||= bar"
      #   "foo &&= bar"
      :opassign,

      # Multiple assignment:
      #   "foo, bar = 1, 2
      :massign,
    ]
    # Note: instance and index assignment expressions could also be written like:
    # "foo.bar=(1)" and "foo.[]=(1, bar)", when expressed that way, the former
    # be parsed as :assign and echo will be suppressed, but the latter is
    # parsed as a :method_add_arg and the output won't be suppressed

    # Creates a new irb session
    def initialize(workspace = nil, input_method = nil)
      @context = Context.new(self, workspace, input_method)
      @context.main.extend ExtendCommandBundle
      @signal_status = :IN_IRB
      @scanner = RubyLex.new
    end

    def run(conf = IRB.conf)
      conf[:IRB_RC].call(context) if conf[:IRB_RC]
      conf[:MAIN_CONTEXT] = context

      prev_trap = trap("SIGINT") do
        signal_handle
      end

      begin
        catch(:IRB_EXIT) do
          eval_input
        end
      ensure
        trap("SIGINT", prev_trap)
        conf[:AT_EXIT].each{|hook| hook.call}
      end
    end

    # Returns the current context of this irb session
    attr_reader :context
    # The lexer used by this irb session
    attr_accessor :scanner

    # Evaluates input for this session.
    def eval_input
      exc = nil

      @scanner.set_prompt do
        |ltype, indent, continue, line_no|
        if ltype
          f = @context.prompt_s
        elsif continue
          f = @context.prompt_c
        elsif indent > 0
          f = @context.prompt_n
        else
          f = @context.prompt_i
        end
        f = "" unless f
        if @context.prompting?
          @context.io.prompt = p = prompt(f, ltype, indent, line_no)
        else
          @context.io.prompt = p = ""
        end
        if @context.auto_indent_mode and !@context.io.respond_to?(:auto_indent)
          unless ltype
            prompt_i = @context.prompt_i.nil? ? "" : @context.prompt_i
            ind = prompt(prompt_i, ltype, indent, line_no)[/.*\z/].size +
              indent * 2 - p.size
            ind += 2 if continue
            @context.io.prompt = p + " " * ind if ind > 0
          end
        end
        @context.io.prompt
      end

      @scanner.set_input(@context.io, context: @context) do
        signal_status(:IN_INPUT) do
          if l = @context.io.gets
            print l if @context.verbose?
          else
            if @context.ignore_eof? and @context.io.readable_after_eof?
              l = "\n"
              if @context.verbose?
                printf "Use \"exit\" to leave %s\n", @context.ap_name
              end
            else
              print "\n" if @context.prompting?
            end
          end
          l
        end
      end

      @scanner.set_auto_indent(@context) if @context.auto_indent_mode

      @scanner.each_top_level_statement do |line, line_no|
        signal_status(:IN_EVAL) do
          begin
            line.untaint if RUBY_VERSION < '2.7'
            if IRB.conf[:MEASURE] && IRB.conf[:MEASURE_CALLBACKS].empty?
              IRB.set_measure_callback
            end
            if IRB.conf[:MEASURE] && !IRB.conf[:MEASURE_CALLBACKS].empty?
              result = nil
              last_proc = proc{ result = @context.evaluate(line, line_no, exception: exc) }
              IRB.conf[:MEASURE_CALLBACKS].inject(last_proc) { |chain, item|
                _name, callback, arg = item
                proc {
                  callback.(@context, line, line_no, arg, exception: exc) do
                    chain.call
                  end
                }
              }.call
              @context.set_last_value(result)
            else
              @context.evaluate(line, line_no, exception: exc)
            end
            if @context.echo?
              if assignment_expression?(line)
                if @context.echo_on_assignment?
                  output_value(@context.echo_on_assignment? == :truncate)
                end
              else
                output_value
              end
            end
          rescue Interrupt => exc
          rescue SystemExit, SignalException
            raise
          rescue Exception => exc
          else
            exc = nil
            next
          end
          handle_exception(exc)
          @context.workspace.local_variable_set(:_, exc)
          exc = nil
        end
      end
    end

    def convert_invalid_byte_sequence(str, enc)
      str.force_encoding(enc)
      str.scrub { |c|
        c.bytes.map{ |b| "\\x#{b.to_s(16).upcase}" }.join
      }
    end

    def encode_with_invalid_byte_sequence(str, enc)
      conv = Encoding::Converter.new(str.encoding, enc)
      dst = String.new
      begin
        ret = conv.primitive_convert(str, dst)
        case ret
        when :invalid_byte_sequence
          conv.insert_output(conv.primitive_errinfo[3].dump[1..-2])
          redo
        when :undefined_conversion
          c = conv.primitive_errinfo[3].dup.force_encoding(conv.primitive_errinfo[1])
          conv.insert_output(c.dump[1..-2])
          redo
        when :incomplete_input
          conv.insert_output(conv.primitive_errinfo[3].dump[1..-2])
        when :finished
        end
        break
      end while nil
      dst
    end

    def handle_exception(exc)
      if exc.backtrace && exc.backtrace[0] =~ /\/irb(2)?(\/.*|-.*|\.rb)?:/ && exc.class.to_s !~ /^IRB/ &&
         !(SyntaxError === exc) && !(EncodingError === exc)
        # The backtrace of invalid encoding hash (ex. {"\xAE": 1}) raises EncodingError without lineno.
        irb_bug = true
      else
        irb_bug = false
      end

      if exc.backtrace
        order = nil
        if '2.5.0' == RUBY_VERSION
          # Exception#full_message doesn't have keyword arguments.
          message = exc.full_message # the same of (highlight: true, order: bottom)
          order = :bottom
        elsif '2.5.1' <= RUBY_VERSION && RUBY_VERSION < '3.0.0'
          if STDOUT.tty?
            message = exc.full_message(order: :bottom)
            order = :bottom
          else
            message = exc.full_message(order: :top)
            order = :top
          end
        else # '3.0.0' <= RUBY_VERSION
          message = exc.full_message(order: :top)
          order = :top
        end
        message = convert_invalid_byte_sequence(message, exc.message.encoding)
        message = encode_with_invalid_byte_sequence(message, IRB.conf[:LC_MESSAGES].encoding) unless message.encoding.to_s.casecmp?(IRB.conf[:LC_MESSAGES].encoding.to_s)
        message = message.gsub(/((?:^\t.+$\n)+)/)  { |m|
          case order
          when :top
            lines = m.split("\n")
          when :bottom
            lines = m.split("\n").reverse
          end
          unless irb_bug
            lines = lines.map { |l| @context.workspace.filter_backtrace(l) }.compact
            if lines.size > @context.back_trace_limit
              omit = lines.size - @context.back_trace_limit
              lines = lines[0..(@context.back_trace_limit - 1)]
              lines << "\t... %d levels..." % omit
            end
          end
          lines = lines.reverse if order == :bottom
          lines.map{ |l| l + "\n" }.join
        }
        # The "<top (required)>" in "(irb)" may be the top level of IRB so imitate the main object.
        message = message.gsub(/\(irb\):(?<num>\d+):in `<(?<frame>top \(required\))>'/)  { "(irb):#{$~[:num]}:in `<main>'" }
        puts message
      end
      print "Maybe IRB bug!\n" if irb_bug
    end

    # Evaluates the given block using the given +path+ as the Context#irb_path
    # and +name+ as the Context#irb_name.
    #
    # Used by the irb command +source+, see IRB@IRB+Sessions for more
    # information.
    def suspend_name(path = nil, name = nil)
      @context.irb_path, back_path = path, @context.irb_path if path
      @context.irb_name, back_name = name, @context.irb_name if name
      begin
        yield back_path, back_name
      ensure
        @context.irb_path = back_path if path
        @context.irb_name = back_name if name
      end
    end

    # Evaluates the given block using the given +workspace+ as the
    # Context#workspace.
    #
    # Used by the irb command +irb_load+, see IRB@IRB+Sessions for more
    # information.
    def suspend_workspace(workspace)
      @context.workspace, back_workspace = workspace, @context.workspace
      begin
        yield back_workspace
      ensure
        @context.workspace = back_workspace
      end
    end

    # Evaluates the given block using the given +input_method+ as the
    # Context#io.
    #
    # Used by the irb commands +source+ and +irb_load+, see IRB@IRB+Sessions
    # for more information.
    def suspend_input_method(input_method)
      back_io = @context.io
      @context.instance_eval{@io = input_method}
      begin
        yield back_io
      ensure
        @context.instance_eval{@io = back_io}
      end
    end

    # Evaluates the given block using the given +context+ as the Context.
    def suspend_context(context)
      @context, back_context = context, @context
      begin
        yield back_context
      ensure
        @context = back_context
      end
    end

    # Handler for the signal SIGINT, see Kernel#trap for more information.
    def signal_handle
      unless @context.ignore_sigint?
        print "\nabort!\n" if @context.verbose?
        exit
      end

      case @signal_status
      when :IN_INPUT
        print "^C\n"
        raise RubyLex::TerminateLineInput
      when :IN_EVAL
        IRB.irb_abort(self)
      when :IN_LOAD
        IRB.irb_abort(self, LoadAbort)
      when :IN_IRB
        # ignore
      else
        # ignore other cases as well
      end
    end

    # Evaluates the given block using the given +status+.
    def signal_status(status)
      return yield if @signal_status == :IN_LOAD

      signal_status_back = @signal_status
      @signal_status = status
      begin
        yield
      ensure
        @signal_status = signal_status_back
      end
    end

    def prompt(prompt, ltype, indent, line_no) # :nodoc:
      p = prompt.dup
      p.gsub!(/%([0-9]+)?([a-zA-Z])/) do
        case $2
        when "N"
          @context.irb_name
        when "m"
          @context.main.to_s
        when "M"
          @context.main.inspect
        when "l"
          ltype
        when "i"
          if indent < 0
            if $1
              "-".rjust($1.to_i)
            else
              "-"
            end
          else
            if $1
              format("%" + $1 + "d", indent)
            else
              indent.to_s
            end
          end
        when "n"
          if $1
            format("%" + $1 + "d", line_no)
          else
            line_no.to_s
          end
        when "%"
          "%"
        end
      end
      p
    end

    def output_value(omit = false) # :nodoc:
      str = @context.inspect_last_value
      multiline_p = str.include?("\n")
      if omit
        winwidth = @context.io.winsize.last
        if multiline_p
          first_line = str.split("\n").first
          result = @context.newline_before_multiline_output? ? (@context.return_format % first_line) : first_line
          output_width = Reline::Unicode.calculate_width(result, true)
          diff_size = output_width - Reline::Unicode.calculate_width(first_line, true)
          if diff_size.positive? and output_width > winwidth
            lines, _ = Reline::Unicode.split_by_width(first_line, winwidth - diff_size - 3)
            str = "%s..." % lines.first
            str += "\e[0m" if @context.use_colorize
            multiline_p = false
          else
            str = str.gsub(/(\A.*?\n).*/m, "\\1...")
            str += "\e[0m" if @context.use_colorize
          end
        else
          output_width = Reline::Unicode.calculate_width(@context.return_format % str, true)
          diff_size = output_width - Reline::Unicode.calculate_width(str, true)
          if diff_size.positive? and output_width > winwidth
            lines, _ = Reline::Unicode.split_by_width(str, winwidth - diff_size - 3)
            str = "%s..." % lines.first
            str += "\e[0m" if @context.use_colorize
          end
        end
      end
      if multiline_p && @context.newline_before_multiline_output?
        printf @context.return_format, "\n#{str}"
      else
        printf @context.return_format, str
      end
    end

    # Outputs the local variables to this current session, including
    # #signal_status and #context, using IRB::Locale.
    def inspect
      ary = []
      for iv in instance_variables
        case (iv = iv.to_s)
        when "@signal_status"
          ary.push format("%s=:%s", iv, @signal_status.id2name)
        when "@context"
          ary.push format("%s=%s", iv, eval(iv).__to_s__)
        else
          ary.push format("%s=%s", iv, eval(iv))
        end
      end
      format("#<%s: %s>", self.class, ary.join(", "))
    end

    def assignment_expression?(line)
      # Try to parse the line and check if the last of possibly multiple
      # expressions is an assignment type.

      # If the expression is invalid, Ripper.sexp should return nil which will
      # result in false being returned. Any valid expression should return an
      # s-expression where the second element of the top level array is an
      # array of parsed expressions. The first element of each expression is the
      # expression's type.
      verbose, $VERBOSE = $VERBOSE, nil
      result = ASSIGNMENT_NODE_TYPES.include?(Ripper.sexp(line)&.dig(1,-1,0))
      $VERBOSE = verbose
      result
    end

    ATTR_TTY = "\e[%sm"
    def ATTR_TTY.[](*a) self % a.join(";"); end
    ATTR_PLAIN = ""
    def ATTR_PLAIN.[](*) self; end
  end

  def @CONF.inspect
    IRB.version unless self[:VERSION]

    array = []
    for k, v in sort{|a1, a2| a1[0].id2name <=> a2[0].id2name}
      case k
      when :MAIN_CONTEXT, :__TMP__EHV__
        array.push format("CONF[:%s]=...myself...", k.id2name)
      when :PROMPT
        s = v.collect{
          |kk, vv|
          ss = vv.collect{|kkk, vvv| ":#{kkk.id2name}=>#{vvv.inspect}"}
          format(":%s=>{%s}", kk.id2name, ss.join(", "))
        }
        array.push format("CONF[:%s]={%s}", k.id2name, s.join(", "))
      else
        array.push format("CONF[:%s]=%s", k.id2name, v.inspect)
      end
    end
    array.join("\n")
  end
end

class Binding
  # Opens an IRB session where +binding.irb+ is called which allows for
  # interactive debugging. You can call any methods or variables available in
  # the current scope, and mutate state if you need to.
  #
  #
  # Given a Ruby file called +potato.rb+ containing the following code:
  #
  #     class Potato
  #       def initialize
  #         @cooked = false
  #         binding.irb
  #         puts "Cooked potato: #{@cooked}"
  #       end
  #     end
  #
  #     Potato.new
  #
  # Running <code>ruby potato.rb</code> will open an IRB session where
  # +binding.irb+ is called, and you will see the following:
  #
  #     $ ruby potato.rb
  #
  #     From: potato.rb @ line 4 :
  #
  #         1: class Potato
  #         2:   def initialize
  #         3:     @cooked = false
  #      => 4:     binding.irb
  #         5:     puts "Cooked potato: #{@cooked}"
  #         6:   end
  #         7: end
  #         8:
  #         9: Potato.new
  #
  #     irb(#<Potato:0x00007feea1916670>):001:0>
  #
  # You can type any valid Ruby code and it will be evaluated in the current
  # context. This allows you to debug without having to run your code repeatedly:
  #
  #     irb(#<Potato:0x00007feea1916670>):001:0> @cooked
  #     => false
  #     irb(#<Potato:0x00007feea1916670>):002:0> self.class
  #     => Potato
  #     irb(#<Potato:0x00007feea1916670>):003:0> caller.first
  #     => ".../2.5.1/lib/ruby/2.5.0/irb/workspace.rb:85:in `eval'"
  #     irb(#<Potato:0x00007feea1916670>):004:0> @cooked = true
  #     => true
  #
  # You can exit the IRB session with the +exit+ command. Note that exiting will
  # resume execution where +binding.irb+ had paused it, as you can see from the
  # output printed to standard output in this example:
  #
  #     irb(#<Potato:0x00007feea1916670>):005:0> exit
  #     Cooked potato: true
  #
  #
  # See IRB@IRB+Usage for more information.
  def irb
    IRB.setup(source_location[0], argv: [])
    workspace = IRB::WorkSpace.new(self)
    STDOUT.print(workspace.code_around_binding)
    binding_irb = IRB::Irb.new(workspace)
    binding_irb.context.irb_path = File.expand_path(source_location[0])
    binding_irb.run(IRB.conf)
  end
end
