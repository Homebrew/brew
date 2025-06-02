module BinData
  module Transform
    # Transforms the data stream by xoring each byte.
    class Xor < BinData::IO::Transform
      def initialize(xor)
        super()
        @xor = xor
      end

      def read(n)
        chain_read(n).bytes.map { |byte| (byte ^ @xor).chr }.join
      end

      def write(data)
        chain_write(data.bytes.map { |byte| (byte ^ @xor).chr }.join)
      end
    end
  end
end
