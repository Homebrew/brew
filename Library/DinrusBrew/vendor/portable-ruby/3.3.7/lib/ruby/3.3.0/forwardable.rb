# frozen_string_literal: false
#
#   forwardable.rb -
#       $Release Version: 1.1$
#       $Revision$
#       by Keiju ISHITSUKA(keiju@ishitsuka.com)
#       original definition by delegator.rb
#       Revised by Daniel J. Berger with suggestions from Florian Gross.
#
#       Documentation by James Edward Gray II and Gavin Sinclair



# The Forwardable module provides delegation of specified
# methods to a designated object, using the methods #def_delegator
# and #def_delegators.
#
# For example, say you have a class RecordCollection which
# contains an array <tt>@records</tt>.  You could provide the lookup method
# #record_number(), which simply calls #[] on the <tt>@records</tt>
# array, like this:
#
#   require 'forwardable'
#
#   class RecordCollection
#     attr_accessor :records
#     extend Forwardable
#     def_delegator :@records, :[], :record_number
#   end
#
# We can use the lookup method like so:
#
#   r = RecordCollection.new
#   r.records = [4,5,6]
#   r.record_number(0)  # => 4
#
# Further, if you wish to provide the methods #size, #<<, and #map,
# all of which delegate to @records, this is how you can do it:
#
#   class RecordCollection # re-open RecordCollection class
#     def_delegators :@records, :size, :<<, :map
#   end
#
#   r = RecordCollection.new
#   r.records = [1,2,3]
#   r.record_number(0)   # => 1
#   r.size               # => 3
#   r << 4               # => [1, 2, 3, 4]
#   r.map { |x| x * 2 }  # => [2, 4, 6, 8]
#
# You can even extend regular objects with Forwardable.
#
#   my_hash = Hash.new
#   my_hash.extend Forwardable              # prepare object for delegation
#   my_hash.def_delegator "STDOUT", "puts"  # add delegation for STDOUT.puts()
#   my_hash.puts "Howdy!"
#
# == Another example
#
# You could use Forwardable as an alternative to inheritance, when you don't want
# to inherit all methods from the superclass. For instance, here is how you might
# add a range of +Array+ instance methods to a new class +Queue+:
#
#   class Queue
#     extend Forwardable
#
#     def initialize
#       @q = [ ]    # prepare delegate object
#     end
#
#     # setup preferred interface, enq() and deq()...
#     def_delegator :@q, :push, :enq
#     def_delegator :@q, :shift, :deq
#
#     # support some general Array methods that fit Queues well
#     def_delegators :@q, :clear, :first, :push, :shift, :size
#   end
#
#   q = Thread::Queue.new
#   q.enq 1, 2, 3, 4, 5
#   q.push 6
#
#   q.shift    # => 1
#   while q.size > 0
#     puts q.deq
#   end
#
#   q.enq "Ruby", "Perl", "Python"
#   puts q.first
#   q.clear
#   puts q.first
#
# This should output:
#
#   2
#   3
#   4
#   5
#   6
#   Ruby
#   nil
#
# == Notes
#
# Be advised, RDoc will not detect delegated methods.
#
# +forwardable.rb+ provides single-method delegation via the def_delegator and
# def_delegators methods. For full-class delegation via DelegateClass, see
# +delegate.rb+.
#
module Forwardable
  require 'forwardable/impl'

  # Version of +forwardable.rb+
  VERSION = "1.3.3"
  VERSION.freeze
  FORWARDABLE_VERSION = VERSION
  FORWARDABLE_VERSION.freeze

  @debug = nil
  class << self
    # ignored
    attr_accessor :debug
  end

  # Takes a hash as its argument.  The key is a symbol or an array of
  # symbols.  These symbols correspond to method names, instance variable
  # names, or constant names (see def_delegator).  The value is
  # the accessor to which the methods will be delegated.
  #
  # :call-seq:
  #    delegate method => accessor
  #    delegate [method, method, ...] => accessor
  #
  def instance_delegate(hash)
    hash.each do |methods, accessor|
      unless defined?(methods.each)
        def_instance_delegator(accessor, methods)
      else
        methods.each {|method| def_instance_delegator(accessor, method)}
      end
    end
  end

  #
  # Shortcut for defining multiple delegator methods, but with no
  # provision for using a different name.  The following two code
  # samples have the same effect:
  #
  #   def_delegators :@records, :size, :<<, :map
  #
  #   def_delegator :@records, :size
  #   def_delegator :@records, :<<
  #   def_delegator :@records, :map
  #
  def def_instance_delegators(accessor, *methods)
    methods.each do |method|
      next if /\A__(?:send|id)__\z/ =~ method
      def_instance_delegator(accessor, method)
    end
  end

  # Define +method+ as delegator instance method with an optional
  # alias name +ali+. Method calls to +ali+ will be delegated to
  # +accessor.method+.  +accessor+ should be a method name, instance
  # variable name, or constant name.  Use the full path to the
  # constant if providing the constant name.
  # Returns the name of the method defined.
  #
  #   class MyQueue
  #     CONST = 1
  #     extend Forwardable
  #     attr_reader :queue
  #     def initialize
  #       @queue = []
  #     end
  #
  #     def_delegator :@queue, :push, :mypush
  #     def_delegator 'MyQueue::CONST', :to_i
  #   end
  #
  #   q = MyQueue.new
  #   q.mypush 42
  #   q.queue    #=> [42]
  #   q.push 23  #=> NoMethodError
  #   q.to_i     #=> 1
  #
  def def_instance_delegator(accessor, method, ali = method)
    gen = Forwardable._delegator_method(self, accessor, method, ali)

    # If it's not a class or module, it's an instance
    mod = Module === self ? self : singleton_class
    ret = mod.module_eval(&gen)
    mod.__send__(:ruby2_keywords, ali) if RUBY_VERSION >= '2.7'
    ret
  end

  alias delegate instance_delegate
  alias def_delegators def_instance_delegators
  alias def_delegator def_instance_delegator

  # :nodoc:
  def self._delegator_method(obj, accessor, method, ali)
    accessor = accessor.to_s unless Symbol === accessor

    if Module === obj ?
         obj.method_defined?(accessor) || obj.private_method_defined?(accessor) :
         obj.respond_to?(accessor, true)
      accessor = "#{accessor}()"
    end

    method_call = ".__send__(:#{method}, *args, &block)"
    if _valid_method?(method)
      loc, = caller_locations(2,1)
      pre = "_ ="
      mesg = "#{Module === obj ? obj : obj.class}\##{ali} at #{loc.path}:#{loc.lineno} forwarding to private method "
      method_call = "#{<<-"begin;"}\n#{<<-"end;".chomp}"
        begin;
          unless defined? _.#{method}
            ::Kernel.warn #{mesg.dump}"\#{_.class}"'##{method}', uplevel: 1
            _#{method_call}
          else
            _.#{method}(*args, &block)
          end
        end;
    end

    _compile_method("#{<<-"begin;"}\n#{<<-"end;"}", __FILE__, __LINE__+1)
    begin;
      proc do
        def #{ali}(*args, &block)
          #{pre}
          begin
            #{accessor}
          end#{method_call}
        end
      end
    end;
  end
end

# SingleForwardable can be used to setup delegation at the object level as well.
#
#    printer = String.new
#    printer.extend SingleForwardable        # prepare object for delegation
#    printer.def_delegator "STDOUT", "puts"  # add delegation for STDOUT.puts()
#    printer.puts "Howdy!"
#
# Also, SingleForwardable can be used to set up delegation for a Class or Module.
#
#   class Implementation
#     def self.service
#       puts "serviced!"
#     end
#   end
#
#   module Facade
#     extend SingleForwardable
#     def_delegator :Implementation, :service
#   end
#
#   Facade.service #=> serviced!
#
# If you want to use both Forwardable and SingleForwardable, you can
# use methods def_instance_delegator and def_single_delegator, etc.
module SingleForwardable
  # Takes a hash as its argument.  The key is a symbol or an array of
  # symbols.  These symbols correspond to method names.  The value is
  # the accessor to which the methods will be delegated.
  #
  # :call-seq:
  #    delegate method => accessor
  #    delegate [method, method, ...] => accessor
  #
  def single_delegate(hash)
    hash.each do |methods, accessor|
      unless defined?(methods.each)
        def_single_delegator(accessor, methods)
      else
        methods.each {|method| def_single_delegator(accessor, method)}
      end
    end
  end

  #
  # Shortcut for defining multiple delegator methods, but with no
  # provision for using a different name.  The following two code
  # samples have the same effect:
  #
  #   def_delegators :@records, :size, :<<, :map
  #
  #   def_delegator :@records, :size
  #   def_delegator :@records, :<<
  #   def_delegator :@records, :map
  #
  def def_single_delegators(accessor, *methods)
    methods.each do |method|
      next if /\A__(?:send|id)__\z/ =~ method
      def_single_delegator(accessor, method)
    end
  end

  # :call-seq:
  #   def_single_delegator(accessor, method, new_name=method)
  #
  # Defines a method _method_ which delegates to _accessor_ (i.e. it calls
  # the method of the same name in _accessor_).  If _new_name_ is
  # provided, it is used as the name for the delegate method.
  # Returns the name of the method defined.
  def def_single_delegator(accessor, method, ali = method)
    gen = Forwardable._delegator_method(self, accessor, method, ali)

    ret = instance_eval(&gen)
    singleton_class.__send__(:ruby2_keywords, ali) if RUBY_VERSION >= '2.7'
    ret
  end

  alias delegate single_delegate
  alias def_delegators def_single_delegators
  alias def_delegator def_single_delegator
end
