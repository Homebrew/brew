# frozen_string_literal: false
#
#   irb/extend-command.rb - irb extend command
#   	$Release Version: 0.9.6$
#   	$Revision$
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#
# --
#
#
#
module IRB # :nodoc:
  # Installs the default irb extensions command bundle.
  module ExtendCommandBundle
    EXCB = ExtendCommandBundle # :nodoc:

    # See #install_alias_method.
    NO_OVERRIDE = 0
    # See #install_alias_method.
    OVERRIDE_PRIVATE_ONLY = 0x01
    # See #install_alias_method.
    OVERRIDE_ALL = 0x02

    # Quits the current irb context
    #
    # +ret+ is the optional signal or message to send to Context#exit
    #
    # Same as <code>IRB.CurrentContext.exit</code>.
    def irb_exit(ret = 0)
      irb_context.exit(ret)
    end

    # Displays current configuration.
    #
    # Modifying the configuration is achieved by sending a message to IRB.conf.
    def irb_context
      IRB.CurrentContext
    end

    @ALIASES = [
      [:context, :irb_context, NO_OVERRIDE],
      [:conf, :irb_context, NO_OVERRIDE],
      [:irb_quit, :irb_exit, OVERRIDE_PRIVATE_ONLY],
      [:exit, :irb_exit, OVERRIDE_PRIVATE_ONLY],
      [:quit, :irb_exit, OVERRIDE_PRIVATE_ONLY],
    ]

    @EXTEND_COMMANDS = [
      [
        :irb_current_working_workspace, :CurrentWorkingWorkspace, "irb/cmd/chws",
        [:irb_print_working_workspace, OVERRIDE_ALL],
        [:irb_cwws, OVERRIDE_ALL],
        [:irb_pwws, OVERRIDE_ALL],
        [:cwws, NO_OVERRIDE],
        [:pwws, NO_OVERRIDE],
        [:irb_current_working_binding, OVERRIDE_ALL],
        [:irb_print_working_binding, OVERRIDE_ALL],
        [:irb_cwb, OVERRIDE_ALL],
        [:irb_pwb, OVERRIDE_ALL],
      ],
      [
        :irb_change_workspace, :ChangeWorkspace, "irb/cmd/chws",
        [:irb_chws, OVERRIDE_ALL],
        [:irb_cws, OVERRIDE_ALL],
        [:chws, NO_OVERRIDE],
        [:cws, NO_OVERRIDE],
        [:irb_change_binding, OVERRIDE_ALL],
        [:irb_cb, OVERRIDE_ALL],
        [:cb, NO_OVERRIDE],
      ],

      [
        :irb_workspaces, :Workspaces, "irb/cmd/pushws",
        [:workspaces, NO_OVERRIDE],
        [:irb_bindings, OVERRIDE_ALL],
        [:bindings, NO_OVERRIDE],
      ],
      [
        :irb_push_workspace, :PushWorkspace, "irb/cmd/pushws",
        [:irb_pushws, OVERRIDE_ALL],
        [:pushws, NO_OVERRIDE],
        [:irb_push_binding, OVERRIDE_ALL],
        [:irb_pushb, OVERRIDE_ALL],
        [:pushb, NO_OVERRIDE],
      ],
      [
        :irb_pop_workspace, :PopWorkspace, "irb/cmd/pushws",
        [:irb_popws, OVERRIDE_ALL],
        [:popws, NO_OVERRIDE],
        [:irb_pop_binding, OVERRIDE_ALL],
        [:irb_popb, OVERRIDE_ALL],
        [:popb, NO_OVERRIDE],
      ],

      [
        :irb_load, :Load, "irb/cmd/load"],
      [
        :irb_require, :Require, "irb/cmd/load"],
      [
        :irb_source, :Source, "irb/cmd/load",
        [:source, NO_OVERRIDE],
      ],

      [
        :irb, :IrbCommand, "irb/cmd/subirb"],
      [
        :irb_jobs, :Jobs, "irb/cmd/subirb",
        [:jobs, NO_OVERRIDE],
      ],
      [
        :irb_fg, :Foreground, "irb/cmd/subirb",
        [:fg, NO_OVERRIDE],
      ],
      [
        :irb_kill, :Kill, "irb/cmd/subirb",
        [:kill, OVERRIDE_PRIVATE_ONLY],
      ],

      [
        :irb_help, :Help, "irb/cmd/help",
        [:help, NO_OVERRIDE],
      ],

      [
        :irb_info, :Info, "irb/cmd/info"
      ],

      [
        :irb_ls, :Ls, "irb/cmd/ls",
        [:ls, NO_OVERRIDE],
      ],

      [
        :irb_measure, :Measure, "irb/cmd/measure",
        [:measure, NO_OVERRIDE],
      ],

      [
        :irb_show_source, :ShowSource, "irb/cmd/show_source",
        [:show_source, NO_OVERRIDE],
      ],

      [
        :irb_whereami, :Whereami, "irb/cmd/whereami",
        [:whereami, NO_OVERRIDE],
      ],

    ]

    # Installs the default irb commands:
    #
    # +irb_current_working_workspace+::   Context#main
    # +irb_change_workspace+::            Context#change_workspace
    # +irb_workspaces+::                  Context#workspaces
    # +irb_push_workspace+::              Context#push_workspace
    # +irb_pop_workspace+::               Context#pop_workspace
    # +irb_load+::                        #irb_load
    # +irb_require+::                     #irb_require
    # +irb_source+::                      IrbLoader#source_file
    # +irb+::                             IRB.irb
    # +irb_jobs+::                        JobManager
    # +irb_fg+::                          JobManager#switch
    # +irb_kill+::                        JobManager#kill
    # +irb_help+::                        IRB@Command+line+options
    def self.install_extend_commands
      for args in @EXTEND_COMMANDS
        def_extend_command(*args)
      end
    end

    # Evaluate the given +cmd_name+ on the given +cmd_class+ Class.
    #
    # Will also define any given +aliases+ for the method.
    #
    # The optional +load_file+ parameter will be required within the method
    # definition.
    def self.def_extend_command(cmd_name, cmd_class, load_file = nil, *aliases)
      case cmd_class
      when Symbol
        cmd_class = cmd_class.id2name
      when String
      when Class
        cmd_class = cmd_class.name
      end

      if load_file
        kwargs = ", **kwargs" if RUBY_ENGINE == "ruby" && RUBY_VERSION >= "2.7.0"
        line = __LINE__; eval %[
          def #{cmd_name}(*opts#{kwargs}, &b)
            require "#{load_file}"
            arity = ExtendCommand::#{cmd_class}.instance_method(:execute).arity
            args = (1..(arity < 0 ? ~arity : arity)).map {|i| "arg" + i.to_s }
            args << "*opts#{kwargs}" if arity < 0
            args << "&block"
            args = args.join(", ")
            line = __LINE__; eval %[
              unless singleton_class.class_variable_defined?(:@@#{cmd_name}_)
                singleton_class.class_variable_set(:@@#{cmd_name}_, true)
                def self.#{cmd_name}_(\#{args})
                  ExtendCommand::#{cmd_class}.execute(irb_context, \#{args})
                end
              end
            ], nil, __FILE__, line
            __send__ :#{cmd_name}_, *opts#{kwargs}, &b
          end
        ], nil, __FILE__, line
      else
        line = __LINE__; eval %[
          def #{cmd_name}(*opts, &b)
            ExtendCommand::#{cmd_class}.execute(irb_context, *opts, &b)
          end
        ], nil, __FILE__, line
      end

      for ali, flag in aliases
        @ALIASES.push [ali, cmd_name, flag]
      end
    end

    # Installs alias methods for the default irb commands, see
    # ::install_extend_commands.
    def install_alias_method(to, from, override = NO_OVERRIDE)
      to = to.id2name unless to.kind_of?(String)
      from = from.id2name unless from.kind_of?(String)

      if override == OVERRIDE_ALL or
          (override == OVERRIDE_PRIVATE_ONLY) && !respond_to?(to) or
          (override == NO_OVERRIDE) &&  !respond_to?(to, true)
        target = self
        (class << self; self; end).instance_eval{
          if target.respond_to?(to, true) &&
            !target.respond_to?(EXCB.irb_original_method_name(to), true)
            alias_method(EXCB.irb_original_method_name(to), to)
          end
          alias_method to, from
        }
      else
        print "irb: warn: can't alias #{to} from #{from}.\n"
      end
    end

    def self.irb_original_method_name(method_name) # :nodoc:
      "irb_" + method_name + "_org"
    end

    # Installs alias methods for the default irb commands on the given object
    # using #install_alias_method.
    def self.extend_object(obj)
      unless (class << obj; ancestors; end).include?(EXCB)
        super
        for ali, com, flg in @ALIASES
          obj.install_alias_method(ali, com, flg)
        end
      end
    end

    install_extend_commands
  end

  # Extends methods for the Context module
  module ContextExtender
    CE = ContextExtender # :nodoc:

    @EXTEND_COMMANDS = [
      [:eval_history=, "irb/ext/history.rb"],
      [:use_tracer=, "irb/ext/tracer.rb"],
      [:use_loader=, "irb/ext/use-loader.rb"],
      [:save_history=, "irb/ext/save-history.rb"],
    ]

    # Installs the default context extensions as irb commands:
    #
    # Context#eval_history=::   +irb/ext/history.rb+
    # Context#use_tracer=::     +irb/ext/tracer.rb+
    # Context#use_loader=::     +irb/ext/use-loader.rb+
    # Context#save_history=::   +irb/ext/save-history.rb+
    def self.install_extend_commands
      for args in @EXTEND_COMMANDS
        def_extend_command(*args)
      end
    end

    # Evaluate the given +command+ from the given +load_file+ on the Context
    # module.
    #
    # Will also define any given +aliases+ for the method.
    def self.def_extend_command(cmd_name, load_file, *aliases)
      line = __LINE__; Context.module_eval %[
        def #{cmd_name}(*opts, &b)
          Context.module_eval {remove_method(:#{cmd_name})}
          require "#{load_file}"
          __send__ :#{cmd_name}, *opts, &b
        end
        for ali in aliases
          alias_method ali, cmd_name
        end
      ], __FILE__, line
    end

    CE.install_extend_commands
  end

  # A convenience module for extending Ruby methods.
  module MethodExtender
    # Extends the given +base_method+ with a prefix call to the given
    # +extend_method+.
    def def_pre_proc(base_method, extend_method)
      base_method = base_method.to_s
      extend_method = extend_method.to_s

      alias_name = new_alias_name(base_method)
      module_eval %[
        alias_method alias_name, base_method
        def #{base_method}(*opts)
          __send__ :#{extend_method}, *opts
          __send__ :#{alias_name}, *opts
        end
      ]
    end

    # Extends the given +base_method+ with a postfix call to the given
    # +extend_method+.
    def def_post_proc(base_method, extend_method)
      base_method = base_method.to_s
      extend_method = extend_method.to_s

      alias_name = new_alias_name(base_method)
      module_eval %[
        alias_method alias_name, base_method
        def #{base_method}(*opts)
          __send__ :#{alias_name}, *opts
          __send__ :#{extend_method}, *opts
        end
      ]
    end

    # Returns a unique method name to use as an alias for the given +name+.
    #
    # Usually returns <code>#{prefix}#{name}#{postfix}<num></code>, example:
    #
    #     new_alias_name('foo') #=> __alias_of__foo__
    #     def bar; end
    #     new_alias_name('bar') #=> __alias_of__bar__2
    def new_alias_name(name, prefix = "__alias_of__", postfix = "__")
      base_name = "#{prefix}#{name}#{postfix}"
      all_methods = instance_methods(true) + private_instance_methods(true)
      same_methods = all_methods.grep(/^#{Regexp.quote(base_name)}[0-9]*$/)
      return base_name if same_methods.empty?
      no = same_methods.size
      while !same_methods.include?(alias_name = base_name + no)
        no += 1
      end
      alias_name
    end
  end
end
