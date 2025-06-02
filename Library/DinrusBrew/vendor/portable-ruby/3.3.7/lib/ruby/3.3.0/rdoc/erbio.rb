# frozen_string_literal: true
require 'erb'

##
# A subclass of ERB that writes directly to an IO.  Credit to Aaron Patterson
# and Masatoshi SEKI.
#
# To use:
#
#   erbio = RDoc::ERBIO.new '<%= "hello world" %>', nil, nil
#
#   File.open 'hello.txt', 'w' do |io|
#     erbio.result binding
#   end
#
# Note that binding must enclose the io you wish to output on.

class RDoc::ERBIO < ERB

  ##
  # Defaults +eoutvar+ to 'io', otherwise is identical to ERB's initialize

  def initialize str, trim_mode: nil, eoutvar: 'io'
    super(str, trim_mode: trim_mode, eoutvar: eoutvar)
  end

  ##
  # Instructs +compiler+ how to write to +io_variable+

  def set_eoutvar compiler, io_variable
    compiler.put_cmd    = "#{io_variable}.write"
    compiler.insert_cmd = "#{io_variable}.write"
    compiler.pre_cmd    = []
    compiler.post_cmd   = []
  end

end
