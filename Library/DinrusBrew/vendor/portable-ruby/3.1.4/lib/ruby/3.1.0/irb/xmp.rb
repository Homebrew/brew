# frozen_string_literal: false
#
#   xmp.rb - irb version of gotoken xmp
#   	$Release Version: 0.9$
#   	$Revision$
#   	by Keiju ISHITSUKA(Nippon Rational Inc.)
#
# --
#
#
#

require_relative "../irb"
require_relative "frame"

# An example printer for irb.
#
# It's much like the standard library PrettyPrint, that shows the value of each
# expression as it runs.
#
# In order to use this library, you must first require it:
#
#     require 'irb/xmp'
#
# Now, you can take advantage of the Object#xmp convenience method.
#
#     xmp <<END
#       foo = "bar"
#       baz = 42
#     END
#     #=> foo = "bar"
#       #==>"bar"
#     #=> baz = 42
#       #==>42
#
# You can also create an XMP object, with an optional binding to print
# expressions in the given binding:
#
#     ctx = binding
#     x = XMP.new ctx
#     x.puts
#     #=> today = "a good day"
#       #==>"a good day"
#     ctx.eval 'today # is what?'
#     #=> "a good day"
class XMP

  # Creates a new XMP object.
  #
  # The top-level binding or, optional +bind+ parameter will be used when
  # creating the workspace. See WorkSpace.new for more information.
  #
  # This uses the +:XMP+ prompt mode, see IRB@Customizing+the+IRB+Prompt for
  # full detail.
  def initialize(bind = nil)
    IRB.init_config(nil)

    IRB.conf[:PROMPT_MODE] = :XMP

    bind = IRB::Frame.top(1) unless bind
    ws = IRB::WorkSpace.new(bind)
    @io = StringInputMethod.new
    @irb = IRB::Irb.new(ws, @io)
    @irb.context.ignore_sigint = false

    IRB.conf[:MAIN_CONTEXT] = @irb.context
  end

  # Evaluates the given +exps+, for example:
  #
  #   require 'irb/xmp'
  #   x = XMP.new
  #
  #   x.puts '{:a => 1, :b => 2, :c => 3}'
  #   #=> {:a => 1, :b => 2, :c => 3}
  #     # ==>{:a=>1, :b=>2, :c=>3}
  #   x.puts 'foo = "bar"'
  #   # => foo = "bar"
  #     # ==>"bar"
  def puts(exps)
    @io.puts exps

    if @irb.context.ignore_sigint
      begin
        trap_proc_b = trap("SIGINT"){@irb.signal_handle}
        catch(:IRB_EXIT) do
          @irb.eval_input
        end
      ensure
        trap("SIGINT", trap_proc_b)
      end
    else
      catch(:IRB_EXIT) do
        @irb.eval_input
      end
    end
  end

  # A custom InputMethod class used by XMP for evaluating string io.
  class StringInputMethod < IRB::InputMethod
    # Creates a new StringInputMethod object
    def initialize
      super
      @exps = []
    end

    # Whether there are any expressions left in this printer.
    def eof?
      @exps.empty?
    end

    # Reads the next expression from this printer.
    #
    # See IO#gets for more information.
    def gets
      while l = @exps.shift
        next if /^\s+$/ =~ l
        l.concat "\n"
        print @prompt, l
        break
      end
      l
    end

    # Concatenates all expressions in this printer, separated by newlines.
    #
    # An Encoding::CompatibilityError is raised of the given +exps+'s encoding
    # doesn't match the previous expression evaluated.
    def puts(exps)
      if @encoding and exps.encoding != @encoding
        enc = Encoding.compatible?(@exps.join("\n"), exps)
        if enc.nil?
          raise Encoding::CompatibilityError, "Encoding in which the passed expression is encoded is not compatible to the preceding's one"
        else
          @encoding = enc
        end
      else
        @encoding = exps.encoding
      end
      @exps.concat exps.split(/\n/)
    end

    # Returns the encoding of last expression printed by #puts.
    attr_reader :encoding
  end
end

# A convenience method that's only available when the you require the IRB::XMP standard library.
#
# Creates a new XMP object, using the given expressions as the +exps+
# parameter, and optional binding as +bind+ or uses the top-level binding. Then
# evaluates the given expressions using the +:XMP+ prompt mode.
#
# For example:
#
#   require 'irb/xmp'
#   ctx = binding
#   xmp 'foo = "bar"', ctx
#   #=> foo = "bar"
#     #==>"bar"
#   ctx.eval 'foo'
#   #=> "bar"
#
# See XMP.new for more information.
def xmp(exps, bind = nil)
  bind = IRB::Frame.top(1) unless bind
  xmp = XMP.new(bind)
  xmp.puts exps
  xmp
end
