# frozen_string_literal: true
require_relative '../rdoc'

##
# Namespace for the ri command line tool's implementation.
#
# See <tt>ri --help</tt> for details.

module RDoc::RI

  ##
  # Base RI error class

  class Error < RDoc::Error; end

  autoload :Driver, "#{__dir__}/ri/driver"
  autoload :Paths,  "#{__dir__}/ri/paths"
  autoload :Store,  "#{__dir__}/ri/store"

end
