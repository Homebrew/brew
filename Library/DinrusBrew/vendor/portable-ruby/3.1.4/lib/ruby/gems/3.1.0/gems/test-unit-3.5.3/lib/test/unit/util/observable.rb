#--
#
# Author:: Nathaniel Talbott.
# Copyright:: Copyright (c) 2000-2002 Nathaniel Talbott. All rights reserved.
# License:: Ruby license.

require 'test/unit/util/procwrapper'

module Test
  module Unit
    module Util

      # This is a utility class that allows anything mixing
      # it in to notify a set of listeners about interesting
      # events.
      module Observable
        # We use this for defaults since nil might mean something
        NOTHING = "NOTHING/#{__id__}"

        # Adds the passed proc as a listener on the
        # channel indicated by channel_name. listener_key
        # is used to remove the listener later; if none is
        # specified, the proc itself is used.
        #
        # Whatever is used as the listener_key is
        # returned, making it very easy to use the proc
        # itself as the listener_key:
        #
        #     listener = add_listener("Channel") { ... }
        #     remove_listener("Channel", listener)
        def add_listener(channel_name, listener_key=NOTHING, &listener) # :yields: value
          unless(block_given?)
            raise ArgumentError.new("No callback was passed as a listener")
          end
      
          key = listener_key
          if (listener_key == NOTHING)
            listener_key = listener
            key = ProcWrapper.new(listener)
          end
      
          channels[channel_name] ||= {}
          channels[channel_name][key] = listener
          return listener_key
        end

        # Removes the listener indicated by listener_key
        # from the channel indicated by
        # channel_name. Returns the registered proc, or
        # nil if none was found.
        def remove_listener(channel_name, listener_key)
          channel = channels[channel_name]
          return nil unless (channel)
          key = listener_key
          if (listener_key.instance_of?(Proc))
            key = ProcWrapper.new(listener_key)
          end
          if (channel.has_key?(key))
            return channel.delete(key)
          end
          return nil
        end

        # Calls all the procs registered on the channel
        # indicated by channel_name. If value is
        # specified, it is passed in to the procs,
        # otherwise they are called with no arguments.
        #
        #--
        #
        # Perhaps this should be private? Would it ever
        # make sense for an external class to call this
        # method directly?
        def notify_listeners(channel_name, *arguments)
          channel = channels[channel_name]
          return 0 unless (channel)
          listeners = channel.values
          listeners.each { |listener| listener.call(*arguments) }
          return listeners.size
        end

        private
        def channels
          @channels ||= {}
          return @channels
        end
      end
    end
  end
end
