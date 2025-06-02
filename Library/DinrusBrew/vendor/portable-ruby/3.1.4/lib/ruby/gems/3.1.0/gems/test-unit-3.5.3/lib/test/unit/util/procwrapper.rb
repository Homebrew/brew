#--
#
# Author:: Nathaniel Talbott.
# Copyright:: Copyright (c) 2000-2002 Nathaniel Talbott. All rights reserved.
# License:: Ruby license.

module Test
  module Unit
    module Util

      # Allows the storage of a Proc passed through '&' in a
      # hash.
      #
      # Note: this may be inefficient, since the hash being
      # used is not necessarily very good. In Observable,
      # efficiency is not too important, since the hash is
      # only accessed when adding and removing listeners,
      # not when notifying.

      class ProcWrapper

        # Creates a new wrapper for a_proc.
        def initialize(a_proc)
          @a_proc = a_proc
          @hash = a_proc.inspect.sub(/^(#<#{a_proc.class}:)/){''}.sub(/(>)$/){''}.hex
        end

        def hash
          return @hash
        end

        def ==(other)
          case(other)
          when ProcWrapper
            return @a_proc == other.to_proc
          else
            return super
          end
        end
        alias :eql? :==

        def to_proc
          return @a_proc
        end
      end
    end
  end
end
