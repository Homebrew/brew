# frozen_string_literal: true
# typed: false

module T::Private
  module Casts
    def self.cast(value, type, cast_method)
      begin
        coerced_type = T::Utils::Private.coerce_and_check_module_types(type, value, true)
        return value unless coerced_type

        error = coerced_type.error_message_for_obj(value)
        return value unless error

        caller_loc = T.must(caller_locations(2..2)).first

        suffix = "Caller: #{T.must(caller_loc).path}:#{T.must(caller_loc).lineno}"

        raise TypeError.new("#{cast_method}: #{error}\n#{suffix}")
      rescue TypeError => e # raise into rescue to ensure e.backtrace is populated
        T::Configuration.inline_type_error_handler(e, {kind: cast_method, value: value, type: type})
        value
      end
    end

    # there's a lot of shared logic with the above one, but factoring
    # it out like this makes it easier to hopefully one day delete
    # this one
    def self.cast_recursive(value, type, cast_method)
      begin
        error = T::Utils.coerce(type).error_message_for_obj_recursive(value)
        return value unless error

        caller_loc = T.must(caller_locations(2..2)).first

        suffix = "Caller: #{T.must(caller_loc).path}:#{T.must(caller_loc).lineno}"

        raise TypeError.new("#{cast_method}: #{error}\n#{suffix}")
      rescue TypeError => e # raise into rescue to ensure e.backtrace is populated
        T::Configuration.inline_type_error_handler(e, {kind: cast_method, value: value, type: type})
        value
      end
    end
  end
end
