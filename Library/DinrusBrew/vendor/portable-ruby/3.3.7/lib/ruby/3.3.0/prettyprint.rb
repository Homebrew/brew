# frozen_string_literal: true
#
# This class implements a pretty printing algorithm. It finds line breaks and
# nice indentations for grouped structure.
#
# By default, the class assumes that primitive elements are strings and each
# byte in the strings have single column in width. But it can be used for
# other situations by giving suitable arguments for some methods:
# * newline object and space generation block for PrettyPrint.new
# * optional width argument for PrettyPrint#text
# * PrettyPrint#breakable
#
# There are several candidate uses:
# * text formatting using proportional fonts
# * multibyte characters which has columns different to number of bytes
# * non-string formatting
#
# == Bugs
# * Box based formatting?
# * Other (better) model/algorithm?
#
# Report any bugs at http://bugs.ruby-lang.org
#
# == References
# Christian Lindig, Strictly Pretty, March 2000,
# https://lindig.github.io/papers/strictly-pretty-2000.pdf
#
# Philip Wadler, A prettier printer, March 1998,
# https://homepages.inf.ed.ac.uk/wadler/topics/language-design.html#prettier
#
# == Author
# Tanaka Akira <akr@fsij.org>
#
class PrettyPrint

  VERSION = "0.2.0"

  # This is a convenience method which is same as follows:
  #
  #   begin
  #     q = PrettyPrint.new(output, maxwidth, newline, &genspace)
  #     ...
  #     q.flush
  #     output
  #   end
  #
  def PrettyPrint.format(output=''.dup, maxwidth=79, newline="\n", genspace=lambda {|n| ' ' * n})
    q = PrettyPrint.new(output, maxwidth, newline, &genspace)
    yield q
    q.flush
    output
  end

  # This is similar to PrettyPrint::format but the result has no breaks.
  #
  # +maxwidth+, +newline+ and +genspace+ are ignored.
  #
  # The invocation of +breakable+ in the block doesn't break a line and is
  # treated as just an invocation of +text+.
  #
  def PrettyPrint.singleline_format(output=''.dup, maxwidth=nil, newline=nil, genspace=nil)
    q = SingleLine.new(output)
    yield q
    output
  end

  # Creates a buffer for pretty printing.
  #
  # +output+ is an output target. If it is not specified, '' is assumed. It
  # should have a << method which accepts the first argument +obj+ of
  # PrettyPrint#text, the first argument +sep+ of PrettyPrint#breakable, the
  # first argument +newline+ of PrettyPrint.new, and the result of a given
  # block for PrettyPrint.new.
  #
  # +maxwidth+ specifies maximum line length. If it is not specified, 79 is
  # assumed. However actual outputs may overflow +maxwidth+ if long
  # non-breakable texts are provided.
  #
  # +newline+ is used for line breaks. "\n" is used if it is not specified.
  #
  # The block is used to generate spaces. {|width| ' ' * width} is used if it
  # is not given.
  #
  def initialize(output=''.dup, maxwidth=79, newline="\n", &genspace)
    @output = output
    @maxwidth = maxwidth
    @newline = newline
    @genspace = genspace || lambda {|n| ' ' * n}

    @output_width = 0
    @buffer_width = 0
    @buffer = []

    root_group = Group.new(0)
    @group_stack = [root_group]
    @group_queue = GroupQueue.new(root_group)
    @indent = 0
  end

  # The output object.
  #
  # This defaults to '', and should accept the << method
  attr_reader :output

  # The maximum width of a line, before it is separated in to a newline
  #
  # This defaults to 79, and should be an Integer
  attr_reader :maxwidth

  # The value that is appended to +output+ to add a new line.
  #
  # This defaults to "\n", and should be String
  attr_reader :newline

  # A lambda or Proc, that takes one argument, of an Integer, and returns
  # the corresponding number of spaces.
  #
  # By default this is:
  #   lambda {|n| ' ' * n}
  attr_reader :genspace

  # The number of spaces to be indented
  attr_reader :indent

  # The PrettyPrint::GroupQueue of groups in stack to be pretty printed
  attr_reader :group_queue

  # Returns the group most recently added to the stack.
  #
  # Contrived example:
  #   out = ""
  #   => ""
  #   q = PrettyPrint.new(out)
  #   => #<PrettyPrint:0x82f85c0 @output="", @maxwidth=79, @newline="\n", @genspace=#<Proc:0x82f8368@/home/vbatts/.rvm/rubies/ruby-head/lib/ruby/2.0.0/prettyprint.rb:82 (lambda)>, @output_width=0, @buffer_width=0, @buffer=[], @group_stack=[#<PrettyPrint::Group:0x82f8138 @depth=0, @breakables=[], @break=false>], @group_queue=#<PrettyPrint::GroupQueue:0x82fb7c0 @queue=[[#<PrettyPrint::Group:0x82f8138 @depth=0, @breakables=[], @break=false>]]>, @indent=0>
  #   q.group {
  #     q.text q.current_group.inspect
  #     q.text q.newline
  #     q.group(q.current_group.depth + 1) {
  #       q.text q.current_group.inspect
  #       q.text q.newline
  #       q.group(q.current_group.depth + 1) {
  #         q.text q.current_group.inspect
  #         q.text q.newline
  #         q.group(q.current_group.depth + 1) {
  #           q.text q.current_group.inspect
  #           q.text q.newline
  #         }
  #       }
  #     }
  #   }
  #   => 284
  #    puts out
  #   #<PrettyPrint::Group:0x8354758 @depth=1, @breakables=[], @break=false>
  #   #<PrettyPrint::Group:0x8354550 @depth=2, @breakables=[], @break=false>
  #   #<PrettyPrint::Group:0x83541cc @depth=3, @breakables=[], @break=false>
  #   #<PrettyPrint::Group:0x8347e54 @depth=4, @breakables=[], @break=false>
  def current_group
    @group_stack.last
  end

  # Breaks the buffer into lines that are shorter than #maxwidth
  def break_outmost_groups
    while @maxwidth < @output_width + @buffer_width
      return unless group = @group_queue.deq
      until group.breakables.empty?
        data = @buffer.shift
        @output_width = data.output(@output, @output_width)
        @buffer_width -= data.width
      end
      while !@buffer.empty? && Text === @buffer.first
        text = @buffer.shift
        @output_width = text.output(@output, @output_width)
        @buffer_width -= text.width
      end
    end
  end

  # This adds +obj+ as a text of +width+ columns in width.
  #
  # If +width+ is not specified, obj.length is used.
  #
  def text(obj, width=obj.length)
    if @buffer.empty?
      @output << obj
      @output_width += width
    else
      text = @buffer.last
      unless Text === text
        text = Text.new
        @buffer << text
      end
      text.add(obj, width)
      @buffer_width += width
      break_outmost_groups
    end
  end

  # This is similar to #breakable except
  # the decision to break or not is determined individually.
  #
  # Two #fill_breakable under a group may cause 4 results:
  # (break,break), (break,non-break), (non-break,break), (non-break,non-break).
  # This is different to #breakable because two #breakable under a group
  # may cause 2 results:
  # (break,break), (non-break,non-break).
  #
  # The text +sep+ is inserted if a line is not broken at this point.
  #
  # If +sep+ is not specified, " " is used.
  #
  # If +width+ is not specified, +sep.length+ is used. You will have to
  # specify this when +sep+ is a multibyte character, for example.
  #
  def fill_breakable(sep=' ', width=sep.length)
    group { breakable sep, width }
  end

  # This says "you can break a line here if necessary", and a +width+\-column
  # text +sep+ is inserted if a line is not broken at the point.
  #
  # If +sep+ is not specified, " " is used.
  #
  # If +width+ is not specified, +sep.length+ is used. You will have to
  # specify this when +sep+ is a multibyte character, for example.
  #
  def breakable(sep=' ', width=sep.length)
    group = @group_stack.last
    if group.break?
      flush
      @output << @newline
      @output << @genspace.call(@indent)
      @output_width = @indent
      @buffer_width = 0
    else
      @buffer << Breakable.new(sep, width, self)
      @buffer_width += width
      break_outmost_groups
    end
  end

  # Groups line break hints added in the block. The line break hints are all
  # to be used or not.
  #
  # If +indent+ is specified, the method call is regarded as nested by
  # nest(indent) { ... }.
  #
  # If +open_obj+ is specified, <tt>text open_obj, open_width</tt> is called
  # before grouping. If +close_obj+ is specified, <tt>text close_obj,
  # close_width</tt> is called after grouping.
  #
  def group(indent=0, open_obj='', close_obj='', open_width=open_obj.length, close_width=close_obj.length)
    text open_obj, open_width
    group_sub {
      nest(indent) {
        yield
      }
    }
    text close_obj, close_width
  end

  # Takes a block and queues a new group that is indented 1 level further.
  def group_sub
    group = Group.new(@group_stack.last.depth + 1)
    @group_stack.push group
    @group_queue.enq group
    begin
      yield
    ensure
      @group_stack.pop
      if group.breakables.empty?
        @group_queue.delete group
      end
    end
  end

  # Increases left margin after newline with +indent+ for line breaks added in
  # the block.
  #
  def nest(indent)
    @indent += indent
    begin
      yield
    ensure
      @indent -= indent
    end
  end

  # outputs buffered data.
  #
  def flush
    @buffer.each {|data|
      @output_width = data.output(@output, @output_width)
    }
    @buffer.clear
    @buffer_width = 0
  end

  # The Text class is the means by which to collect strings from objects.
  #
  # This class is intended for internal use of the PrettyPrint buffers.
  class Text # :nodoc:

    # Creates a new text object.
    #
    # This constructor takes no arguments.
    #
    # The workflow is to append a PrettyPrint::Text object to the buffer, and
    # being able to call the buffer.last() to reference it.
    #
    # As there are objects, use PrettyPrint::Text#add to include the objects
    # and the width to utilized by the String version of this object.
    def initialize
      @objs = []
      @width = 0
    end

    # The total width of the objects included in this Text object.
    attr_reader :width

    # Render the String text of the objects that have been added to this Text object.
    #
    # Output the text to +out+, and increment the width to +output_width+
    def output(out, output_width)
      @objs.each {|obj| out << obj}
      output_width + @width
    end

    # Include +obj+ in the objects to be pretty printed, and increment
    # this Text object's total width by +width+
    def add(obj, width)
      @objs << obj
      @width += width
    end
  end

  # The Breakable class is used for breaking up object information
  #
  # This class is intended for internal use of the PrettyPrint buffers.
  class Breakable # :nodoc:

    # Create a new Breakable object.
    #
    # Arguments:
    # * +sep+ String of the separator
    # * +width+ Integer width of the +sep+
    # * +q+ parent PrettyPrint object, to base from
    def initialize(sep, width, q)
      @obj = sep
      @width = width
      @pp = q
      @indent = q.indent
      @group = q.current_group
      @group.breakables.push self
    end

    # Holds the separator String
    #
    # The +sep+ argument from ::new
    attr_reader :obj

    # The width of +obj+ / +sep+
    attr_reader :width

    # The number of spaces to indent.
    #
    # This is inferred from +q+ within PrettyPrint, passed in ::new
    attr_reader :indent

    # Render the String text of the objects that have been added to this
    # Breakable object.
    #
    # Output the text to +out+, and increment the width to +output_width+
    def output(out, output_width)
      @group.breakables.shift
      if @group.break?
        out << @pp.newline
        out << @pp.genspace.call(@indent)
        @indent
      else
        @pp.group_queue.delete @group if @group.breakables.empty?
        out << @obj
        output_width + @width
      end
    end
  end

  # The Group class is used for making indentation easier.
  #
  # While this class does neither the breaking into newlines nor indentation,
  # it is used in a stack (as well as a queue) within PrettyPrint, to group
  # objects.
  #
  # For information on using groups, see PrettyPrint#group
  #
  # This class is intended for internal use of the PrettyPrint buffers.
  class Group # :nodoc:
    # Create a Group object
    #
    # Arguments:
    # * +depth+ - this group's relation to previous groups
    def initialize(depth)
      @depth = depth
      @breakables = []
      @break = false
    end

    # This group's relation to previous groups
    attr_reader :depth

    # Array to hold the Breakable objects for this Group
    attr_reader :breakables

    # Makes a break for this Group, and returns true
    def break
      @break = true
    end

    # Boolean of whether this Group has made a break
    def break?
      @break
    end

    # Boolean of whether this Group has been queried for being first
    #
    # This is used as a predicate, and ought to be called first.
    def first?
      if defined? @first
        false
      else
        @first = false
        true
      end
    end
  end

  # The GroupQueue class is used for managing the queue of Group to be pretty
  # printed.
  #
  # This queue groups the Group objects, based on their depth.
  #
  # This class is intended for internal use of the PrettyPrint buffers.
  class GroupQueue # :nodoc:
    # Create a GroupQueue object
    #
    # Arguments:
    # * +groups+ - one or more PrettyPrint::Group objects
    def initialize(*groups)
      @queue = []
      groups.each {|g| enq g}
    end

    # Enqueue +group+
    #
    # This does not strictly append the group to the end of the queue,
    # but instead adds it in line, base on the +group.depth+
    def enq(group)
      depth = group.depth
      @queue << [] until depth < @queue.length
      @queue[depth] << group
    end

    # Returns the outer group of the queue
    def deq
      @queue.each {|gs|
        (gs.length-1).downto(0) {|i|
          unless gs[i].breakables.empty?
            group = gs.slice!(i, 1).first
            group.break
            return group
          end
        }
        gs.each {|group| group.break}
        gs.clear
      }
      return nil
    end

    # Remote +group+ from this queue
    def delete(group)
      @queue[group.depth].delete(group)
    end
  end

  # PrettyPrint::SingleLine is used by PrettyPrint.singleline_format
  #
  # It is passed to be similar to a PrettyPrint object itself, by responding to:
  # * #text
  # * #breakable
  # * #nest
  # * #group
  # * #flush
  # * #first?
  #
  # but instead, the output has no line breaks
  #
  class SingleLine
    # Create a PrettyPrint::SingleLine object
    #
    # Arguments:
    # * +output+ - String (or similar) to store rendered text. Needs to respond to '<<'
    # * +maxwidth+ - Argument position expected to be here for compatibility.
    #                This argument is a noop.
    # * +newline+ - Argument position expected to be here for compatibility.
    #               This argument is a noop.
    def initialize(output, maxwidth=nil, newline=nil)
      @output = output
      @first = [true]
    end

    # Add +obj+ to the text to be output.
    #
    # +width+ argument is here for compatibility. It is a noop argument.
    def text(obj, width=nil)
      @output << obj
    end

    # Appends +sep+ to the text to be output. By default +sep+ is ' '
    #
    # +width+ argument is here for compatibility. It is a noop argument.
    def breakable(sep=' ', width=nil)
      @output << sep
    end

    # Takes +indent+ arg, but does nothing with it.
    #
    # Yields to a block.
    def nest(indent) # :nodoc:
      yield
    end

    # Opens a block for grouping objects to be pretty printed.
    #
    # Arguments:
    # * +indent+ - noop argument. Present for compatibility.
    # * +open_obj+ - text appended before the &blok. Default is ''
    # * +close_obj+ - text appended after the &blok. Default is ''
    # * +open_width+ - noop argument. Present for compatibility.
    # * +close_width+ - noop argument. Present for compatibility.
    def group(indent=nil, open_obj='', close_obj='', open_width=nil, close_width=nil)
      @first.push true
      @output << open_obj
      yield
      @output << close_obj
      @first.pop
    end

    # Method present for compatibility, but is a noop
    def flush # :nodoc:
    end

    # This is used as a predicate, and ought to be called first.
    def first?
      result = @first[-1]
      @first[-1] = false
      result
    end
  end
end
