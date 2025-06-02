# frozen_string_literal: true
module Kernel
  ###
  # An alias for Psych.dump_stream meant to be used with IRB.
  def y *objects
    puts Psych.dump_stream(*objects)
  end
  private :y
end

