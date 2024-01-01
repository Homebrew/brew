require 'stringio'

module BinData
  # A wrapper around an IO object.  The wrapper provides a consistent
  # interface for BinData objects to use when accessing the IO.
  module IO

    # Common operations for both Read and Write.
    module Common
      def initialize(io)
        if self.class === io
          raise ArgumentError, "io must not be a #{self.class}"
        end

        # wrap strings in a StringIO
        if io.respond_to?(:to_str)
          io = BinData::IO.create_string_io(io.to_str)
        end

        @raw_io = io
        @buffer_end_points = nil

        extend seekable? ? SeekableStream : UnSeekableStream
        stream_init
      end

      #-------------
      private

      def seekable?
        @raw_io.pos
      rescue NoMethodError, Errno::ESPIPE, Errno::EPIPE, Errno::EINVAL
        nil
      end

      def seek(n)
        seek_raw(buffer_limited_n(n))
      end

      def buffer_limited_n(n)
        if @buffer_end_points
          if n.nil? || n > 0
            max = @buffer_end_points[1] - offset
            n = max if n.nil? || n > max
          else
            min = @buffer_end_points[0] - offset
            n = min if n < min
          end
        end

        n
      end

      def with_buffer_common(n)
        prev = @buffer_end_points
        if prev
          avail = prev[1] - offset
          n = avail if n > avail
        end
        @buffer_end_points = [offset, offset + n]
        begin
          yield(*@buffer_end_points)
        ensure
          @buffer_end_points = prev
        end
      end

      # Use #seek and #pos on seekable streams
      module SeekableStream
        # The number of bytes remaining in the input stream.
        def num_bytes_remaining
          start_mark = @raw_io.pos
          @raw_io.seek(0, ::IO::SEEK_END)
          end_mark = @raw_io.pos

          if @buffer_end_points
            if @buffer_end_points[1] < end_mark
              end_mark = @buffer_end_points[1]
            end
          end

          bytes_remaining = end_mark - start_mark
          @raw_io.seek(start_mark, ::IO::SEEK_SET)

          bytes_remaining
        end

        # All io calls in +block+ are rolled back after this
        # method completes.
        def with_readahead
          mark = @raw_io.pos
          begin
            yield
          ensure
            @raw_io.seek(mark, ::IO::SEEK_SET)
          end
        end

        #-----------
        private

        def stream_init
          @initial_pos = @raw_io.pos
        end

        def offset_raw
          @raw_io.pos - @initial_pos
        end

        def seek_raw(n)
          @raw_io.seek(n, ::IO::SEEK_CUR)
        end

        def read_raw(n)
          @raw_io.read(n)
        end

        def write_raw(data)
          @raw_io.write(data)
        end
      end

      # Manually keep track of offset for unseekable streams.
      module UnSeekableStream
        def offset_raw
          @offset
        end

        # The number of bytes remaining in the input stream.
        def num_bytes_remaining
          raise IOError, "stream is unseekable"
        end

        # All io calls in +block+ are rolled back after this
        # method completes.
        def with_readahead
          mark = @offset
          @read_data = ""
          @in_readahead = true

          class << self
            alias_method :read_raw_without_readahead, :read_raw
            alias_method :read_raw, :read_raw_with_readahead
          end

          begin
            yield
          ensure
            @offset = mark
            @in_readahead = false
          end
        end

        #-----------
        private

        def stream_init
          @offset = 0
        end

        def read_raw(n)
          data = @raw_io.read(n)
          @offset += data.size if data
          data
        end

        def read_raw_with_readahead(n)
          data = ""

          unless @read_data.empty? || @in_readahead
            bytes_to_consume = [n, @read_data.length].min
            data += @read_data.slice!(0, bytes_to_consume)
            n -= bytes_to_consume

            if @read_data.empty?
              class << self
                alias_method :read_raw, :read_raw_without_readahead
              end
            end
          end

          raw_data = @raw_io.read(n)
          data += raw_data if raw_data

          if @in_readahead
            @read_data += data
          end

          @offset += data.size

          data
        end

        def write_raw(data)
          @offset += data.size
          @raw_io.write(data)
        end

        def seek_raw(n)
          raise IOError, "stream is unseekable" if n < 0

          # NOTE: how do we seek on a writable stream?

          # skip over data in 8k blocks
          while n > 0
            bytes_to_read = [n, 8192].min
            read_raw(bytes_to_read)
            n -= bytes_to_read
          end
        end
      end
    end

    # Creates a StringIO around +str+.
    def self.create_string_io(str = "")
      s = StringIO.new(str.dup.force_encoding(Encoding::BINARY))
      s.binmode
      s
    end

    # Create a new IO Read wrapper around +io+.  +io+ must provide #read,
    # #pos if reading the current stream position and #seek if setting the
    # current stream position.  If +io+ is a string it will be automatically
    # wrapped in an StringIO object.
    #
    # The IO can handle bitstreams in either big or little endian format.
    #
    #      M  byte1   L      M  byte2   L
    #      S 76543210 S      S fedcba98 S
    #      B          B      B          B
    #
    # In big endian format:
    #   readbits(6), readbits(5) #=> [765432, 10fed]
    #
    # In little endian format:
    #   readbits(6), readbits(5) #=> [543210, a9876]
    #
    class Read
      include Common

      def initialize(io)
        super(io)

        # bits when reading
        @rnbits  = 0
        @rval    = 0
        @rendian = nil
      end

      # Sets a buffer of +n+ bytes on the io stream.  Any reading or seeking
      # calls inside the +block+ will be contained within this buffer.
      def with_buffer(n)
        with_buffer_common(n) do
          yield
          read
        end
      end

      # Returns the current offset of the io stream.  Offset will be rounded
      # up when reading bitfields.
      def offset
        offset_raw
      end

      # Seek +n+ bytes from the current position in the io stream.
      def seekbytes(n)
        reset_read_bits
        seek(n)
      end

      # Reads exactly +n+ bytes from +io+.
      #
      # If the data read is nil an EOFError is raised.
      #
      # If the data read is too short an IOError is raised.
      def readbytes(n)
        reset_read_bits
        read(n)
      end

      # Reads all remaining bytes from the stream.
      def read_all_bytes
        reset_read_bits
        read
      end

      # Reads exactly +nbits+ bits from the stream. +endian+ specifies whether
      # the bits are stored in +:big+ or +:little+ endian format.
      def readbits(nbits, endian)
        if @rendian != endian
          # don't mix bits of differing endian
          reset_read_bits
          @rendian = endian
        end

        if endian == :big
          read_big_endian_bits(nbits)
        else
          read_little_endian_bits(nbits)
        end
      end

      # Discards any read bits so the stream becomes aligned at the
      # next byte boundary.
      def reset_read_bits
        @rnbits = 0
        @rval   = 0
      end

      #---------------
      private

      def read(n = nil)
        str = read_raw(buffer_limited_n(n))
        if n
          raise EOFError, "End of file reached" if str.nil?
          raise IOError, "data truncated" if str.size < n
        end
        str
      end

      def read_big_endian_bits(nbits)
        while @rnbits < nbits
          accumulate_big_endian_bits
        end

        val     = (@rval >> (@rnbits - nbits)) & mask(nbits)
        @rnbits -= nbits
        @rval   &= mask(@rnbits)

        val
      end

      def accumulate_big_endian_bits
        byte = read(1).unpack('C').at(0) & 0xff
        @rval = (@rval << 8) | byte
        @rnbits += 8
      end

      def read_little_endian_bits(nbits)
        while @rnbits < nbits
          accumulate_little_endian_bits
        end

        val     = @rval & mask(nbits)
        @rnbits -= nbits
        @rval   >>= nbits

        val
      end

      def accumulate_little_endian_bits
        byte = read(1).unpack('C').at(0) & 0xff
        @rval = @rval | (byte << @rnbits)
        @rnbits += 8
      end

      def mask(nbits)
        (1 << nbits) - 1
      end
    end

    # Create a new IO Write wrapper around +io+.  +io+ must provide #write.
    # If +io+ is a string it will be automatically wrapped in an StringIO
    # object.
    #
    # The IO can handle bitstreams in either big or little endian format.
    #
    # See IO::Read for more information.
    class Write
      include Common
      def initialize(io)
        super(io)

        @wnbits  = 0
        @wval    = 0
        @wendian = nil
      end

      # Sets a buffer of +n+ bytes on the io stream.  Any writes inside the
      # +block+ will be contained within this buffer.  If less than +n+ bytes
      # are written inside the block, the remainder will be padded with '\0'
      # bytes.
      def with_buffer(n)
        with_buffer_common(n) do |_buf_start, buf_end|
          yield
          write("\0" * (buf_end - offset))
        end
      end

      # Returns the current offset of the io stream.  Offset will be rounded
      # up when writing bitfields.
      def offset
        offset_raw + (@wnbits > 0 ? 1 : 0)
      end

      # Seek +n+ bytes from the current position in the io stream.
      def seekbytes(n)
        flushbits
        seek(n)
      end

      # Writes the given string of bytes to the io stream.
      def writebytes(str)
        flushbits
        write(str)
      end

      # Writes +nbits+ bits from +val+ to the stream. +endian+ specifies whether
      # the bits are to be stored in +:big+ or +:little+ endian format.
      def writebits(val, nbits, endian)
        if @wendian != endian
          # don't mix bits of differing endian
          flushbits
          @wendian = endian
        end

        clamped_val = val & mask(nbits)

        if endian == :big
          write_big_endian_bits(clamped_val, nbits)
        else
          write_little_endian_bits(clamped_val, nbits)
        end
      end

      # To be called after all +writebits+ have been applied.
      def flushbits
        raise "Internal state error nbits = #{@wnbits}" if @wnbits >= 8

        if @wnbits > 0
          writebits(0, 8 - @wnbits, @wendian)
        end
      end
      alias flush flushbits

      #---------------
      private

      def write(data)
        n = buffer_limited_n(data.size)
        if n < data.size
          data = data[0, n]
        end

        write_raw(data)
      end

      def write_big_endian_bits(val, nbits)
        while nbits > 0
          bits_req = 8 - @wnbits
          if nbits >= bits_req
            msb_bits = (val >> (nbits - bits_req)) & mask(bits_req)
            nbits -= bits_req
            val &= mask(nbits)

            @wval   = (@wval << bits_req) | msb_bits
            write(@wval.chr)

            @wval   = 0
            @wnbits = 0
          else
            @wval = (@wval << nbits) | val
            @wnbits += nbits
            nbits = 0
          end
        end
      end

      def write_little_endian_bits(val, nbits)
        while nbits > 0
          bits_req = 8 - @wnbits
          if nbits >= bits_req
            lsb_bits = val & mask(bits_req)
            nbits -= bits_req
            val >>= bits_req

            @wval   = @wval | (lsb_bits << @wnbits)
            write(@wval.chr)

            @wval   = 0
            @wnbits = 0
          else
            @wval   = @wval | (val << @wnbits)
            @wnbits += nbits
            nbits = 0
          end
        end
      end

      def mask(nbits)
        (1 << nbits) - 1
      end
    end
  end
end
