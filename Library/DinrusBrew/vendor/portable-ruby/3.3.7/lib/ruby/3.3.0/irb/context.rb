# frozen_string_literal: true
#
#   irb/context.rb - irb context
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#

require_relative "workspace"
require_relative "inspector"
require_relative "input-method"
require_relative "output-method"

module IRB
  # A class that wraps the current state of the irb session, including the
  # configuration of IRB.conf.
  class Context
    # Creates a new IRB context.
    #
    # The optional +input_method+ argument:
    #
    # +nil+::     uses stdin or Reline or Readline
    # +String+::  uses a File
    # +other+::   uses this as InputMethod
    def initialize(irb, workspace = nil, input_method = nil)
      @irb = irb
      @workspace_stack = []
      if workspace
        @workspace_stack << workspace
      else
        @workspace_stack << WorkSpace.new
      end
      @thread = Thread.current

      # copy of default configuration
      @ap_name = IRB.conf[:AP_NAME]
      @rc = IRB.conf[:RC]
      @load_modules = IRB.conf[:LOAD_MODULES]

      if IRB.conf.has_key?(:USE_SINGLELINE)
        @use_singleline = IRB.conf[:USE_SINGLELINE]
      elsif IRB.conf.has_key?(:USE_READLINE) # backward compatibility
        @use_singleline = IRB.conf[:USE_READLINE]
      else
        @use_singleline = nil
      end
      if IRB.conf.has_key?(:USE_MULTILINE)
        @use_multiline = IRB.conf[:USE_MULTILINE]
      elsif IRB.conf.has_key?(:USE_RELINE) # backward compatibility
        warn <<~MSG.strip
          USE_RELINE is deprecated, please use USE_MULTILINE instead.
        MSG
        @use_multiline = IRB.conf[:USE_RELINE]
      elsif IRB.conf.has_key?(:USE_REIDLINE)
        warn <<~MSG.strip
          USE_REIDLINE is deprecated, please use USE_MULTILINE instead.
        MSG
        @use_multiline = IRB.conf[:USE_REIDLINE]
      else
        @use_multiline = nil
      end
      @use_autocomplete = IRB.conf[:USE_AUTOCOMPLETE]
      @verbose = IRB.conf[:VERBOSE]
      @io = nil

      self.inspect_mode = IRB.conf[:INSPECT_MODE]
      self.use_tracer = IRB.conf[:USE_TRACER]
      self.use_loader = IRB.conf[:USE_LOADER] if IRB.conf[:USE_LOADER]
      self.eval_history = IRB.conf[:EVAL_HISTORY] if IRB.conf[:EVAL_HISTORY]

      @ignore_sigint = IRB.conf[:IGNORE_SIGINT]
      @ignore_eof = IRB.conf[:IGNORE_EOF]

      @back_trace_limit = IRB.conf[:BACK_TRACE_LIMIT]

      self.prompt_mode = IRB.conf[:PROMPT_MODE]

      if IRB.conf[:SINGLE_IRB] or !defined?(IRB::JobManager)
        @irb_name = IRB.conf[:IRB_NAME]
      else
        @irb_name = IRB.conf[:IRB_NAME]+"#"+IRB.JobManager.n_jobs.to_s
      end
      self.irb_path = "(" + @irb_name + ")"

      case input_method
      when nil
        @io = nil
        case use_multiline?
        when nil
          if term_interactive? && IRB.conf[:PROMPT_MODE] != :INF_RUBY && !use_singleline?
            # Both of multiline mode and singleline mode aren't specified.
            @io = RelineInputMethod.new(build_completor)
          else
            @io = nil
          end
        when false
          @io = nil
        when true
          @io = RelineInputMethod.new(build_completor)
        end
        unless @io
          case use_singleline?
          when nil
            if (defined?(ReadlineInputMethod) && term_interactive? &&
                IRB.conf[:PROMPT_MODE] != :INF_RUBY)
              @io = ReadlineInputMethod.new
            else
              @io = nil
            end
          when false
            @io = nil
          when true
            if defined?(ReadlineInputMethod)
              @io = ReadlineInputMethod.new
            else
              @io = nil
            end
          else
            @io = nil
          end
        end
        @io = StdioInputMethod.new unless @io

      when '-'
        @io = FileInputMethod.new($stdin)
        @irb_name = '-'
        self.irb_path = '-'
      when String
        @io = FileInputMethod.new(input_method)
        @irb_name = File.basename(input_method)
        self.irb_path = input_method
      else
        @io = input_method
      end
      @extra_doc_dirs = IRB.conf[:EXTRA_DOC_DIRS]

      @echo = IRB.conf[:ECHO]
      if @echo.nil?
        @echo = true
      end

      @echo_on_assignment = IRB.conf[:ECHO_ON_ASSIGNMENT]
      if @echo_on_assignment.nil?
        @echo_on_assignment = :truncate
      end

      @newline_before_multiline_output = IRB.conf[:NEWLINE_BEFORE_MULTILINE_OUTPUT]
      if @newline_before_multiline_output.nil?
        @newline_before_multiline_output = true
      end

      @user_aliases = IRB.conf[:COMMAND_ALIASES].dup
      @command_aliases = @user_aliases.merge(KEYWORD_ALIASES)
    end

    private def term_interactive?
      return true if ENV['TEST_IRB_FORCE_INTERACTIVE']
      STDIN.tty? && ENV['TERM'] != 'dumb'
    end

    # because all input will eventually be evaluated as Ruby code,
    # command names that conflict with Ruby keywords need special workaround
    # we can remove them once we implemented a better command system for IRB
    KEYWORD_ALIASES = {
      :break => :irb_break,
      :catch => :irb_catch,
      :next => :irb_next,
    }.freeze

    private_constant :KEYWORD_ALIASES

    def use_tracer=(val)
      require_relative "ext/tracer" if val
      IRB.conf[:USE_TRACER] = val
    end

    def eval_history=(val)
      self.class.remove_method(__method__)
      require_relative "ext/eval_history"
      __send__(__method__, val)
    end

    def use_loader=(val)
      self.class.remove_method(__method__)
      require_relative "ext/use-loader"
      __send__(__method__, val)
    end

    private def build_completor
      completor_type = IRB.conf[:COMPLETOR]
      case completor_type
      when :regexp
        return RegexpCompletor.new
      when :type
        completor = build_type_completor
        return completor if completor
      else
        warn "Invalid value for IRB.conf[:COMPLETOR]: #{completor_type}"
      end
      # Fallback to RegexpCompletor
      RegexpCompletor.new
    end

    private def build_type_completor
      if RUBY_ENGINE == 'truffleruby'
        # Avoid SyntaxError. truffleruby does not support endless method definition yet.
        warn 'TypeCompletor is not supported on TruffleRuby yet'
        return
      end

      begin
        require 'repl_type_completor'
      rescue LoadError => e
        warn "TypeCompletor requires `gem repl_type_completor`: #{e.message}"
        return
      end

      ReplTypeCompletor.preload_rbs
      TypeCompletor.new(self)
    end

    def save_history=(val)
      IRB.conf[:SAVE_HISTORY] = val
    end

    def save_history
      IRB.conf[:SAVE_HISTORY]
    end

    # A copy of the default <code>IRB.conf[:HISTORY_FILE]</code>
    def history_file
      IRB.conf[:HISTORY_FILE]
    end

    # Set <code>IRB.conf[:HISTORY_FILE]</code> to the given +hist+.
    def history_file=(hist)
      IRB.conf[:HISTORY_FILE] = hist
    end

    # Workspace in the current context.
    def workspace
      @workspace_stack.last
    end

    # Replace the current workspace with the given +workspace+.
    def replace_workspace(workspace)
      @workspace_stack.pop
      @workspace_stack.push(workspace)
    end

    # The top-level workspace, see WorkSpace#main
    def main
      workspace.main
    end

    # The toplevel workspace, see #home_workspace
    attr_reader :workspace_home
    # The current thread in this context.
    attr_reader :thread
    # The current input method.
    #
    # Can be either StdioInputMethod, ReadlineInputMethod,
    # RelineInputMethod, FileInputMethod or other specified when the
    # context is created. See ::new for more # information on +input_method+.
    attr_accessor :io

    # Current irb session.
    attr_accessor :irb
    # A copy of the default <code>IRB.conf[:AP_NAME]</code>
    attr_accessor :ap_name
    # A copy of the default <code>IRB.conf[:RC]</code>
    attr_accessor :rc
    # A copy of the default <code>IRB.conf[:LOAD_MODULES]</code>
    attr_accessor :load_modules
    # Can be either name from <code>IRB.conf[:IRB_NAME]</code>, or the number of
    # the current job set by JobManager, such as <code>irb#2</code>
    attr_accessor :irb_name

    # Can be one of the following:
    # - the #irb_name surrounded by parenthesis
    # - the +input_method+ passed to Context.new
    # - the file path of the current IRB context in a binding.irb session
    attr_reader :irb_path

    # Sets @irb_path to the given +path+ as well as @eval_path
    # @eval_path is used for evaluating code in the context of IRB session
    # It's the same as irb_path, but with the IRB name postfix
    # This makes sure users can distinguish the methods defined in the IRB session
    # from the methods defined in the current file's context, especially with binding.irb
    def irb_path=(path)
      @irb_path = path

      if File.exist?(path)
        @eval_path = "#{path}(#{IRB.conf[:IRB_NAME]})"
      else
        @eval_path = path
      end
    end

    # Whether multiline editor mode is enabled or not.
    #
    # A copy of the default <code>IRB.conf[:USE_MULTILINE]</code>
    attr_reader :use_multiline
    # Whether singleline editor mode is enabled or not.
    #
    # A copy of the default <code>IRB.conf[:USE_SINGLELINE]</code>
    attr_reader :use_singleline
    # Whether colorization is enabled or not.
    #
    # A copy of the default <code>IRB.conf[:USE_AUTOCOMPLETE]</code>
    attr_reader :use_autocomplete
    # A copy of the default <code>IRB.conf[:INSPECT_MODE]</code>
    attr_reader :inspect_mode

    # A copy of the default <code>IRB.conf[:PROMPT_MODE]</code>
    attr_reader :prompt_mode
    # Standard IRB prompt.
    #
    # See {Custom Prompts}[rdoc-ref:IRB@Custom+Prompts] for more information.
    attr_accessor :prompt_i
    # IRB prompt for continuated strings.
    #
    # See {Custom Prompts}[rdoc-ref:IRB@Custom+Prompts] for more information.
    attr_accessor :prompt_s
    # IRB prompt for continuated statement. (e.g. immediately after an +if+)
    #
    # See {Custom Prompts}[rdoc-ref:IRB@Custom+Prompts] for more information.
    attr_accessor :prompt_c

    # TODO: Remove this when developing v2.0
    def prompt_n
      warn "IRB::Context#prompt_n is deprecated and will be removed in the next major release."
      ""
    end

    # TODO: Remove this when developing v2.0
    def prompt_n=(_)
      warn "IRB::Context#prompt_n= is deprecated and will be removed in the next major release."
      ""
    end

    # Can be either the default <code>IRB.conf[:AUTO_INDENT]</code>, or the
    # mode set by #prompt_mode=
    #
    # To disable auto-indentation in irb:
    #
    #     IRB.conf[:AUTO_INDENT] = false
    #
    # or
    #
    #     irb_context.auto_indent_mode = false
    #
    # or
    #
    #     IRB.CurrentContext.auto_indent_mode = false
    #
    # See IRB@Configuration for more information.
    attr_accessor :auto_indent_mode
    # The format of the return statement, set by #prompt_mode= using the
    # +:RETURN+ of the +mode+ passed to set the current #prompt_mode.
    attr_accessor :return_format

    # Whether <code>^C</code> (+control-c+) will be ignored or not.
    #
    # If set to +false+, <code>^C</code> will quit irb.
    #
    # If set to +true+,
    #
    # * during input:   cancel input then return to top level.
    # * during execute: abandon current execution.
    attr_accessor :ignore_sigint
    # Whether <code>^D</code> (+control-d+) will be ignored or not.
    #
    # If set to +false+, <code>^D</code> will quit irb.
    attr_accessor :ignore_eof
    # Specify the installation locations of the ri file to be displayed in the
    # document dialog.
    attr_accessor :extra_doc_dirs
    # Whether to echo the return value to output or not.
    #
    # Uses <code>IRB.conf[:ECHO]</code> if available, or defaults to +true+.
    #
    #     puts "hello"
    #     # hello
    #     #=> nil
    #     IRB.CurrentContext.echo = false
    #     puts "omg"
    #     # omg
    attr_accessor :echo
    # Whether to echo for assignment expressions.
    #
    # If set to +false+, the value of assignment will not be shown.
    #
    # If set to +true+, the value of assignment will be shown.
    #
    # If set to +:truncate+, the value of assignment will be shown and truncated.
    #
    # It defaults to +:truncate+.
    #
    #     a = "omg"
    #     #=> omg
    #
    #     a = "omg" * 10
    #     #=> omgomgomgomgomgomgomg...
    #
    #     IRB.CurrentContext.echo_on_assignment = false
    #     a = "omg"
    #
    #     IRB.CurrentContext.echo_on_assignment = true
    #     a = "omg" * 10
    #     #=> omgomgomgomgomgomgomgomgomgomg
    #
    # To set the behaviour of showing on assignment in irb:
    #
    #     IRB.conf[:ECHO_ON_ASSIGNMENT] = :truncate or true or false
    #
    # or
    #
    #     irb_context.echo_on_assignment = :truncate or true or false
    #
    # or
    #
    #     IRB.CurrentContext.echo_on_assignment = :truncate or true or false
    attr_accessor :echo_on_assignment
    # Whether a newline is put before multiline output.
    #
    # Uses <code>IRB.conf[:NEWLINE_BEFORE_MULTILINE_OUTPUT]</code> if available,
    # or defaults to +true+.
    #
    #     "abc\ndef"
    #     #=>
    #     abc
    #     def
    #     IRB.CurrentContext.newline_before_multiline_output = false
    #     "abc\ndef"
    #     #=> abc
    #     def
    attr_accessor :newline_before_multiline_output
    # Whether verbose messages are displayed or not.
    #
    # A copy of the default <code>IRB.conf[:VERBOSE]</code>
    attr_accessor :verbose

    # The limit of backtrace lines displayed as top +n+ and tail +n+.
    #
    # The default value is 16.
    #
    # Can also be set using the +--back-trace-limit+ command line option.
    attr_accessor :back_trace_limit

    # User-defined IRB command aliases
    attr_accessor :command_aliases

    attr_accessor :with_debugger

    # Alias for #use_multiline
    alias use_multiline? use_multiline
    # Alias for #use_singleline
    alias use_singleline? use_singleline
    # backward compatibility
    alias use_reline use_multiline
    # backward compatibility
    alias use_reline? use_multiline
    # backward compatibility
    alias use_readline use_singleline
    # backward compatibility
    alias use_readline? use_singleline
    # Alias for #use_autocomplete
    alias use_autocomplete? use_autocomplete
    # Alias for #rc
    alias rc? rc
    alias ignore_sigint? ignore_sigint
    alias ignore_eof? ignore_eof
    alias echo? echo
    alias echo_on_assignment? echo_on_assignment
    alias newline_before_multiline_output? newline_before_multiline_output

    # Returns whether messages are displayed or not.
    def verbose?
      if @verbose.nil?
        if @io.kind_of?(RelineInputMethod)
          false
        elsif defined?(ReadlineInputMethod) && @io.kind_of?(ReadlineInputMethod)
          false
        elsif !STDIN.tty? or @io.kind_of?(FileInputMethod)
          true
        else
          false
        end
      else
        @verbose
      end
    end

    # Whether #verbose? is +true+, and +input_method+ is either
    # StdioInputMethod or RelineInputMethod or ReadlineInputMethod, see #io
    # for more information.
    def prompting?
      verbose? || @io.prompting?
    end

    # The return value of the last statement evaluated.
    attr_reader :last_value

    # Sets the return value from the last statement evaluated in this context
    # to #last_value.
    def set_last_value(value)
      @last_value = value
      workspace.local_variable_set :_, value
    end

    # Sets the +mode+ of the prompt in this context.
    #
    # See {Custom Prompts}[rdoc-ref:IRB@Custom+Prompts] for more information.
    def prompt_mode=(mode)
      @prompt_mode = mode
      pconf = IRB.conf[:PROMPT][mode]
      @prompt_i = pconf[:PROMPT_I]
      @prompt_s = pconf[:PROMPT_S]
      @prompt_c = pconf[:PROMPT_C]
      @return_format = pconf[:RETURN]
      @return_format = "%s\n" if @return_format == nil
      if ai = pconf.include?(:AUTO_INDENT)
        @auto_indent_mode = ai
      else
        @auto_indent_mode = IRB.conf[:AUTO_INDENT]
      end
    end

    # Whether #inspect_mode is set or not, see #inspect_mode= for more detail.
    def inspect?
      @inspect_mode.nil? or @inspect_mode
    end

    # Whether #io uses a File for the +input_method+ passed when creating the
    # current context, see ::new
    def file_input?
      @io.class == FileInputMethod
    end

    # Specifies the inspect mode with +opt+:
    #
    # +true+::  display +inspect+
    # +false+:: display +to_s+
    # +nil+::   inspect mode in non-math mode,
    #           non-inspect mode in math mode
    #
    # See IRB::Inspector for more information.
    #
    # Can also be set using the +--inspect+ and +--noinspect+ command line
    # options.
    def inspect_mode=(opt)

      if i = Inspector::INSPECTORS[opt]
        @inspect_mode = opt
        @inspect_method = i
        i.init
      else
        case opt
        when nil
          if Inspector.keys_with_inspector(Inspector::INSPECTORS[true]).include?(@inspect_mode)
            self.inspect_mode = false
          elsif Inspector.keys_with_inspector(Inspector::INSPECTORS[false]).include?(@inspect_mode)
            self.inspect_mode = true
          else
            puts "Can't switch inspect mode."
            return
          end
        when /^\s*\{.*\}\s*$/
          begin
            inspector = eval "proc#{opt}"
          rescue Exception
            puts "Can't switch inspect mode(#{opt})."
            return
          end
          self.inspect_mode = inspector
        when Proc
          self.inspect_mode = IRB::Inspector(opt)
        when Inspector
          prefix = "usr%d"
          i = 1
          while Inspector::INSPECTORS[format(prefix, i)]; i += 1; end
          @inspect_mode = format(prefix, i)
          @inspect_method = opt
          Inspector.def_inspector(format(prefix, i), @inspect_method)
        else
          puts "Can't switch inspect mode(#{opt})."
          return
        end
      end
      print "Switch to#{unless @inspect_mode; ' non';end} inspect mode.\n" if verbose?
      @inspect_mode
    end

    def evaluate(statement, line_no) # :nodoc:
      @line_no = line_no

      case statement
      when Statement::EmptyInput
        return
      when Statement::Expression
        result = evaluate_expression(statement.code, line_no)
        set_last_value(result)
      when Statement::Command
        statement.command_class.execute(self, statement.arg)
        set_last_value(nil)
      end

      nil
    end

    def from_binding?
      @irb.from_binding
    end

    def evaluate_expression(code, line_no) # :nodoc:
      result = nil
      if IRB.conf[:MEASURE] && IRB.conf[:MEASURE_CALLBACKS].empty?
        IRB.set_measure_callback
      end

      if IRB.conf[:MEASURE] && !IRB.conf[:MEASURE_CALLBACKS].empty?
        last_proc = proc do
          result = workspace.evaluate(code, @eval_path, line_no)
        end
        IRB.conf[:MEASURE_CALLBACKS].inject(last_proc) do |chain, item|
          _name, callback, arg = item
          proc do
            callback.(self, code, line_no, arg) do
              chain.call
            end
          end
        end.call
      else
        result = workspace.evaluate(code, @eval_path, line_no)
      end
      result
    end

    def inspect_last_value # :nodoc:
      @inspect_method.inspect_value(@last_value)
    end

    NOPRINTING_IVARS = ["@last_value"] # :nodoc:
    NO_INSPECTING_IVARS = ["@irb", "@io"] # :nodoc:
    IDNAME_IVARS = ["@prompt_mode"] # :nodoc:

    alias __inspect__ inspect
    def inspect # :nodoc:
      array = []
      for ivar in instance_variables.sort{|e1, e2| e1 <=> e2}
        ivar = ivar.to_s
        name = ivar.sub(/^@(.*)$/, '\1')
        val = instance_eval(ivar)
        case ivar
        when *NOPRINTING_IVARS
          array.push format("conf.%s=%s", name, "...")
        when *NO_INSPECTING_IVARS
          array.push format("conf.%s=%s", name, val.to_s)
        when *IDNAME_IVARS
          array.push format("conf.%s=:%s", name, val.id2name)
        else
          array.push format("conf.%s=%s", name, val.inspect)
        end
      end
      array.join("\n")
    end
    alias __to_s__ to_s
    alias to_s inspect

    def local_variables # :nodoc:
      workspace.binding.local_variables
    end
  end
end
