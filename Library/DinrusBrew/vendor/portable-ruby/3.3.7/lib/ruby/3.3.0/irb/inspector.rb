# frozen_string_literal: true
#
#   irb/inspector.rb - inspect methods
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#

module IRB # :nodoc:


  # Convenience method to create a new Inspector, using the given +inspect+
  # proc, and optional +init+ proc and passes them to Inspector.new
  #
  #     irb(main):001:0> ins = IRB::Inspector(proc{ |v| "omg! #{v}" })
  #     irb(main):001:0> IRB.CurrentContext.inspect_mode = ins # => omg! #<IRB::Inspector:0x007f46f7ba7d28>
  #     irb(main):001:0> "what?" #=> omg! what?
  #
  def IRB::Inspector(inspect, init = nil)
    Inspector.new(inspect, init)
  end

  # An irb inspector
  #
  # In order to create your own custom inspector there are two things you
  # should be aware of:
  #
  # Inspector uses #inspect_value, or +inspect_proc+, for output of return values.
  #
  # This also allows for an optional #init+, or +init_proc+, which is called
  # when the inspector is activated.
  #
  # Knowing this, you can create a rudimentary inspector as follows:
  #
  #     irb(main):001:0> ins = IRB::Inspector.new(proc{ |v| "omg! #{v}" })
  #     irb(main):001:0> IRB.CurrentContext.inspect_mode = ins # => omg! #<IRB::Inspector:0x007f46f7ba7d28>
  #     irb(main):001:0> "what?" #=> omg! what?
  #
  class Inspector
    KERNEL_INSPECT = Object.instance_method(:inspect)
    # Default inspectors available to irb, this includes:
    #
    # +:pp+::       Using Kernel#pretty_inspect
    # +:yaml+::     Using YAML.dump
    # +:marshal+::  Using Marshal.dump
    INSPECTORS = {}

    # Determines the inspector to use where +inspector+ is one of the keys passed
    # during inspector definition.
    def self.keys_with_inspector(inspector)
      INSPECTORS.select{|k, v| v == inspector}.collect{|k, v| k}
    end

    # Example
    #
    #     Inspector.def_inspector(key, init_p=nil){|v| v.inspect}
    #     Inspector.def_inspector([key1,..], init_p=nil){|v| v.inspect}
    #     Inspector.def_inspector(key, inspector)
    #     Inspector.def_inspector([key1,...], inspector)
    def self.def_inspector(key, arg=nil, &block)
      if block_given?
        inspector = IRB::Inspector(block, arg)
      else
        inspector = arg
      end

      case key
      when Array
        for k in key
          def_inspector(k, inspector)
        end
      when Symbol
        INSPECTORS[key] = inspector
        INSPECTORS[key.to_s] = inspector
      when String
        INSPECTORS[key] = inspector
        INSPECTORS[key.intern] = inspector
      else
        INSPECTORS[key] = inspector
      end
    end

    # Creates a new inspector object, using the given +inspect_proc+ when
    # output return values in irb.
    def initialize(inspect_proc, init_proc = nil)
      @init = init_proc
      @inspect = inspect_proc
    end

    # Proc to call when the inspector is activated, good for requiring
    # dependent libraries.
    def init
      @init.call if @init
    end

    # Proc to call when the input is evaluated and output in irb.
    def inspect_value(v)
      @inspect.call(v)
    rescue => e
      puts "An error occurred when inspecting the object: #{e.inspect}"

      begin
        puts "Result of Kernel#inspect: #{KERNEL_INSPECT.bind_call(v)}"
        ''
      rescue => e
        puts "An error occurred when running Kernel#inspect: #{e.inspect}"
        puts e.backtrace.join("\n")
        ''
      end
    end
  end

  Inspector.def_inspector([false, :to_s, :raw]){|v| v.to_s}
  Inspector.def_inspector([:p, :inspect]){|v|
    Color.colorize_code(v.inspect, colorable: Color.colorable? && Color.inspect_colorable?(v))
  }
  Inspector.def_inspector([true, :pp, :pretty_inspect], proc{require_relative "color_printer"}){|v|
    IRB::ColorPrinter.pp(v, +'').chomp
  }
  Inspector.def_inspector([:yaml, :YAML], proc{require "yaml"}){|v|
    begin
      YAML.dump(v)
    rescue
      puts "(can't dump yaml. use inspect)"
      v.inspect
    end
  }

  Inspector.def_inspector([:marshal, :Marshal, :MARSHAL, Marshal]){|v|
    Marshal.dump(v)
  }
end
