# frozen_string_literal: true

require "date"

Google::Protobuf::Timestamp.class_eval do
  def to_time
    Time.at(seconds, nanos, :nanosecond, in: 0)
  end

  def self.from_time(time)
    new.from_time(time)
  end

  def from_time(time)
    self.seconds = time.to_i
    self.nanos = time.nsec
    self
  end

  def to_i
    seconds
  end

  def to_f
    seconds + nanos.quo(1_000_000_000)
  end

  def self.decode_json_hash(json, registry:, ignore_unknown_fields: false)
    return Protobug::UNSET if json.nil?
    raise Protobug::DecodeError, "expected string for #{full_name}, got #{json.inspect}" unless json.is_a? String

    if /t|z/.match?(json)
      raise Protobug::DecodeError, "json timestamp string has incorrect capitalization: #{json.inspect}"
    elsif !json.include?("T")
      raise Protobug::DecodeError, "json timestamp string missing T: #{json.inspect}"
    end

    begin
      time = DateTime.rfc3339(json, Date::GREGORIAN).to_time
    rescue Date::Error => e
      raise Protobug::DecodeError, "json timestamp string invalid: #{json.inspect} (#{e})"
    end
    validate_json_range(Protobug::DecodeError, time)
    json = {
      "seconds" => time.to_i,
      "nanos" => time.nsec
    }
    super
  end

  def as_json(print_unknown_fields: false) # rubocop:disable Lint/UnusedMethodArgument
    time = Time.at(seconds, nanos, :nanosecond, in: 0)
    self.class.validate_json_range(Protobug::EncodeError, time)

    nanosecs = time.nsec

    if nanosecs > 0
      nanosecs = nanosecs.to_s.rjust(9, "0")
      nil while nanosecs.delete_suffix!("000")
      digits = nanosecs.size
      format = "%FT%H:%M:%S.%#{digits}NZ"
    else
      format = "%FT%H:%M:%SZ"
    end

    time.strftime(format)
  end

  def self.validate_json_range(err, time)
    raise err, "time value too large #{time.inspect}" if time.year > 9999
    raise err, "time value too small #{time.inspect}" if time.year <= 0
  end
end
