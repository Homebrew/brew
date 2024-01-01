module BinData
  # WARNING: THIS IS UNSUPPORTED!!
  #
  # This was a (failed) experimental feature that allowed seeking within the
  # input stream.  It remains here for backwards compatability for the few
  # people that used it.
  #
  # The official way to skip around the stream is to use BinData::Skip with
  # the `:to_abs_offset` parameter.
  #
  # == Parameters
  #
  # Parameters may be provided at initialisation to control the behaviour of
  # an object.  These parameters are:
  #
  # [<tt>:check_offset</tt>]  Raise an error if the current IO offset doesn't
  #                           meet this criteria.  A boolean return indicates
  #                           success or failure.  Any other return is compared
  #                           to the current offset.  The variable +offset+
  #                           is made available to any lambda assigned to
  #                           this parameter.  This parameter is only checked
  #                           before reading.
  # [<tt>:adjust_offset</tt>] Ensures that the current IO offset is at this
  #                           position before reading.  This is like
  #                           <tt>:check_offset</tt>, except that it will
  #                           adjust the IO offset instead of raising an error.
  module CheckOrAdjustOffsetPlugin

    def self.included(base) #:nodoc:
      base.optional_parameters :check_offset, :adjust_offset
      base.mutually_exclusive_parameters :check_offset, :adjust_offset
    end

    def initialize_shared_instance
      extend CheckOffsetMixin  if has_parameter?(:check_offset)
      extend AdjustOffsetMixin if has_parameter?(:adjust_offset)
      super
    end

    module CheckOffsetMixin
      def do_read(io) #:nodoc:
        check_offset(io)
        super(io)
      end

      #---------------
      private

      def check_offset(io)
        actual_offset = io.offset
        expected = eval_parameter(:check_offset, offset: actual_offset)

        if !expected
          raise ValidityError, "offset not as expected for #{debug_name}"
        elsif actual_offset != expected && expected != true
          raise ValidityError,
                "offset is '#{actual_offset}' but " +
                "expected '#{expected}' for #{debug_name}"
        end
      end
    end

    module AdjustOffsetMixin
      def do_read(io) #:nodoc:
        adjust_offset(io)
        super(io)
      end

      #---------------
      private

      def adjust_offset(io)
        actual_offset = io.offset
        expected = eval_parameter(:adjust_offset)
        if actual_offset != expected
          begin
            seek = expected - actual_offset
            io.seekbytes(seek)
            warn "adjusting stream position by #{seek} bytes" if $VERBOSE
          rescue
            raise ValidityError,
                  "offset is '#{actual_offset}' but couldn't seek to " +
                  "expected '#{expected}' for #{debug_name}"
          end
        end
      end
    end
  end

  # Add these offset options to Base
  class Base
    include CheckOrAdjustOffsetPlugin
  end
end
