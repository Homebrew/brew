# frozen_string_literal: true
# typed: true

module T::Private
  module Casts
    def self.cast(value, type, cast_method)
      begin
        # Every caller (T.cast/let/bind/assert_type! in _types.rb) inlines the
        # value check for the two dominant shapes -- a Module literal and the
        # SimplePairUnion that `T.nilable(SomeModule)` produces -- and only
        # falls through to here when that check already failed. So skip
        # straight to coercing: re-checking `value.is_a?(type)` /
        # `type.valid?(value)` here would always be false.
        case type
        when ::Module
          coerced_type = T::Types::Simple::Private::Pool.type_for_module(type)
        when T::Types::Base
          # Mirrors the T::Types::Base branch of coerce_and_check_module_types,
          # kept inline to avoid its call frame for every already-coerced type.
          coerced_type =
            case type
            when T::Private::Types::TypeAlias
              type.aliased_type
            else
              type
            end
        else
          coerced_type = T::Utils::Private.coerce_and_check_module_types(type, value, true)
          return value unless coerced_type
        end

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
