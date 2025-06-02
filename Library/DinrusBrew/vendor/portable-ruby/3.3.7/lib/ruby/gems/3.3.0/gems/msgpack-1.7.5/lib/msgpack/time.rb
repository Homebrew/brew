# frozen_string_literal: true

# MessagePack extention packer and unpacker for built-in Time class
module MessagePack
  module Time
    # 3-arg Time.at is available Ruby >= 2.5
    TIME_AT_3_AVAILABLE = begin
                            !!::Time.at(0, 0, :nanosecond)
                          rescue ArgumentError
                            false
                          end

    Unpacker = if TIME_AT_3_AVAILABLE
                 lambda do |payload|
                   tv = MessagePack::Timestamp.from_msgpack_ext(payload)
                   ::Time.at(tv.sec, tv.nsec, :nanosecond)
                 end
               else
                 lambda do |payload|
                   tv = MessagePack::Timestamp.from_msgpack_ext(payload)
                   ::Time.at(tv.sec, tv.nsec / 1000.0r)
                 end
               end

    Packer = lambda { |time|
      MessagePack::Timestamp.to_msgpack_ext(time.tv_sec, time.tv_nsec)
    }
  end
end
