# frozen_string_literal: false
require 'observer'

module DRb
  # The Observable module extended to DRb.  See Observable for details.
  module DRbObservable
    include Observable

    # Notifies observers of a change in state.  See also
    # Observable#notify_observers
    def notify_observers(*arg)
      if defined? @observer_state and @observer_state
        if defined? @observer_peers
          @observer_peers.each do |observer, method|
            begin
              observer.__send__(method, *arg)
            rescue
              delete_observer(observer)
            end
          end
        end
        @observer_state = false
      end
    end
  end
end
