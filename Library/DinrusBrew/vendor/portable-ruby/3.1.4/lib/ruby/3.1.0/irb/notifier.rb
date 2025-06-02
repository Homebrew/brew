# frozen_string_literal: false
#
#   notifier.rb - output methods used by irb
#   	$Release Version: 0.9.6$
#   	$Revision$
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#
# --
#
#
#

require_relative "output-method"

module IRB
  # An output formatter used internally by the lexer.
  module Notifier
    class ErrUndefinedNotifier < StandardError
      def initialize(val)
        super("undefined notifier level: #{val} is specified")
      end
    end
    class ErrUnrecognizedLevel < StandardError
      def initialize(val)
        super("unrecognized notifier level: #{val} is specified")
      end
    end

    # Define a new Notifier output source, returning a new CompositeNotifier
    # with the given +prefix+ and +output_method+.
    #
    # The optional +prefix+ will be appended to all objects being inspected
    # during output, using the given +output_method+ as the output source. If
    # no +output_method+ is given, StdioOutputMethod will be used, and all
    # expressions will be sent directly to STDOUT without any additional
    # formatting.
    def def_notifier(prefix = "", output_method = StdioOutputMethod.new)
      CompositeNotifier.new(prefix, output_method)
    end
    module_function :def_notifier

    # An abstract class, or superclass, for CompositeNotifier and
    # LeveledNotifier to inherit. It provides several wrapper methods for the
    # OutputMethod object used by the Notifier.
    class AbstractNotifier
      # Creates a new Notifier object
      def initialize(prefix, base_notifier)
        @prefix = prefix
        @base_notifier = base_notifier
      end

      # The +prefix+ for this Notifier, which is appended to all objects being
      # inspected during output.
      attr_reader :prefix

      # A wrapper method used to determine whether notifications are enabled.
      #
      # Defaults to +true+.
      def notify?
        true
      end

      # See OutputMethod#print for more detail.
      def print(*opts)
        @base_notifier.print prefix, *opts if notify?
      end

      # See OutputMethod#printn for more detail.
      def printn(*opts)
        @base_notifier.printn prefix, *opts if notify?
      end

      # See OutputMethod#printf for more detail.
      def printf(format, *opts)
        @base_notifier.printf(prefix + format, *opts) if notify?
      end

      # See OutputMethod#puts for more detail.
      def puts(*objs)
        if notify?
          @base_notifier.puts(*objs.collect{|obj| prefix + obj.to_s})
        end
      end

      # Same as #ppx, except it uses the #prefix given during object
      # initialization.
      # See OutputMethod#ppx for more detail.
      def pp(*objs)
        if notify?
          @base_notifier.ppx @prefix, *objs
        end
      end

      # Same as #pp, except it concatenates the given +prefix+ with the #prefix
      # given during object initialization.
      #
      # See OutputMethod#ppx for more detail.
      def ppx(prefix, *objs)
        if notify?
          @base_notifier.ppx @prefix+prefix, *objs
        end
      end

      # Execute the given block if notifications are enabled.
      def exec_if
        yield(@base_notifier) if notify?
      end
    end

    # A class that can be used to create a group of notifier objects with the
    # intent of representing a leveled notification system for irb.
    #
    # This class will allow you to generate other notifiers, and assign them
    # the appropriate level for output.
    #
    # The Notifier class provides a class-method Notifier.def_notifier to
    # create a new composite notifier. Using the first composite notifier
    # object you create, sibling notifiers can be initialized with
    # #def_notifier.
    class CompositeNotifier < AbstractNotifier
      # Create a new composite notifier object with the given +prefix+, and
      # +base_notifier+ to use for output.
      def initialize(prefix, base_notifier)
        super

        @notifiers = [D_NOMSG]
        @level_notifier = D_NOMSG
      end

      # List of notifiers in the group
      attr_reader :notifiers

      # Creates a new LeveledNotifier in the composite #notifiers group.
      #
      # The given +prefix+ will be assigned to the notifier, and +level+ will
      # be used as the index of the #notifiers Array.
      #
      # This method returns the newly created instance.
      def def_notifier(level, prefix = "")
        notifier = LeveledNotifier.new(self, level, prefix)
        @notifiers[level] = notifier
        notifier
      end

      # Returns the leveled notifier for this object
      attr_reader :level_notifier
      alias level level_notifier

      # Sets the leveled notifier for this object.
      #
      # When the given +value+ is an instance of AbstractNotifier,
      # #level_notifier is set to the given object.
      #
      # When an Integer is given, #level_notifier is set to the notifier at the
      # index +value+ in the #notifiers Array.
      #
      # If no notifier exists at the index +value+ in the #notifiers Array, an
      # ErrUndefinedNotifier exception is raised.
      #
      # An ErrUnrecognizedLevel exception is raised if the given +value+ is not
      # found in the existing #notifiers Array, or an instance of
      # AbstractNotifier
      def level_notifier=(value)
        case value
        when AbstractNotifier
          @level_notifier = value
        when Integer
          l = @notifiers[value]
          raise ErrUndefinedNotifier, value unless l
          @level_notifier = l
        else
          raise ErrUnrecognizedLevel, value unless l
        end
      end

      alias level= level_notifier=
    end

    # A leveled notifier is comparable to the composite group from
    # CompositeNotifier#notifiers.
    class LeveledNotifier < AbstractNotifier
      include Comparable

      # Create a new leveled notifier with the given +base+, and +prefix+ to
      # send to AbstractNotifier.new
      #
      # The given +level+ is used to compare other leveled notifiers in the
      # CompositeNotifier group to determine whether or not to output
      # notifications.
      def initialize(base, level, prefix)
        super(prefix, base)

        @level = level
      end

      # The current level of this notifier object
      attr_reader :level

      # Compares the level of this notifier object with the given +other+
      # notifier.
      #
      # See the Comparable module for more information.
      def <=>(other)
        @level <=> other.level
      end

      # Whether to output messages to the output method, depending on the level
      # of this notifier object.
      def notify?
        @base_notifier.level >= self
      end
    end

    # NoMsgNotifier is a LeveledNotifier that's used as the default notifier
    # when creating a new CompositeNotifier.
    #
    # This notifier is used as the +zero+ index, or level +0+, for
    # CompositeNotifier#notifiers, and will not output messages of any sort.
    class NoMsgNotifier < LeveledNotifier
      # Creates a new notifier that should not be used to output messages.
      def initialize
        @base_notifier = nil
        @level = 0
        @prefix = ""
      end

      # Ensures notifications are ignored, see AbstractNotifier#notify? for
      # more information.
      def notify?
        false
      end
    end

    D_NOMSG = NoMsgNotifier.new # :nodoc:
  end
end
