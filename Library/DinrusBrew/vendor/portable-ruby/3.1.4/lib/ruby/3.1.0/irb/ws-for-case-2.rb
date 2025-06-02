# frozen_string_literal: false
#
#   irb/ws-for-case-2.rb -
#   	$Release Version: 0.9.6$
#   	$Revision$
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#
# --
#
#
#

while true
  IRB::BINDING_QUEUE.push _ = binding
end
