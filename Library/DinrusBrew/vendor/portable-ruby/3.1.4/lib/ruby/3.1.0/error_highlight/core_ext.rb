require_relative "formatter"

module ErrorHighlight
  module CoreExt
    # This is a marker to let `DidYouMean::Correctable#original_message` skip
    # the following method definition of `to_s`.
    # See https://github.com/ruby/did_you_mean/pull/152
    SKIP_TO_S_FOR_SUPER_LOOKUP = true
    private_constant :SKIP_TO_S_FOR_SUPER_LOOKUP

    def to_s
      msg = super.dup

      locs = backtrace_locations
      return msg unless locs

      loc = locs.first
      begin
        node = RubyVM::AbstractSyntaxTree.of(loc, keep_script_lines: true)
        opts = {}

        case self
        when NoMethodError, NameError
          opts[:point_type] = :name
          opts[:name] = name
        when TypeError, ArgumentError
          opts[:point_type] = :args
        end

        spot = ErrorHighlight.spot(node, **opts)

      rescue SyntaxError
      rescue SystemCallError # file not found or something
      rescue ArgumentError   # eval'ed code
      end

      if spot
        points = ErrorHighlight.formatter.message_for(spot)
        msg << points if !msg.include?(points)
      end

      msg
    end
  end

  NameError.prepend(CoreExt)

  # The extension for TypeError/ArgumentError is temporarily disabled due to many test failures

  #TypeError.prepend(CoreExt)
  #ArgumentError.prepend(CoreExt)
end
