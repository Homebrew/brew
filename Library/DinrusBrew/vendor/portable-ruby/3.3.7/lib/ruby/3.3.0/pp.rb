# frozen_string_literal: true

require 'prettyprint'

##
# A pretty-printer for Ruby objects.
#
##
# == What PP Does
#
# Standard output by #p returns this:
#   #<PP:0x81fedf0 @genspace=#<Proc:0x81feda0>, @group_queue=#<PrettyPrint::GroupQueue:0x81fed3c @queue=[[#<PrettyPrint::Group:0x81fed78 @breakables=[], @depth=0, @break=false>], []]>, @buffer=[], @newline="\n", @group_stack=[#<PrettyPrint::Group:0x81fed78 @breakables=[], @depth=0, @break=false>], @buffer_width=0, @indent=0, @maxwidth=79, @output_width=2, @output=#<IO:0x8114ee4>>
#
# Pretty-printed output returns this:
#   #<PP:0x81fedf0
#    @buffer=[],
#    @buffer_width=0,
#    @genspace=#<Proc:0x81feda0>,
#    @group_queue=
#     #<PrettyPrint::GroupQueue:0x81fed3c
#      @queue=
#       [[#<PrettyPrint::Group:0x81fed78 @break=false, @breakables=[], @depth=0>],
#        []]>,
#    @group_stack=
#     [#<PrettyPrint::Group:0x81fed78 @break=false, @breakables=[], @depth=0>],
#    @indent=0,
#    @maxwidth=79,
#    @newline="\n",
#    @output=#<IO:0x8114ee4>,
#    @output_width=2>
#
##
# == Usage
#
#   pp(obj)             #=> obj
#   pp obj              #=> obj
#   pp(obj1, obj2, ...) #=> [obj1, obj2, ...]
#   pp()                #=> nil
#
# Output <tt>obj(s)</tt> to <tt>$></tt> in pretty printed format.
#
# It returns <tt>obj(s)</tt>.
#
##
# == Output Customization
#
# To define a customized pretty printing function for your classes,
# redefine method <code>#pretty_print(pp)</code> in the class.
# Note that <code>require 'pp'</code> is needed before redefining <code>#pretty_print(pp)</code>.
#
# <code>#pretty_print</code> takes the +pp+ argument, which is an instance of the PP class.
# The method uses #text, #breakable, #nest, #group and #pp to print the
# object.
#
##
# == Pretty-Print JSON
#
# To pretty-print JSON refer to JSON#pretty_generate.
#
##
# == Author
# Tanaka Akira <akr@fsij.org>

class PP < PrettyPrint

  VERSION = "0.5.0"

  # Returns the usable width for +out+.
  # As the width of +out+:
  # 1. If +out+ is assigned to a tty device, its width is used.
  # 2. Otherwise, or it could not get the value, the +COLUMN+
  #    environment variable is assumed to be set to the width.
  # 3. If +COLUMN+ is not set to a non-zero number, 80 is assumed.
  #
  # And finally, returns the above width value - 1.
  # * This -1 is for Windows command prompt, which moves the cursor to
  #   the next line if it reaches the last column.
  def PP.width_for(out)
    begin
      require 'io/console'
      _, width = out.winsize
    rescue LoadError, NoMethodError, SystemCallError
    end
    (width || ENV['COLUMNS']&.to_i&.nonzero? || 80) - 1
  end

  # Outputs +obj+ to +out+ in pretty printed format of
  # +width+ columns in width.
  #
  # If +out+ is omitted, <code>$></code> is assumed.
  # If +width+ is omitted, the width of +out+ is assumed (see
  # width_for).
  #
  # PP.pp returns +out+.
  def PP.pp(obj, out=$>, width=width_for(out))
    q = PP.new(out, width)
    q.guard_inspect_key {q.pp obj}
    q.flush
    #$pp = q
    out << "\n"
  end

  # Outputs +obj+ to +out+ like PP.pp but with no indent and
  # newline.
  #
  # PP.singleline_pp returns +out+.
  def PP.singleline_pp(obj, out=$>)
    q = SingleLine.new(out)
    q.guard_inspect_key {q.pp obj}
    q.flush
    out
  end

  # :stopdoc:
  def PP.mcall(obj, mod, meth, *args, &block)
    mod.instance_method(meth).bind_call(obj, *args, &block)
  end
  # :startdoc:

  if defined? ::Ractor
    class << self
      # Returns the sharing detection flag as a boolean value.
      # It is false (nil) by default.
      def sharing_detection
        Ractor.current[:pp_sharing_detection]
      end
      # Sets the sharing detection flag to b.
      def sharing_detection=(b)
        Ractor.current[:pp_sharing_detection] = b
      end
    end
  else
    @sharing_detection = false
    class << self
      # Returns the sharing detection flag as a boolean value.
      # It is false by default.
      attr_accessor :sharing_detection
    end
  end

  module PPMethods

    # Yields to a block
    # and preserves the previous set of objects being printed.
    def guard_inspect_key
      if Thread.current[:__recursive_key__] == nil
        Thread.current[:__recursive_key__] = {}.compare_by_identity
      end

      if Thread.current[:__recursive_key__][:inspect] == nil
        Thread.current[:__recursive_key__][:inspect] = {}.compare_by_identity
      end

      save = Thread.current[:__recursive_key__][:inspect]

      begin
        Thread.current[:__recursive_key__][:inspect] = {}.compare_by_identity
        yield
      ensure
        Thread.current[:__recursive_key__][:inspect] = save
      end
    end

    # Check whether the object_id +id+ is in the current buffer of objects
    # to be pretty printed. Used to break cycles in chains of objects to be
    # pretty printed.
    def check_inspect_key(id)
      Thread.current[:__recursive_key__] &&
      Thread.current[:__recursive_key__][:inspect] &&
      Thread.current[:__recursive_key__][:inspect].include?(id)
    end

    # Adds the object_id +id+ to the set of objects being pretty printed, so
    # as to not repeat objects.
    def push_inspect_key(id)
      Thread.current[:__recursive_key__][:inspect][id] = true
    end

    # Removes an object from the set of objects being pretty printed.
    def pop_inspect_key(id)
      Thread.current[:__recursive_key__][:inspect].delete id
    end

    # Adds +obj+ to the pretty printing buffer
    # using Object#pretty_print or Object#pretty_print_cycle.
    #
    # Object#pretty_print_cycle is used when +obj+ is already
    # printed, a.k.a the object reference chain has a cycle.
    def pp(obj)
      # If obj is a Delegator then use the object being delegated to for cycle
      # detection
      obj = obj.__getobj__ if defined?(::Delegator) and obj.is_a?(::Delegator)

      if check_inspect_key(obj)
        group {obj.pretty_print_cycle self}
        return
      end

      begin
        push_inspect_key(obj)
        group {obj.pretty_print self}
      ensure
        pop_inspect_key(obj) unless PP.sharing_detection
      end
    end

    # A convenience method which is same as follows:
    #
    #   group(1, '#<' + obj.class.name, '>') { ... }
    def object_group(obj, &block) # :yield:
      group(1, '#<' + obj.class.name, '>', &block)
    end

    # A convenience method, like object_group, but also reformats the Object's
    # object_id.
    def object_address_group(obj, &block)
      str = Kernel.instance_method(:to_s).bind_call(obj)
      str.chomp!('>')
      group(1, str, '>', &block)
    end

    # A convenience method which is same as follows:
    #
    #   text ','
    #   breakable
    def comma_breakable
      text ','
      breakable
    end

    # Adds a separated list.
    # The list is separated by comma with breakable space, by default.
    #
    # #seplist iterates the +list+ using +iter_method+.
    # It yields each object to the block given for #seplist.
    # The procedure +separator_proc+ is called between each yields.
    #
    # If the iteration is zero times, +separator_proc+ is not called at all.
    #
    # If +separator_proc+ is nil or not given,
    # +lambda { comma_breakable }+ is used.
    # If +iter_method+ is not given, :each is used.
    #
    # For example, following 3 code fragments has similar effect.
    #
    #   q.seplist([1,2,3]) {|v| xxx v }
    #
    #   q.seplist([1,2,3], lambda { q.comma_breakable }, :each) {|v| xxx v }
    #
    #   xxx 1
    #   q.comma_breakable
    #   xxx 2
    #   q.comma_breakable
    #   xxx 3
    def seplist(list, sep=nil, iter_method=:each) # :yield: element
      sep ||= lambda { comma_breakable }
      first = true
      list.__send__(iter_method) {|*v|
        if first
          first = false
        else
          sep.call
        end
        RUBY_VERSION >= "3.0" ? yield(*v, **{}) : yield(*v)
      }
    end

    # A present standard failsafe for pretty printing any given Object
    def pp_object(obj)
      object_address_group(obj) {
        seplist(obj.pretty_print_instance_variables, lambda { text ',' }) {|v|
          breakable
          v = v.to_s if Symbol === v
          text v
          text '='
          group(1) {
            breakable ''
            pp(obj.instance_eval(v))
          }
        }
      }
    end

    # A pretty print for a Hash
    def pp_hash(obj)
      group(1, '{', '}') {
        seplist(obj, nil, :each_pair) {|k, v|
          group {
            pp k
            text '=>'
            group(1) {
              breakable ''
              pp v
            }
          }
        }
      }
    end
  end

  include PPMethods

  class SingleLine < PrettyPrint::SingleLine # :nodoc:
    include PPMethods
  end

  module ObjectMixin # :nodoc:
    # 1. specific pretty_print
    # 2. specific inspect
    # 3. generic pretty_print

    # A default pretty printing method for general objects.
    # It calls #pretty_print_instance_variables to list instance variables.
    #
    # If +self+ has a customized (redefined) #inspect method,
    # the result of self.inspect is used but it obviously has no
    # line break hints.
    #
    # This module provides predefined #pretty_print methods for some of
    # the most commonly used built-in classes for convenience.
    def pretty_print(q)
      umethod_method = Object.instance_method(:method)
      begin
        inspect_method = umethod_method.bind_call(self, :inspect)
      rescue NameError
      end
      if inspect_method && inspect_method.owner != Kernel
        q.text self.inspect
      elsif !inspect_method && self.respond_to?(:inspect)
        q.text self.inspect
      else
        q.pp_object(self)
      end
    end

    # A default pretty printing method for general objects that are
    # detected as part of a cycle.
    def pretty_print_cycle(q)
      q.object_address_group(self) {
        q.breakable
        q.text '...'
      }
    end

    # Returns a sorted array of instance variable names.
    #
    # This method should return an array of names of instance variables as symbols or strings as:
    # +[:@a, :@b]+.
    def pretty_print_instance_variables
      instance_variables.sort
    end

    # Is #inspect implementation using #pretty_print.
    # If you implement #pretty_print, it can be used as follows.
    #
    #   alias inspect pretty_print_inspect
    #
    # However, doing this requires that every class that #inspect is called on
    # implement #pretty_print, or a RuntimeError will be raised.
    def pretty_print_inspect
      if Object.instance_method(:method).bind_call(self, :pretty_print).owner == PP::ObjectMixin
        raise "pretty_print is not overridden for #{self.class}"
      end
      PP.singleline_pp(self, ''.dup)
    end
  end
end

class Array # :nodoc:
  def pretty_print(q) # :nodoc:
    q.group(1, '[', ']') {
      q.seplist(self) {|v|
        q.pp v
      }
    }
  end

  def pretty_print_cycle(q) # :nodoc:
    q.text(empty? ? '[]' : '[...]')
  end
end

class Hash # :nodoc:
  def pretty_print(q) # :nodoc:
    q.pp_hash self
  end

  def pretty_print_cycle(q) # :nodoc:
    q.text(empty? ? '{}' : '{...}')
  end
end

class << ENV # :nodoc:
  def pretty_print(q) # :nodoc:
    h = {}
    ENV.keys.sort.each {|k|
      h[k] = ENV[k]
    }
    q.pp_hash h
  end
end

class Struct # :nodoc:
  def pretty_print(q) # :nodoc:
    q.group(1, sprintf("#<struct %s", PP.mcall(self, Kernel, :class).name), '>') {
      q.seplist(PP.mcall(self, Struct, :members), lambda { q.text "," }) {|member|
        q.breakable
        q.text member.to_s
        q.text '='
        q.group(1) {
          q.breakable ''
          q.pp self[member]
        }
      }
    }
  end

  def pretty_print_cycle(q) # :nodoc:
    q.text sprintf("#<struct %s:...>", PP.mcall(self, Kernel, :class).name)
  end
end

class Data # :nodoc:
  def pretty_print(q) # :nodoc:
    q.group(1, sprintf("#<data %s", PP.mcall(self, Kernel, :class).name), '>') {
      q.seplist(PP.mcall(self, Data, :members), lambda { q.text "," }) {|member|
        q.breakable
        q.text member.to_s
        q.text '='
        q.group(1) {
          q.breakable ''
          q.pp public_send(member)
        }
      }
    }
  end

  def pretty_print_cycle(q) # :nodoc:
    q.text sprintf("#<data %s:...>", PP.mcall(self, Kernel, :class).name)
  end
end if "3.2" <= RUBY_VERSION

class Range # :nodoc:
  def pretty_print(q) # :nodoc:
    q.pp self.begin
    q.breakable ''
    q.text(self.exclude_end? ? '...' : '..')
    q.breakable ''
    q.pp self.end if self.end
  end
end

class String # :nodoc:
  def pretty_print(q) # :nodoc:
    lines = self.lines
    if lines.size > 1
      q.group(0, '', '') do
        q.seplist(lines, lambda { q.text ' +'; q.breakable }) do |v|
          q.pp v
        end
      end
    else
      q.text inspect
    end
  end
end

class File < IO # :nodoc:
  class Stat # :nodoc:
    def pretty_print(q) # :nodoc:
      require 'etc'
      q.object_group(self) {
        q.breakable
        q.text sprintf("dev=0x%x", self.dev); q.comma_breakable
        q.text "ino="; q.pp self.ino; q.comma_breakable
        q.group {
          m = self.mode
          q.text sprintf("mode=0%o", m)
          q.breakable
          q.text sprintf("(%s %c%c%c%c%c%c%c%c%c)",
            self.ftype,
            (m & 0400 == 0 ? ?- : ?r),
            (m & 0200 == 0 ? ?- : ?w),
            (m & 0100 == 0 ? (m & 04000 == 0 ? ?- : ?S) :
                             (m & 04000 == 0 ? ?x : ?s)),
            (m & 0040 == 0 ? ?- : ?r),
            (m & 0020 == 0 ? ?- : ?w),
            (m & 0010 == 0 ? (m & 02000 == 0 ? ?- : ?S) :
                             (m & 02000 == 0 ? ?x : ?s)),
            (m & 0004 == 0 ? ?- : ?r),
            (m & 0002 == 0 ? ?- : ?w),
            (m & 0001 == 0 ? (m & 01000 == 0 ? ?- : ?T) :
                             (m & 01000 == 0 ? ?x : ?t)))
        }
        q.comma_breakable
        q.text "nlink="; q.pp self.nlink; q.comma_breakable
        q.group {
          q.text "uid="; q.pp self.uid
          begin
            pw = Etc.getpwuid(self.uid)
          rescue ArgumentError
          end
          if pw
            q.breakable; q.text "(#{pw.name})"
          end
        }
        q.comma_breakable
        q.group {
          q.text "gid="; q.pp self.gid
          begin
            gr = Etc.getgrgid(self.gid)
          rescue ArgumentError
          end
          if gr
            q.breakable; q.text "(#{gr.name})"
          end
        }
        q.comma_breakable
        q.group {
          q.text sprintf("rdev=0x%x", self.rdev)
          if self.rdev_major && self.rdev_minor
            q.breakable
            q.text sprintf('(%d, %d)', self.rdev_major, self.rdev_minor)
          end
        }
        q.comma_breakable
        q.text "size="; q.pp self.size; q.comma_breakable
        q.text "blksize="; q.pp self.blksize; q.comma_breakable
        q.text "blocks="; q.pp self.blocks; q.comma_breakable
        q.group {
          t = self.atime
          q.text "atime="; q.pp t
          q.breakable; q.text "(#{t.tv_sec})"
        }
        q.comma_breakable
        q.group {
          t = self.mtime
          q.text "mtime="; q.pp t
          q.breakable; q.text "(#{t.tv_sec})"
        }
        q.comma_breakable
        q.group {
          t = self.ctime
          q.text "ctime="; q.pp t
          q.breakable; q.text "(#{t.tv_sec})"
        }
      }
    end
  end
end

class MatchData # :nodoc:
  def pretty_print(q) # :nodoc:
    nc = []
    self.regexp.named_captures.each {|name, indexes|
      indexes.each {|i| nc[i] = name }
    }
    q.object_group(self) {
      q.breakable
      q.seplist(0...self.size, lambda { q.breakable }) {|i|
        if i == 0
          q.pp self[i]
        else
          if nc[i]
            q.text nc[i]
          else
            q.pp i
          end
          q.text ':'
          q.pp self[i]
        end
      }
    }
  end
end

if defined?(RubyVM::AbstractSyntaxTree)
  class RubyVM::AbstractSyntaxTree::Node
    def pretty_print_children(q, names = [])
      children.zip(names) do |c, n|
        if n
          q.breakable
          q.text "#{n}:"
        end
        q.group(2) do
          q.breakable
          q.pp c
        end
      end
    end

    def pretty_print(q)
      q.group(1, "(#{type}@#{first_lineno}:#{first_column}-#{last_lineno}:#{last_column}", ")") {
        case type
        when :SCOPE
          pretty_print_children(q, %w"tbl args body")
        when :ARGS
          pretty_print_children(q, %w[pre_num pre_init opt first_post post_num post_init rest kw kwrest block])
        when :DEFN
          pretty_print_children(q, %w[mid body])
        when :ARYPTN
          pretty_print_children(q, %w[const pre rest post])
        when :HSHPTN
          pretty_print_children(q, %w[const kw kwrest])
        else
          pretty_print_children(q)
        end
      }
    end
  end
end

class Object < BasicObject # :nodoc:
  include PP::ObjectMixin
end

[Numeric, Symbol, FalseClass, TrueClass, NilClass, Module].each {|c|
  c.class_eval {
    def pretty_print_cycle(q)
      q.text inspect
    end
  }
}

[Numeric, FalseClass, TrueClass, Module].each {|c|
  c.class_eval {
    def pretty_print(q)
      q.text inspect
    end
  }
}

module Kernel
  # Returns a pretty printed object as a string.
  #
  # See the PP module for more information.
  def pretty_inspect
    PP.pp(self, ''.dup)
  end

  # prints arguments in pretty form.
  #
  # pp returns argument(s).
  def pp(*objs)
    objs.each {|obj|
      PP.pp(obj)
    }
    objs.size <= 1 ? objs.first : objs
  end
  module_function :pp
end
