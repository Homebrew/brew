require 'monitor'

module Warning
  module Processor
    # Map of symbols to regexps for warning messages to ignore.
    IGNORE_MAP = {
      ambiguous_slash: /: warning: ambiguous first argument; put parentheses or a space even after [`']\/' operator\n\z|: warning: ambiguity between regexp and two divisions: wrap regexp in parentheses or add a space after [`']\/' operator\n\z|ambiguous `\/`; wrap regexp in parentheses or add a space after `\/` operator\n\z/,
      arg_prefix: /: warning: ([`'][&\*]'||ambiguous `[\*&]` has been) interpreted as( an)? argument prefix\n\z/,
      bignum: /: warning: constant ::Bignum is deprecated\n\z/,
      default_gem_removal: /: warning: .+? was loaded from the standard library, but will no longer be part of the default gems starting from Ruby [\d.]+\./,
      fixnum: /: warning: constant ::Fixnum is deprecated\n\z/,
      ignored_block: /: warning: the block passed to '.+' defined at .+:\d+ may be ignored\n\z/,
      method_redefined: /: warning: method redefined; discarding old .+\n\z|: warning: previous definition of .+ was here\n\z/,
      missing_gvar: /: warning: global variable [`']\$.+' not initialized\n\z/,
      missing_ivar: /: warning: instance variable @.+ not initialized\n\z/,
      not_reached: /: warning: statement not reached\n\z/,
      shadow: /: warning: shadowing outer local variable - \w+\n\z/,
      unused_var: /: warning: assigned but unused variable - \w+\n\z/,
      useless_operator: /: warning: possibly useless use of [><!=]+ in void context\n\z/,
      keyword_separation: /: warning: (?:Using the last argument (?:for [`'].+' )?as keyword parameters is deprecated; maybe \*\* should be added to the call|Passing the keyword argument (?:for [`'].+' )?as the last hash parameter is deprecated|Splitting the last argument (?:for [`'].+' )?into positional and keyword parameters is deprecated|The called method (?:[`'].+' )?is defined here)\n\z/,
      safe: /: warning: (?:rb_safe_level_2_warning|rb_safe_level|rb_set_safe_level_force|rb_set_safe_level|rb_secure|rb_insecure_operation|rb_check_safe_obj|\$SAFE) will (?:be removed|become a normal global variable) in Ruby 3\.0\n\z/,
      taint: /: warning: (?:rb_error_untrusted|rb_check_trusted|Pathname#taint|Pathname#untaint|rb_env_path_tainted|Object#tainted\?|Object#taint|Object#untaint|Object#untrusted\?|Object#untrust|Object#trust|rb_obj_infect|rb_tainted_str_new|rb_tainted_str_new_cstr) is deprecated and will be removed in Ruby 3\.2\.?\n\z/,
      mismatched_indentations: /: warning: mismatched indentations at '.+' with '.+' at \d+\n\z/,
      void_context: /possibly useless use of (?:a )?\S+ in void context/,
    }

    # Map of action symbols to procs that return the symbol
    ACTION_PROC_MAP = {
      raise: proc{|_| :raise},
      default: proc{|_| :default},
      backtrace: proc{|_| :backtrace},
    }
    private_constant :ACTION_PROC_MAP

    # Clear all current ignored warnings, warning processors, and duplicate check cache.
    # Also disables deduplicating warnings if that is currently enabled.
    #
    # If a block is passed, the previous values are restored after the block exits.
    #
    # Examples:
    #
    #   # Clear warning state
    #   Warning.clear
    #
    #   Warning.clear do
    #     # Clear warning state inside the block
    #     ...
    #   end
    #   # Previous warning state restored when block exists
    def clear
      if block_given?
        ignore = process = dedup = nil
        synchronize do
          ignore = @ignore.dup
          process = @process.dup
          dedup = @dedup.dup
        end

        begin
          clear
          yield
        ensure
          synchronize do
            @ignore = ignore
            @process = process
            @dedup = dedup
          end
        end
      else
        synchronize do
          @ignore.clear
          @process.clear
          @dedup = false
        end
      end
    end

    # Deduplicate warnings, suppress warning messages if the same warning message
    # has already occurred.  Note that this can lead to unbounded memory use
    # if unique warnings are generated.
    def dedup
      @dedup = {}
    end

    def freeze
      @ignore.freeze
      @process.freeze
      super
    end
    
    # Ignore any warning messages matching the given regexp, if they
    # start with the given path.
    # The regexp can also be one of the following symbols (or an array including them), which will
    # use an appropriate regexp for the given warning:
    #
    # :arg_prefix :: Ignore warnings when using * or & as an argument prefix
    # :ambiguous_slash :: Ignore warnings for things like <tt>method /regexp/</tt>
    # :bignum :: Ignore warnings when referencing the ::Bignum constant.
    # :default_gem_removal :: Ignore warnings that a gem will be removed from the default gems
    #                         in a future Ruby version.
    # :fixnum :: Ignore warnings when referencing the ::Fixnum constant.
    # :keyword_separation :: Ignore warnings related to keyword argument separation.
    # :method_redefined :: Ignore warnings when defining a method in a class/module where a
    #                      method of the same name was already defined in that class/module.
    # :missing_gvar :: Ignore warnings for accesses to global variables
    #                  that have not yet been initialized
    # :missing_ivar :: Ignore warnings for accesses to instance variables
    #                  that have not yet been initialized
    # :not_reached :: Ignore statement not reached warnings.
    # :safe :: Ignore warnings related to $SAFE and related C-API functions.
    # :shadow :: Ignore warnings related to shadowing outer local variables.
    # :taint :: Ignore warnings related to taint and related methods and C-API functions.
    # :unused_var :: Ignore warnings for unused variables.
    # :useless_operator :: Ignore warnings when using operators such as == and > when the
    #                      result is not used.
    # :void_context :: Ignore warnings for :: to reference constants when the result is not
    #                  used (often used to trigger autoload).
    #
    # Examples:
    #
    #   # Ignore all uninitialized instance variable warnings
    #   Warning.ignore(/instance variable @\w+ not initialized/)
    #
    #   # Ignore all uninitialized instance variable warnings in current file
    #   Warning.ignore(/instance variable @\w+ not initialized/, __FILE__)
    #
    #   # Ignore all uninitialized instance variable warnings in current file
    #   Warning.ignore(:missing_ivar, __FILE__)
    #
    #   # Ignore all uninitialized instance variable and method redefined warnings in current file
    #   Warning.ignore([:missing_ivar, :method_redefined],  __FILE__)
    def ignore(regexp, path='')
      unless regexp = convert_regexp(regexp)
        raise TypeError, "first argument to Warning.ignore should be Regexp, Symbol, or Array of Symbols, got #{regexp.inspect}"
      end

      synchronize do 
        @ignore << [path, regexp]
      end
      nil
    end

    # Handle all warnings starting with the given path, instead of
    # the default behavior of printing them to $stderr. Examples:
    #
    #   # Write warning to LOGGER at level warning
    #   Warning.process do |warning|
    #     LOGGER.warning(warning)
    #   end
    #
    #   # Write warnings in the current file to LOGGER at level error level
    #   Warning.process(__FILE__) do |warning|
    #     LOGGER.error(warning)
    #   end
    #
    # The block can return one of the following symbols:
    #
    # :default :: Take the default action (call super, printing to $stderr).
    # :backtrace :: Take the default action (call super, printing to $stderr),
    #               and also print the backtrace.
    # :raise :: Raise a RuntimeError with the warning as the message.
    #
    # If the block returns anything else, it is assumed the block completely handled
    # the warning and takes no other action.
    #
    # Instead of passing a block, you can pass a hash of actions to take for specific
    # warnings, using regexp as keys and a callable objects as values:
    #
    #   Warning.process(__FILE__,
    #     /instance variable @\w+ not initialized/ => proc do |warning|
    #       LOGGER.warning(warning)
    #     end,
    #     /global variable [`']\$\w+' not initialized/ => proc do |warning|
    #       LOGGER.error(warning)
    #     end
    #   )
    #
    # Instead of passing a regexp as a key, you can pass a symbol that is recognized
    # by Warning.ignore.  Instead of passing a callable object as a value, you can
    # pass a symbol, which will be treated as a callable object that returns that symbol:
    #
    #   Warning.process(__FILE__, :missing_ivar=>:backtrace, :keyword_separation=>:raise)
    def process(path='', actions=nil, &block)
      unless path.is_a?(String)
        raise ArgumentError, "path must be a String (given an instance of #{path.class})"
      end

      if block
        if actions
          raise ArgumentError, "cannot pass both actions and block to Warning.process"
        end
      elsif actions
        block = {}
        actions.each do |regexp, value|
          unless regexp = convert_regexp(regexp)
            raise TypeError, "action provided to Warning.process should be Regexp, Symbol, or Array of Symbols, got #{regexp.inspect}"
          end

          block[regexp] = ACTION_PROC_MAP[value] || value
        end
      else
        raise ArgumentError, "must pass either actions or block to Warning.process"
      end

      synchronize do
        @process << [path, block]
        @process.sort_by!(&:first)
        @process.reverse!
      end
      nil
    end


    if RUBY_VERSION >= '3.0'
      method_args = ', category: nil'
      super_ = "category ? super : super(str)"
    # :nocov:
    else
      super_ = "super"
    # :nocov:
    end

    class_eval(<<-END, __FILE__, __LINE__+1)
      def warn(str#{method_args})
        synchronize{@ignore.dup}.each do |path, regexp|
          if str.start_with?(path) && regexp.match?(str)
            return
          end
        end

        if @dedup
          if synchronize{@dedup[str]}
            return
          end

          synchronize{@dedup[str] = true}
        end

        action = catch(:action) do
          synchronize{@process.dup}.each do |path, block|
            if str.start_with?(path)
              if block.is_a?(Hash)
                block.each do |regexp, blk|
                  if regexp.match?(str)
                    throw :action, blk.call(str)
                  end
                end
              else
                throw :action, block.call(str)
              end
            end
          end

          :default
        end

        case action
        when :default
          #{super_}
        when :backtrace
          #{super_}
          $stderr.puts caller
        when :raise
          raise str
        else
          # nothing
        end

        nil
      end
    END

    private

    # Convert the given Regexp, Symbol, or Array of Symbols into a Regexp.
    def convert_regexp(regexp)
      case regexp
      when Regexp
        regexp
      when Symbol
        IGNORE_MAP.fetch(regexp)
      when Array
        Regexp.union(regexp.map{|re| IGNORE_MAP.fetch(re)})
      else
        # nothing
      end
    end

    def synchronize(&block)
      @monitor.synchronize(&block)
    end
  end

  @ignore = []
  @process = []
  @dedup = false
  @monitor = Monitor.new

  extend Processor
end
