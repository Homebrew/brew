# frozen_string_literal: true
module Psych
  ###
  # Psych::Handler is an abstract base class that defines the events used
  # when dealing with Psych::Parser.  Clients who want to use Psych::Parser
  # should implement a class that inherits from Psych::Handler and define
  # events that they can handle.
  #
  # Psych::Handler defines all events that Psych::Parser can possibly send to
  # event handlers.
  #
  # See Psych::Parser for more details
  class Handler
    ###
    # Configuration options for dumping YAML.
    class DumperOptions
      attr_accessor :line_width, :indentation, :canonical

      def initialize
        @line_width  = 0
        @indentation = 2
        @canonical   = false
      end
    end

    # Default dumping options
    OPTIONS = DumperOptions.new

    # Events that a Handler should respond to.
    EVENTS = [ :alias,
               :empty,
               :end_document,
               :end_mapping,
               :end_sequence,
               :end_stream,
               :scalar,
               :start_document,
               :start_mapping,
               :start_sequence,
               :start_stream ]

    ###
    # Called with +encoding+ when the YAML stream starts.  This method is
    # called once per stream.  A stream may contain multiple documents.
    #
    # See the constants in Psych::Parser for the possible values of +encoding+.
    def start_stream encoding
    end

    ###
    # Called when the document starts with the declared +version+,
    # +tag_directives+, if the document is +implicit+.
    #
    # +version+ will be an array of integers indicating the YAML version being
    # dealt with, +tag_directives+ is a list of tuples indicating the prefix
    # and suffix of each tag, and +implicit+ is a boolean indicating whether
    # the document is started implicitly.
    #
    # === Example
    #
    # Given the following YAML:
    #
    #   %YAML 1.1
    #   %TAG ! tag:tenderlovemaking.com,2009:
    #   --- !squee
    #
    # The parameters for start_document must be this:
    #
    #   version         # => [1, 1]
    #   tag_directives  # => [["!", "tag:tenderlovemaking.com,2009:"]]
    #   implicit        # => false
    def start_document version, tag_directives, implicit
    end

    ###
    # Called with the document ends.  +implicit+ is a boolean value indicating
    # whether or not the document has an implicit ending.
    #
    # === Example
    #
    # Given the following YAML:
    #
    #   ---
    #     hello world
    #
    # +implicit+ will be true.  Given this YAML:
    #
    #   ---
    #     hello world
    #   ...
    #
    # +implicit+ will be false.
    def end_document implicit
    end

    ###
    # Called when an alias is found to +anchor+.  +anchor+ will be the name
    # of the anchor found.
    #
    # === Example
    #
    # Here we have an example of an array that references itself in YAML:
    #
    #   --- &ponies
    #   - first element
    #   - *ponies
    #
    # &ponies is the anchor, *ponies is the alias.  In this case, alias is
    # called with "ponies".
    def alias anchor
    end

    ###
    # Called when a scalar +value+ is found.  The scalar may have an
    # +anchor+, a +tag+, be implicitly +plain+ or implicitly +quoted+
    #
    # +value+ is the string value of the scalar
    # +anchor+ is an associated anchor or nil
    # +tag+ is an associated tag or nil
    # +plain+ is a boolean value
    # +quoted+ is a boolean value
    # +style+ is an integer indicating the string style
    #
    # See the constants in Psych::Nodes::Scalar for the possible values of
    # +style+
    #
    # === Example
    #
    # Here is a YAML document that exercises most of the possible ways this
    # method can be called:
    #
    #   ---
    #   - !str "foo"
    #   - &anchor fun
    #   - many
    #     lines
    #   - |
    #     many
    #     newlines
    #
    # The above YAML document contains a list with four strings.  Here are
    # the parameters sent to this method in the same order:
    #
    #   # value               anchor    tag     plain   quoted  style
    #   ["foo",               nil,      "!str", false,  false,  3    ]
    #   ["fun",               "anchor", nil,    true,   false,  1    ]
    #   ["many lines",        nil,      nil,    true,   false,  1    ]
    #   ["many\nnewlines\n",  nil,      nil,    false,  true,   4    ]
    #
    def scalar value, anchor, tag, plain, quoted, style
    end

    ###
    # Called when a sequence is started.
    #
    # +anchor+ is the anchor associated with the sequence or nil.
    # +tag+ is the tag associated with the sequence or nil.
    # +implicit+ a boolean indicating whether or not the sequence was implicitly
    # started.
    # +style+ is an integer indicating the list style.
    #
    # See the constants in Psych::Nodes::Sequence for the possible values of
    # +style+.
    #
    # === Example
    #
    # Here is a YAML document that exercises most of the possible ways this
    # method can be called:
    #
    #   ---
    #   - !!seq [
    #     a
    #   ]
    #   - &pewpew
    #     - b
    #
    # The above YAML document consists of three lists, an outer list that
    # contains two inner lists.  Here is a matrix of the parameters sent
    # to represent these lists:
    #
    #   # anchor    tag                       implicit  style
    #   [nil,       nil,                      true,     1     ]
    #   [nil,       "tag:yaml.org,2002:seq",  false,    2     ]
    #   ["pewpew",  nil,                      true,     1     ]

    def start_sequence anchor, tag, implicit, style
    end

    ###
    # Called when a sequence ends.
    def end_sequence
    end

    ###
    # Called when a map starts.
    #
    # +anchor+ is the anchor associated with the map or +nil+.
    # +tag+ is the tag associated with the map or +nil+.
    # +implicit+ is a boolean indicating whether or not the map was implicitly
    # started.
    # +style+ is an integer indicating the mapping style.
    #
    # See the constants in Psych::Nodes::Mapping for the possible values of
    # +style+.
    #
    # === Example
    #
    # Here is a YAML document that exercises most of the possible ways this
    # method can be called:
    #
    #   ---
    #   k: !!map { hello: world }
    #   v: &pewpew
    #     hello: world
    #
    # The above YAML document consists of three maps, an outer map that contains
    # two inner maps.  Below is a matrix of the parameters sent in order to
    # represent these three maps:
    #
    #   # anchor    tag                       implicit  style
    #   [nil,       nil,                      true,     1     ]
    #   [nil,       "tag:yaml.org,2002:map",  false,    2     ]
    #   ["pewpew",  nil,                      true,     1     ]

    def start_mapping anchor, tag, implicit, style
    end

    ###
    # Called when a map ends
    def end_mapping
    end

    ###
    # Called when an empty event happens. (Which, as far as I can tell, is
    # never).
    def empty
    end

    ###
    # Called when the YAML stream ends
    def end_stream
    end

    ###
    # Called before each event with line/column information.
    def event_location(start_line, start_column, end_line, end_column)
    end

    ###
    # Is this handler a streaming handler?
    def streaming?
      false
    end
  end
end
