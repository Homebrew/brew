# frozen_string_literal: true
# = delegate -- Support for the Delegation Pattern
#
# Documentation by James Edward Gray II and Gavin Sinclair

##
# This library provides three different ways to delegate method calls to an
# object.  The easiest to use is SimpleDelegator.  Pass an object to the
# constructor and all methods supported by the object will be delegated.  This
# object can be changed later.
#
# Going a step further, the top level DelegateClass method allows you to easily
# setup delegation through class inheritance.  This is considerably more
# flexible and thus probably the most common use for this library.
#
# Finally, if you need full control over the delegation scheme, you can inherit
# from the abstract class Delegator and customize as needed.  (If you find
# yourself needing this control, have a look at Forwardable which is also in
# the standard library.  It may suit your needs better.)
#
# SimpleDelegator's implementation serves as a nice example of the use of
# Delegator:
#
#   require 'delegate'
#
#   class SimpleDelegator < Delegator
#     def __getobj__
#       @delegate_sd_obj # return object we are delegating to, required
#     end
#
#     def __setobj__(obj)
#       @delegate_sd_obj = obj # change delegation object,
#                              # a feature we're providing
#     end
#   end
#
# == Notes
#
# Be advised, RDoc will not detect delegated methods.
#
class Delegator < BasicObject
  VERSION = "0.3.1"

  kernel = ::Kernel.dup
  kernel.class_eval do
    alias __raise__ raise
    [:to_s, :inspect, :!~, :===, :<=>, :hash].each do |m|
      undef_method m
    end
    private_instance_methods.each do |m|
      if /\Ablock_given\?\z|\Aiterator\?\z|\A__.*__\z/ =~ m
        next
      end
      undef_method m
    end
  end
  include kernel

  # :stopdoc:
  def self.const_missing(n)
    ::Object.const_get(n)
  end
  # :startdoc:

  ##
  # :method: raise
  # Use #__raise__ if your Delegator does not have a object to delegate the
  # #raise method call.
  #

  #
  # Pass in the _obj_ to delegate method calls to.  All methods supported by
  # _obj_ will be delegated to.
  #
  def initialize(obj)
    __setobj__(obj)
  end

  #
  # Handles the magic of delegation through \_\_getobj\_\_.
  #
  ruby2_keywords def method_missing(m, *args, &block)
    r = true
    target = self.__getobj__ {r = false}

    if r && target_respond_to?(target, m, false)
      target.__send__(m, *args, &block)
    elsif ::Kernel.method_defined?(m) || ::Kernel.private_method_defined?(m)
      ::Kernel.instance_method(m).bind_call(self, *args, &block)
    else
      super(m, *args, &block)
    end
  end

  #
  # Checks for a method provided by this the delegate object by forwarding the
  # call through \_\_getobj\_\_.
  #
  def respond_to_missing?(m, include_private)
    r = true
    target = self.__getobj__ {r = false}
    r &&= target_respond_to?(target, m, include_private)
    if r && include_private && !target_respond_to?(target, m, false)
      warn "delegator does not forward private method \##{m}", uplevel: 3
      return false
    end
    r
  end

  KERNEL_RESPOND_TO = ::Kernel.instance_method(:respond_to?)
  private_constant :KERNEL_RESPOND_TO

  # Handle BasicObject instances
  private def target_respond_to?(target, m, include_private)
    case target
    when Object
      target.respond_to?(m, include_private)
    else
      if KERNEL_RESPOND_TO.bind_call(target, :respond_to?)
        target.respond_to?(m, include_private)
      else
        KERNEL_RESPOND_TO.bind_call(target, m, include_private)
      end
    end
  end

  #
  # Returns the methods available to this delegate object as the union
  # of this object's and \_\_getobj\_\_ methods.
  #
  def methods(all=true)
    __getobj__.methods(all) | super
  end

  #
  # Returns the methods available to this delegate object as the union
  # of this object's and \_\_getobj\_\_ public methods.
  #
  def public_methods(all=true)
    __getobj__.public_methods(all) | super
  end

  #
  # Returns the methods available to this delegate object as the union
  # of this object's and \_\_getobj\_\_ protected methods.
  #
  def protected_methods(all=true)
    __getobj__.protected_methods(all) | super
  end

  # Note: no need to specialize private_methods, since they are not forwarded

  #
  # Returns true if two objects are considered of equal value.
  #
  def ==(obj)
    return true if obj.equal?(self)
    self.__getobj__ == obj
  end

  #
  # Returns true if two objects are not considered of equal value.
  #
  def !=(obj)
    return false if obj.equal?(self)
    __getobj__ != obj
  end

  #
  # Returns true if two objects are considered of equal value.
  #
  def eql?(obj)
    return true if obj.equal?(self)
    obj.eql?(__getobj__)
  end

  #
  # Delegates ! to the \_\_getobj\_\_
  #
  def !
    !__getobj__
  end

  #
  # This method must be overridden by subclasses and should return the object
  # method calls are being delegated to.
  #
  def __getobj__
    __raise__ ::NotImplementedError, "need to define `__getobj__'"
  end

  #
  # This method must be overridden by subclasses and change the object delegate
  # to _obj_.
  #
  def __setobj__(obj)
    __raise__ ::NotImplementedError, "need to define `__setobj__'"
  end

  #
  # Serialization support for the object returned by \_\_getobj\_\_.
  #
  def marshal_dump
    ivars = instance_variables.reject {|var| /\A@delegate_/ =~ var}
    [
      :__v2__,
      ivars, ivars.map {|var| instance_variable_get(var)},
      __getobj__
    ]
  end

  #
  # Reinitializes delegation from a serialized object.
  #
  def marshal_load(data)
    version, vars, values, obj = data
    if version == :__v2__
      vars.each_with_index {|var, i| instance_variable_set(var, values[i])}
      __setobj__(obj)
    else
      __setobj__(data)
    end
  end

  def initialize_clone(obj, freeze: nil) # :nodoc:
    self.__setobj__(obj.__getobj__.clone(freeze: freeze))
  end
  def initialize_dup(obj) # :nodoc:
    self.__setobj__(obj.__getobj__.dup)
  end
  private :initialize_clone, :initialize_dup

  ##
  # :method: freeze
  # Freeze both the object returned by \_\_getobj\_\_ and self.
  #
  def freeze
    __getobj__.freeze
    super()
  end

  @delegator_api = self.public_instance_methods
  def self.public_api # :nodoc:
    @delegator_api
  end
end

##
# A concrete implementation of Delegator, this class provides the means to
# delegate all supported method calls to the object passed into the constructor
# and even to change the object being delegated to at a later time with
# #__setobj__.
#
#   class User
#     def born_on
#       Date.new(1989, 9, 10)
#     end
#   end
#
#   require 'delegate'
#
#   class UserDecorator < SimpleDelegator
#     def birth_year
#       born_on.year
#     end
#   end
#
#   decorated_user = UserDecorator.new(User.new)
#   decorated_user.birth_year  #=> 1989
#   decorated_user.__getobj__  #=> #<User: ...>
#
# A SimpleDelegator instance can take advantage of the fact that SimpleDelegator
# is a subclass of +Delegator+ to call <tt>super</tt> to have methods called on
# the object being delegated to.
#
#   class SuperArray < SimpleDelegator
#     def [](*args)
#       super + 1
#     end
#   end
#
#   SuperArray.new([1])[0]  #=> 2
#
# Here's a simple example that takes advantage of the fact that
# SimpleDelegator's delegation object can be changed at any time.
#
#   class Stats
#     def initialize
#       @source = SimpleDelegator.new([])
#     end
#
#     def stats(records)
#       @source.__setobj__(records)
#
#       "Elements:  #{@source.size}\n" +
#       " Non-Nil:  #{@source.compact.size}\n" +
#       "  Unique:  #{@source.uniq.size}\n"
#     end
#   end
#
#   s = Stats.new
#   puts s.stats(%w{James Edward Gray II})
#   puts
#   puts s.stats([1, 2, 3, nil, 4, 5, 1, 2])
#
# Prints:
#
#   Elements:  4
#    Non-Nil:  4
#     Unique:  4
#
#   Elements:  8
#    Non-Nil:  7
#     Unique:  6
#
class SimpleDelegator < Delegator
  # Returns the current object method calls are being delegated to.
  def __getobj__
    unless defined?(@delegate_sd_obj)
      return yield if block_given?
      __raise__ ::ArgumentError, "not delegated"
    end
    @delegate_sd_obj
  end

  #
  # Changes the delegate object to _obj_.
  #
  # It's important to note that this does *not* cause SimpleDelegator's methods
  # to change.  Because of this, you probably only want to change delegation
  # to objects of the same type as the original delegate.
  #
  # Here's an example of changing the delegation object.
  #
  #   names = SimpleDelegator.new(%w{James Edward Gray II})
  #   puts names[1]    # => Edward
  #   names.__setobj__(%w{Gavin Sinclair})
  #   puts names[1]    # => Sinclair
  #
  def __setobj__(obj)
    __raise__ ::ArgumentError, "cannot delegate to self" if self.equal?(obj)
    @delegate_sd_obj = obj
  end
end

def Delegator.delegating_block(mid) # :nodoc:
  lambda do |*args, &block|
    target = self.__getobj__
    target.__send__(mid, *args, &block)
  end.ruby2_keywords
end

#
# The primary interface to this library.  Use to setup delegation when defining
# your class.
#
#   class MyClass < DelegateClass(ClassToDelegateTo) # Step 1
#     def initialize
#       super(obj_of_ClassToDelegateTo)              # Step 2
#     end
#   end
#
# or:
#
#   MyClass = DelegateClass(ClassToDelegateTo) do    # Step 1
#     def initialize
#       super(obj_of_ClassToDelegateTo)              # Step 2
#     end
#   end
#
# Here's a sample of use from Tempfile which is really a File object with a
# few special rules about storage location and when the File should be
# deleted.  That makes for an almost textbook perfect example of how to use
# delegation.
#
#   class Tempfile < DelegateClass(File)
#     # constant and class member data initialization...
#
#     def initialize(basename, tmpdir=Dir::tmpdir)
#       # build up file path/name in var tmpname...
#
#       @tmpfile = File.open(tmpname, File::RDWR|File::CREAT|File::EXCL, 0600)
#
#       # ...
#
#       super(@tmpfile)
#
#       # below this point, all methods of File are supported...
#     end
#
#     # ...
#   end
#
def DelegateClass(superclass, &block)
  klass = Class.new(Delegator)
  ignores = [*::Delegator.public_api, :to_s, :inspect, :=~, :!~, :===]
  protected_instance_methods = superclass.protected_instance_methods
  protected_instance_methods -= ignores
  public_instance_methods = superclass.public_instance_methods
  public_instance_methods -= ignores
  klass.module_eval do
    def __getobj__ # :nodoc:
      unless defined?(@delegate_dc_obj)
        return yield if block_given?
        __raise__ ::ArgumentError, "not delegated"
      end
      @delegate_dc_obj
    end
    def __setobj__(obj)  # :nodoc:
      __raise__ ::ArgumentError, "cannot delegate to self" if self.equal?(obj)
      @delegate_dc_obj = obj
    end
    protected_instance_methods.each do |method|
      define_method(method, Delegator.delegating_block(method))
      protected method
    end
    public_instance_methods.each do |method|
      define_method(method, Delegator.delegating_block(method))
    end
  end
  klass.define_singleton_method :public_instance_methods do |all=true|
    super(all) | superclass.public_instance_methods
  end
  klass.define_singleton_method :protected_instance_methods do |all=true|
    super(all) | superclass.protected_instance_methods
  end
  klass.define_singleton_method :instance_methods do |all=true|
    super(all) | superclass.instance_methods
  end
  klass.define_singleton_method :public_instance_method do |name|
    super(name)
  rescue NameError
    raise unless self.public_instance_methods.include?(name)
    superclass.public_instance_method(name)
  end
  klass.define_singleton_method :instance_method do |name|
    super(name)
  rescue NameError
    raise unless self.instance_methods.include?(name)
    superclass.instance_method(name)
  end
  klass.module_eval(&block) if block
  return klass
end
