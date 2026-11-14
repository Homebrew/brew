# frozen_string_literal: true

Google::Protobuf::Duration.class_eval do
  # Returns the number of seconds represented by this Duration
  def to_f
    seconds + (nanos.to_f / 1_000_000_000)
  end

  def self.decode_json_hash(json, registry:, ignore_unknown_fields: false)
    return Protobug::UNSET if json.nil?
    raise Protobug::DecodeError, "expected string for #{full_name}, got #{json.inspect}" unless json.is_a? String

    unless /\A(-)?(\d+)(?:\.(\d+))?s\z/ =~ json
      raise Protobug::DecodeError, "expected string for #{full_name}, got #{json.inspect}"
    end

    sign = Regexp.last_match(1) ? -1 : 1
    seconds = Regexp.last_match(2).to_i
    nanos = Regexp.last_match(3)&.ljust(9, "0").to_i
    validate_json_range(Protobug::DecodeError, seconds, nanos)
    json = {
      "seconds" => sign * seconds,
      "nanos" => sign * nanos
    }
    super
  end

  def as_json(print_unknown_fields: false) # rubocop:disable Lint/UnusedMethodArgument
    seconds = self.seconds
    nanos = self.nanos

    self.class.validate_json_range(Protobug::EncodeError, seconds, nanos)

    sign = seconds < 0 ? "-" : ""
    sign = "-" if seconds == 0 && nanos < 0
    seconds = seconds.abs
    nanos = nanos.abs
    if nanos.nonzero?
      nanos_s = ".#{nanos.to_s.rjust(9, "0")}"
      nil while nanos_s.delete_suffix!("000")
    end
    "#{sign}#{seconds}#{nanos_s}s"
  end

  def self.validate_json_range(err, seconds, nanos)
    if seconds != 0 && nanos != 0 && ((seconds < 0) ^ (nanos < 0))
      raise err,
            "seconds and nanos must have the same sign"
    end

    raise err, "seconds out of range for json duration" if seconds < -315_576_000_000 || seconds > +315_576_000_000
  end
end
