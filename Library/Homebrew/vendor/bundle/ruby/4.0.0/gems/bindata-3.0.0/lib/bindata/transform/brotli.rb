require 'brotli'

module BinData
  module Transform
    # Transforms a brotli compressed data stream.
    #
    #     gem install brotli
    class Brotli < BinData::IO::Transform
      transform_changes_stream_length!

      def initialize(read_length)
        super()
        @length = read_length
      end

      def read(n)
        @read ||= ::Brotli::inflate(chain_read(@length))
        @read.slice!(0...n)
      end

      def write(data)
        @write ||= create_empty_binary_string
        @write << data
      end

      def after_read_transform
        raise IOError, "didn't read all data" unless @read.empty?
      end

      def after_write_transform
        chain_write(::Brotli::deflate(@write))
      end
    end
  end
end
